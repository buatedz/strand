package strand.states;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.media.Sound;
import strand.Paths;
import strand.Prefs;
import strand.Discord;
import strand.Songs;
import strand.play.Lanes;
import strand.play.NoteLayer;
import strand.play.NoteSkin;
import strand.play.NoteStore;
import strand.script.LuaScript;
import strand.script.ScriptApi;
import strand.ui.Term;

class PlayState extends FlxState
{
	static inline final LEAD_IN_MS:Float = 1500;
	static inline final VOICE_SYNC_MS:Float = 100;
	static inline final AUDIO_SNAP_MS:Float = 250;
	static inline final AUDIO_PULL:Float = 4;

	var song:SongInfo;
	var store:NoteStore;
	var layer:NoteLayer;
	public var scoreTxt:FlxText;
	public var renderedTxt:FlxText;
	public var timeTxt:FlxText;
	public var timeBarBG:FlxSprite;
	public var timeBar:FlxSprite;
	var sounds:Array<FlxSound> = [];
	var voiceDrift:Array<Int> = [];
	var raw:Array<Sound>;

	var songTime:Float = -LEAD_IN_MS;
	var started:Bool = false;
	var lengthMs:Float = 0;
	var speed:Float = 1;
	var splitParts:Array<strand.chart.ChartMeta.SplitPart> = [];
	var splitActive:Int = -1;
	var ending:Bool = false;

	public var chartNotesPassed:Float = 0;
	public var oppChartNotesPassed:Float = 0;
	public var chartNPS:Float = 0;
	public var oppChartNPS:Float = 0;
	public var chartTotalNotes:Float = 0;
	public var oppChartTotalNotes:Float = 0;
	public var chartMaxNPS:Float = 0;
	public var oppChartMaxNPS:Float = 0;

	public var npsSpeedMult:Float = 1;

	public var scripts(default, null):Array<LuaScript> = [];
	public var luaObjects(default, null):Map<String, FlxSprite> = new Map();
	public var camOther(default, null):FlxCamera;
	public var songPosition(get, never):Float;
	@:keep public var amountOfRenderedNotes:Int = 0;
	@:keep public var skippedCount:Float = 0;
	@:keep public var maxRenderedNotes:Int = 0;
	@:keep public var maxSkipped:Float = 0;
	@:keep public var mergedCount:Float = 0;
	@:keep public var maxMerged:Float = 0;
	@:keep public var ffmpegMode:Bool = false;
	@:keep public var chartNotes = {first: 0.0, written: 0.0, length: 0.0, capacity: 0.0};
	@:keep public var chartStream = {madeUntil: 0.0, finished: true};
	var scriptError:FlxText;
	var countdownCalled:Bool = false;

	inline function get_songPosition():Float
		return songTime;
	var fpsAvg:Float = 60;
	var adaptiveSkip:Float = 1;

	public function new(song:SongInfo, store:NoteStore, sounds:Array<Sound>)
	{
		super();
		this.song = song;
		this.store = store;
		this.raw = sounds;
	}

	override public function create():Void
	{
		super.create();
		bgColor = FlxColor.BLACK;
		final meta = store.entry.meta;
		speed = Prefs.scrollSpeed > 0 ? Prefs.scrollSpeed : (meta.speed > 0 ? meta.speed : 1);
		if (Prefs.runSplitCharts && meta.parts.length > 1) {
			splitParts = meta.parts.copy();
			splitParts.sort((a, b) -> a.startMs < b.startMs ? -1 : a.startMs > b.startMs ? 1 : 0);
		}
		chartTotalNotes = store.totals[NoteStore.PLAYER];
		oppChartTotalNotes = store.totals[NoteStore.OPP];

		for (i in 0...raw.length) {
			final s:FlxSound = new FlxSound().loadEmbedded(raw[i]);
			FlxG.sound.list.add(s);
			sounds.push(s);
			voiceDrift.push(0);
		}
		lengthMs = meta.lastMs + 1000;
		if (sounds.length > 0) lengthMs = Math.max(sounds[0].length, 1);

		final keys:Int = store.keys;
		final down:Bool = Prefs.downscroll;
		final splashes:Bool = Prefs.noteSplashes;
		final skin:NoteSkin = new NoteSkin(keys, Prefs.noteSkin, splashes ? Prefs.splashType : null);
		layer = new NoteLayer(store, skin);
		for (side in 0...2) for (k in 0...keys) layer.strumX.push(Lanes.strumX(keys, k, side, Prefs.middlescroll));
		layer.downscroll = down;
		layer.strumY = down ? FlxG.height - 150 : 50;
		layer.farY = down ? 0 : FlxG.height;
		layer.pxPerMs = 0.45 * speed;
		layer.smooth = Prefs.antialiasing;
		layer.showNotes = Prefs.showNotes;
		layer.drawHolds = Prefs.drawHolds;
		layer.showOpponent = Prefs.opponentNotes;
		layer.setOpponentAlpha(Prefs.middlescroll ? Prefs.oppNoteAlpha : 1);
		layer.lightOpp = Prefs.lightOppStrums;
		layer.lightPlayer = Prefs.lightPlayerStrums;
		final bpm:Float = meta.bpm > 0 ? meta.bpm : 100;
		layer.stepMs = 60000 / bpm / 4;
		layer.litMs = Prefs.strumLitStyle == 'BPM Based' ? layer.stepMs * 1.5 : 150;
		layer.splashPlayer = splashes;
		layer.splashOpp = splashes && Prefs.oppNoteSplashes;
		FlxG.game.addChildAt(layer, FlxG.game.getChildIndex(FlxG.camera.flashSprite) + 1);
		camOther = new FlxCamera();
		camOther.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(camOther, false);

		final hud:Bool = !Prefs.hideHud;
		if (hud && Prefs.timeBar != 'Disabled') {
			final barY:Float = down ? FlxG.height - 44 : 19;
			timeBarBG = new FlxSprite(FlxG.width / 2 - 200, barY + 8).makeGraphic(400, 19, FlxColor.BLACK);
			add(timeBarBG);
			timeBar = new FlxSprite(timeBarBG.x + 4, timeBarBG.y + 4).makeGraphic(392, 11, FlxColor.WHITE);
			timeBar.origin.set(0, 0);
			add(timeBar);
			timeTxt = hudText(barY, 32);
			timeTxt.font = Paths.font();
			add(timeTxt);
		}
		if (hud) {
			scoreTxt = hudText(down ? FlxG.height * 0.11 + 36 : FlxG.height * 0.89 + 36, 20);
			add(scoreTxt);
		}
		if (Prefs.showRendered) {
			renderedTxt = new FlxText(10, 0, 460, '', 16);
			renderedTxt.setFormat(Paths.vcr(), 16, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			renderedTxt.borderSize = 1.25;
			add(renderedTxt);
		}

		loadScripts();
		callScripts('onCreatePost', []);
	}

	function loadScripts():Void
	{
		final dir:String = Paths.scripts();
		if (!sys.FileSystem.exists(dir) || !sys.FileSystem.isDirectory(dir)) return;
		final files:Array<String> = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f.toLowerCase(), '.lua')) f];
		files.sort((a, b) -> a.toLowerCase() < b.toLowerCase() ? -1 : 1);
		for (f in files) {
			final s:LuaScript = new LuaScript(f);
			setScriptGlobals(s);
			ScriptApi.install(s, this);
			var code:String = null;
			try code = sys.io.File.getContent(dir + '/' + f) catch (e:Dynamic) s.lastError = Std.string(e);
			if (code != null && s.run(code)) {
				scripts.push(s);
				s.call('onCreate', []);
			}
			if (s.lastError != null) showScriptError(s);
		}
	}

	function setScriptGlobals(s:LuaScript):Void
	{
		final meta = store.entry.meta;
		s.set('songName', song.name);
		s.set('bpm', meta.bpm);
		s.set('curBpm', meta.bpm);
		s.set('scrollSpeed', speed);
		s.set('songLength', lengthMs);
		s.set('crochet', layer.stepMs * 4);
		s.set('stepCrochet', layer.stepMs);
		s.set('screenWidth', FlxG.width);
		s.set('screenHeight', FlxG.height);
		s.set('downscroll', Prefs.downscroll);
		s.set('middlescroll', Prefs.middlescroll);
		s.set('botPlay', true);
		s.set('chartStreaming', store.streaming);
		s.set('chartTotalNotes', chartTotalNotes);
		s.set('oppChartTotalNotes', oppChartTotalNotes);
		s.set('chartNoteCount', store.chartNoteCount);
		s.set('engineName', 'Strand');
		updateScriptGlobals(s);
	}

	function updateScriptGlobals(s:LuaScript):Void
	{
		s.set('songPosition', songTime);
		s.set('curStep', Math.floor(songTime / layer.stepMs));
		s.set('curBeat', Math.floor(songTime / (layer.stepMs * 4)));
		s.set('curDecStep', songTime / layer.stepMs);
		s.set('curDecBeat', songTime / (layer.stepMs * 4));
		s.set('chartNotesPassed', chartNotesPassed);
		s.set('oppChartNotesPassed', oppChartNotesPassed);
		s.set('chartNPS', chartNPS);
		s.set('oppChartNPS', oppChartNPS);
		s.set('chartMaxNPS', chartMaxNPS);
		s.set('oppChartMaxNPS', oppChartMaxNPS);
		s.set('chartNotesLoaded', store.chartNotesLoaded);
	}

	public function callScripts(func:String, args:Array<Dynamic>):Dynamic
	{
		var result:Dynamic = LuaScript.FUNCTION_CONTINUE;
		for (s in scripts) {
			if (s.closed) continue;
			final r:Dynamic = s.call(func, args);
			if (r == LuaScript.FUNCTION_STOP) result = r;
			if (s.lastError != null) showScriptError(s);
		}
		return result;
	}

	function showScriptError(s:LuaScript):Void
	{
		trace('Lua script ${s.name}: ${s.lastError}');
		if (scriptError == null) {
			scriptError = new FlxText(10, 10, FlxG.width - 20, '', 14);
			scriptError.setFormat(Paths.vcr(), 14, FlxColor.RED, LEFT, OUTLINE, FlxColor.BLACK);
			scriptError.cameras = [camOther];
			add(scriptError);
		}
		scriptError.text = s.name + ': ' + s.lastError;
		s.lastError = null;
	}

	function hudText(y:Float, size:Int):FlxText
	{
		final t:FlxText = new FlxText(0, y, FlxG.width, '', size);
		t.setFormat(Paths.vcr(), size, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		t.borderSize = size >= 32 ? 2 : 1.25;
		return t;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (ending) return;
		if (!countdownCalled) {
			countdownCalled = true;
			callScripts('onStartCountdown', []);
			callScripts('onCountdownStarted', []);
		}
		callScripts('onUpdate', [elapsed]);
		if (FlxG.keys.anyJustPressed([ESCAPE, BACKSPACE])) {
			stop();
			FlxG.switchState(() -> new MenuState('freeplay'));
			return;
		}

		songTime += elapsed * 1000;
		if (!started && songTime >= 0) {
			started = true;
			startSounds(Math.max(0, songTime));
			callScripts('onSongStart', []);
			Discord.playing(song.name, songTime, lengthMs);
		}
		if (started && sounds.length > 0 && sounds[0].playing) {
			final drift:Float = sounds[0].time - songTime;
			if (Math.abs(drift) > AUDIO_SNAP_MS) songTime = sounds[0].time;
			else songTime += drift * Math.min(1, elapsed * AUDIO_PULL);
			syncVoices();
		}
		store.songTime = songTime;

		if (songTime >= lengthMs) {
			finish();
			return;
		}

		if (elapsed > 0) fpsAvg += (1 / elapsed - fpsAvg) * 0.1;
		if (Prefs.drawSkip < 0) {
			final target:Float = FlxG.drawFramerate;
			if (fpsAvg < target * 0.9) adaptiveSkip = Math.min(32, adaptiveSkip * 1.15);
			else if (fpsAvg > target * 0.97) adaptiveSkip = Math.max(1, adaptiveSkip / 1.05);
			layer.skipPx = adaptiveSkip;
		} else layer.skipPx = Prefs.drawSkip;
		if (splitParts.length > 1) syncSplit();
		layer.scaleX = FlxG.scaleMode.scale.x;
		layer.scaleY = FlxG.scaleMode.scale.y;
		layer.render(songTime);

		updateStats();
		if (scripts.length > 0) {
			updateScriptVars();
			for (s in scripts) if (!s.closed) updateScriptGlobals(s);
			callScripts('onUpdatePost', [elapsed]);
		}
	}

	function syncSplit():Void
	{
		var active:Int = -1;
		for (i in 0...splitParts.length) {
			final p = splitParts[i];
			if (p.startMs > songTime) break;
			if (p.endMs >= songTime || active < 0) active = i;
		}
		if (active < 0 || active == splitActive) return;
		splitActive = active;
		final p = splitParts[active];
		if (Prefs.syncSplitSpeed && Prefs.scrollSpeed <= 0 && p.speed > 0) {
			speed = p.speed;
			layer.pxPerMs = 0.45 * speed;
		}
		if (Prefs.syncSplitBpm && p.bpm > 0) {
			layer.stepMs = 60000 / p.bpm / 4;
			if (Prefs.strumLitStyle == 'BPM Based') layer.litMs = layer.stepMs * 1.5;
		}
	}

	function updateScriptVars():Void
	{
		amountOfRenderedNotes = layer.drawnNotes;
		skippedCount = layer.skippedNotes;
		maxRenderedNotes = layer.maxDrawn;
		maxSkipped = layer.maxSkipped;
		mergedCount = layer.mergedNotes;
		maxMerged = layer.maxMerged;
		chartNotes.written = chartNotes.length = chartNotes.capacity = store.chartNotesLoaded;
		chartStream.madeUntil = store.streamMadeUntil;
		chartStream.finished = store.streamFinished;
	}

	function startSounds(at:Float):Void
	{
		final audio = lime.media.AudioManager.context;
		final alc = audio != null && audio.type == OPENAL ? audio.openal : null;
		final current = alc != null ? alc.getCurrentContext() : null;
		if (current != null) alc.suspendContext(current);
		for (s in sounds) s.play(true, at);
		if (current != null) alc.processContext(current);
	}

	function syncVoices():Void
	{
		final inst:Float = channelTime(sounds[0]);
		for (i in 1...sounds.length) {
			if (Math.abs(channelTime(sounds[i]) - inst) <= VOICE_SYNC_MS) {
				voiceDrift[i] = 0;
			} else if (++voiceDrift[i] >= 2) {
				voiceDrift[i] = 0;
				sounds[i].time = channelTime(sounds[0]);
			}
		}
	}

	static function channelTime(s:FlxSound):Float
		return @:privateAccess (s._channel != null ? s._channel.position : s.time);

	function updateStats():Void
	{
		final t:Float = songTime;
		chartNotesPassed = store.passed(t, NoteStore.PLAYER);
		oppChartNotesPassed = store.passed(t, NoteStore.OPP);
		final past:Float = t - 1000 * npsSpeedMult;
		chartNPS = chartNotesPassed - store.passed(past, NoteStore.PLAYER);
		oppChartNPS = oppChartNotesPassed - store.passed(past, NoteStore.OPP);
		if (chartNPS > chartMaxNPS) chartMaxNPS = chartNPS;
		if (oppChartNPS > oppChartMaxNPS) oppChartMaxNPS = oppChartNPS;

		if (scoreTxt != null) {
			var line:String = 'Notes: ' + Term.fmtInt(chartNotesPassed) + ' / ' + Term.fmtInt(chartTotalNotes);
			if (Prefs.showNps) line += ' | NPS: ' + Term.fmtInt(chartNPS) + ' (Max ' + Term.fmtInt(chartMaxNPS) + ')';
			if (Prefs.opponentNotes) {
				line += ' | Opponent: ' + Term.fmtInt(oppChartNotesPassed) + ' / ' + Term.fmtInt(oppChartTotalNotes);
				if (Prefs.showNps) line += ' | NPS: ' + Term.fmtInt(oppChartNPS) + ' (Max ' + Term.fmtInt(oppChartMaxNPS) + ')';
			}
			if (scoreTxt.text != line) scoreTxt.text = line;
		}
		if (timeTxt != null) {
			final p:Float = Math.max(0, Math.min(1, t / lengthMs));
			timeBar.scale.x = p;
			final s:String = switch (Prefs.timeBar)
			{
				case 'Time Elapsed': Term.mmss(Math.max(0, t));
				case 'Song Name': song.name;
				default: Term.mmss(Math.max(0, lengthMs - Math.max(0, t)));
			}
			if (timeTxt.text != s) timeTxt.text = s;
		}
		if (renderedTxt != null) {
			final meta = store.entry.meta;
			final lines:Array<String> = [
				'Rendered Notes: ' + Term.fmtInt(layer.drawnNotes) + ' (Max ' + Term.fmtInt(layer.maxDrawn) + ')',
				'Skipped: ' + Term.shortCount(layer.skippedNotes) + ' (Max ' + Term.shortCount(layer.maxSkipped) + ')'
					+ (Prefs.drawSkip < 0 ? ' at ' + Term.fmt1(adaptiveSkip) + ' px' : ''),
				'In Memory: ' + Term.shortCount(store.chartNotesLoaded) + ' of ' + Term.shortCount(meta.entries) + ' entries',
				'Cache Load: ' + Term.fmt1(store.cacheLoadSeconds * 1000) + ' ms'
			];
			if (store.streaming)
				lines.push('Stream JSON: ' + (store.streamError != null ? 'stopped: ' + store.streamError : store.streamFinished ? 'all ahead ready' : 'ready until ' + Term.mmss(store.streamMadeUntil)));
			final s:String = lines.join('\n');
			if (renderedTxt.text != s) {
				renderedTxt.text = s;
				renderedTxt.y = Prefs.downscroll ? 60 : FlxG.height - renderedTxt.height - 50;
			}
		}
	}

	function finish():Void
	{
		callScripts('onEndSong', []);
		ending = true;
		stop();
		FlxG.switchState(() -> new EndState(song));
	}

	function stop():Void
	{
		for (s in sounds) {
			s.stop();
			FlxG.sound.list.remove(s, true);
			s.destroy();
		}
		sounds = [];
	}

	override public function destroy():Void
	{
		if (layer != null) {
			if (layer.parent != null) layer.parent.removeChild(layer);
			layer.dispose();
		}
		if (store != null) store.dispose();
		for (s in scripts) {
			s.call('onDestroy', []);
			s.close();
		}
		scripts = [];
		super.destroy();
	}
}
