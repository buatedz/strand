package strand.states;

import flixel.FlxG;
import strand.Prefs;
import strand.Discord;
import strand.Songs;
import strand.play.NoteSkin;
import strand.ui.MenuList;
import strand.ui.Term;
import strand.ui.TermState;

class MenuState extends TermState
{
	static inline final HOLD_DELAY:Float = 0.35;
	static inline final HOLD_FIRST:Float = 0.1;
	static inline final HOLD_FASTEST:Float = 0.012;
	static inline final HOLD_SPEEDUP:Float = 3;

	var holdDir:Int = 0;
	var holdTime:Float = 0;
	var nextRepeat:Float = 0;
	var holdUnsaved:Bool = false;

	static var stack:Array<{id:String, sel:Int}> = null;

	var list:MenuList;
	var side:InfoGrid;
	var sideKey:String = '';
	var startIn:String;

	public function new(?startIn:String)
	{
		super();
		this.startIn = startIn;
	}

	override public function create():Void
	{
		super.create();
		Discord.menus();
		list = new MenuList(Term.PAD_LEFT, mainTop(), mainBottom() - mainTop());
		add(list);
		side = new InfoGrid(0, mainTop());
		add(side);
		if (stack == null || startIn == 'main') stack = [{id: 'main', sel: -1}];
		if (startIn == 'freeplay' && top().id != 'freeplay') stack.push({id: 'freeplay', sel: -1});
		render();
	}

	inline function top()
		return stack[stack.length - 1];

	function push(id:String):Void
	{
		top().sel = list.selected;
		stack.push({id: id, sel: -1});
		say('');
		render();
	}

	function pop():Void
	{
		if (stack.length <= 1) return;
		stack.pop();
		say('');
		render();
	}

	function render(keep:Bool = false):Void
	{
		final t = top();
		final rows:Array<MenuRow> = rowsFor(t.id);
		list.setRows(rows, keep);
		if (!keep && t.sel >= 0 && t.sel < rows.length) {
			list.selected = t.sel;
			list.redraw();
		}
		t.sel = list.selected;
		switch (t.id)
		{
			case 'main':
				setTitle([]);
				setHint(['w/s up/down  select', 'enter  open', 'esc  back']);
			case 'freeplay':
				setTitle(['freeplay']);
				setHint(['w/s up/down  select', 'enter  play', 'esc  back']);
			case 'options' | 'visuals' | 'hud' | 'split':
				setTitle(t.id == 'options' ? ['options'] : ['options', t.id == 'hud' ? 'hud' : t.id == 'split' ? 'split charts' : 'notes and strums']);
				setHint(['w/s up/down  select', 'a/d left/right  change', 'esc  back']);
			case 'credits':
				setTitle(['credits']);
				setHint(['w/s up/down  select', 'esc  back']);
			case 'exit':
				setTitle(['exit']);
				setHint(['w/s up/down  select', 'enter  confirm', 'esc  back']);
		}
		updateSide();
	}

	function onoff(b:Bool):String
		return b ? 'on' : 'off';

	function rowsFor(id:String):Array<MenuRow>
	{
		return switch (id)
		{
			case 'main': [
					{label: 'freeplay', value: Songs.list.length + (Songs.list.length == 1 ? ' song' : ' songs'), enter: () -> push('freeplay')},
					{label: 'options', value: '-', enter: () -> push('options')},
					{label: 'credits', value: '-', enter: () -> push('credits')},
					{gap: true},
					{label: 'exit', act: true, enter: () -> push('exit')}
				];
			case 'freeplay':
				final rows:Array<MenuRow> = [];
				for (s in Songs.list) rows.push({
					label: s.name,
					value: s.meta != null ? Term.mmss(s.lengthMs()) : '-',
					data: s,
					enter: () -> play(s)
				});
				if (rows.length == 0) {
					rows.push({label: 'no songs yet', value: '', muted: true, noSel: true});
					rows.push({label: 'charts go in assets/data/<song>/, audio in assets/songs/<song>/', noSel: true, act: true});
				}
				rows.push({gap: true});
				rows.push({label: 'back', act: true, enter: pop});
				rows;
			case 'options': [
					{label: 'downscroll', value: onoff(Prefs.downscroll), change: d -> Prefs.downscroll = !Prefs.downscroll},
					{label: 'scroll speed', value: Prefs.scrollSpeed <= 0 ? 'chart default' : Term.fmt1(Prefs.scrollSpeed) + 'x', change: changeSpeed, repeat: true},
					{label: 'notes and strums', value: '-', enter: () -> push('visuals')},
					{label: 'hud', value: '-', enter: () -> push('hud')},
					{label: 'split charts', value: onoff(Prefs.runSplitCharts), enter: () -> push('split')},
					{gap: true},
					{label: 'volume', value: Prefs.volume + '%', change: d -> Prefs.volume = Std.int(clamp(Prefs.volume + 10 * d, 0, 100)), repeat: true},
					{label: 'music', value: onoff(Prefs.music), change: d -> Prefs.music = !Prefs.music},
					{gap: true},
					{label: 'framerate', value: Prefs.framerate, change: d -> Prefs.framerate = cycle(Prefs.FRAMERATES, Prefs.framerate, d)},
					{label: 'vsync', value: onoff(Prefs.vsync), change: d -> Prefs.vsync = !Prefs.vsync},
					{label: 'antialiasing', value: onoff(Prefs.antialiasing), change: d -> Prefs.antialiasing = !Prefs.antialiasing},
					{label: 'fps counter', value: onoff(Prefs.fpsCounter), change: d -> Prefs.fpsCounter = !Prefs.fpsCounter},
					{label: 'discord rich presence', value: Discord.CLIENT_ID == '' ? 'off (no discord app id yet)' : onoff(Prefs.discordRpc), change: d -> Prefs.discordRpc = !Prefs.discordRpc},
					{gap: true},
					{label: 'stack merge', value: Prefs.stackMerge <= 0 ? 'off' : 'notes under ' + Prefs.stackMerge + ' ms apart', change: changeMerge, repeat: true},
					{label: 'draw skip', value: skipText(), change: changeSkip, repeat: true},
					{label: 'stream json', value: onoff(Prefs.streamJson), change: d -> Prefs.streamJson = !Prefs.streamJson},
					{label: 'stream ahead', value: (Prefs.streamAhead / 1000) + ' s' + (Prefs.streamJson ? '' : '  (stream json is off)'), change: d -> Prefs.streamAhead = cycle(Prefs.AHEADS, Prefs.streamAhead, d)},
					{gap: true},
					{label: 'cache.bin', value: Term.bytes(Songs.cache.fileBytes()) + '  (enter to tidy)', enter: tidyCache},
					{label: 'reset to defaults', act: true, enter: () -> {
						Prefs.reset();
						Prefs.apply();
						say('options reset.');
					}},
					{gap: true},
					{label: 'back', act: true, enter: pop}
				];
			case 'visuals': [
					{label: 'note skin', value: Prefs.noteSkin, change: d -> Prefs.noteSkin = cycle(NoteSkin.SKINS, Prefs.noteSkin, d)},
					{label: 'middlescroll', value: onoff(Prefs.middlescroll), change: d -> Prefs.middlescroll = !Prefs.middlescroll},
					{label: 'opponent notes', value: onoff(Prefs.opponentNotes), change: d -> Prefs.opponentNotes = !Prefs.opponentNotes},
					{label: 'opponent note alpha', value: Math.round(Prefs.oppNoteAlpha * 100) + '%  (middlescroll)', change: d -> Prefs.oppNoteAlpha = cycle(Prefs.ALPHAS, Prefs.oppNoteAlpha, d)},
					{label: 'show notes', value: onoff(Prefs.showNotes), change: d -> Prefs.showNotes = !Prefs.showNotes},
					{label: 'draw holds', value: onoff(Prefs.drawHolds), change: d -> Prefs.drawHolds = !Prefs.drawHolds},
					{gap: true},
					{label: 'light player strums', value: onoff(Prefs.lightPlayerStrums), change: d -> Prefs.lightPlayerStrums = !Prefs.lightPlayerStrums},
					{label: 'light opponent strums', value: onoff(Prefs.lightOppStrums), change: d -> Prefs.lightOppStrums = !Prefs.lightOppStrums},
					{label: 'strum light-up style', value: Prefs.strumLitStyle.toLowerCase(), change: d -> Prefs.strumLitStyle = cycle(Prefs.LIT_STYLES, Prefs.strumLitStyle, d)},
					{gap: true},
					{label: 'note splashes', value: onoff(Prefs.noteSplashes), change: d -> Prefs.noteSplashes = !Prefs.noteSplashes},
					{label: 'opponent splashes', value: onoff(Prefs.oppNoteSplashes), change: d -> Prefs.oppNoteSplashes = !Prefs.oppNoteSplashes},
					{label: 'splash type', value: Prefs.splashType, change: d -> Prefs.splashType = cycle(NoteSkin.SPLASHES, Prefs.splashType, d)},
					{gap: true},
					{label: 'back', act: true, enter: pop}
				];
			case 'hud': [
					{label: 'hide hud', value: onoff(Prefs.hideHud), change: d -> Prefs.hideHud = !Prefs.hideHud},
					{label: 'time bar', value: Prefs.timeBar.toLowerCase(), change: d -> Prefs.timeBar = cycle(Prefs.TIME_BARS, Prefs.timeBar, d)},
					{label: 'show nps', value: onoff(Prefs.showNps), change: d -> Prefs.showNps = !Prefs.showNps},
					{label: 'show rendered notes', value: onoff(Prefs.showRendered), change: d -> Prefs.showRendered = !Prefs.showRendered},
					{gap: true},
					{label: 'back', act: true, enter: pop}
				];
			case 'split': [
					{label: 'run split charts', value: onoff(Prefs.runSplitCharts), change: d -> {
						Prefs.runSplitCharts = !Prefs.runSplitCharts;
						Songs.scan();
					}},
					{label: 'sync scroll speed', value: onoff(Prefs.syncSplitSpeed), change: d -> Prefs.syncSplitSpeed = !Prefs.syncSplitSpeed},
					{label: 'sync bpm', value: onoff(Prefs.syncSplitBpm), change: d -> Prefs.syncSplitBpm = !Prefs.syncSplitBpm},
					{gap: true},
					{label: 'back', act: true, enter: pop}
				];
			case 'credits': [
					{label: 'engine', value: 'buatedz'},
					{label: 'based on', value: 'Threadripper Engine'},
					{label: 'framework', value: 'HaxeFlixel'},
					{label: 'note art', value: "Friday Night Funkin' by the Funkin' Crew"},
					{label: 'font', value: 'Space Mono by Colophon (OFL)'},
					{label: 'compression', value: 'LZMA SDK by Igor Pavlov'},
					{gap: true},
					{label: 'you', value: 'for playing'},
					{gap: true},
					{label: 'back', act: true, enter: pop}
				];
			case 'exit': [
					{label: 'quit Strand?', value: '', muted: true, noSel: true},
					{gap: true},
					{label: 'no, go back', enter: pop},
					{label: 'yes, quit', act: true, enter: () -> Sys.exit(0)}
				];
			default: [];
		}
	}

	function skipText():String
	{
		final v:Float = Prefs.drawSkip;
		if (v < 0) return 'adaptive (1 to 32 px)';
		if (v == 0) return 'off';
		return 'notes under ' + v + ' px apart';
	}

	function changeMerge(d:Int):Void
		Prefs.stackMerge = clamp(Prefs.stackMerge + Prefs.STEP * d, 0, Prefs.MAX_MERGE);

	function changeSkip(d:Int):Void
	{
		final v:Float = Prefs.drawSkip;
		if (v < 0) Prefs.drawSkip = d > 0 ? 0 : -1;
		else if (v <= 0 && d < 0) Prefs.drawSkip = -1;
		else Prefs.drawSkip = clamp(v + Prefs.STEP * d, 0, Prefs.MAX_SKIP);
	}

	function changeSpeed(d:Int):Void
	{
		if (Prefs.scrollSpeed <= 0) {
			if (d > 0) Prefs.scrollSpeed = 1;
			return;
		}
		if (d < 0 && Prefs.scrollSpeed <= 0.5) {
			Prefs.scrollSpeed = 0;
			return;
		}
		Prefs.scrollSpeed = Math.round(clamp(Prefs.scrollSpeed + 0.1 * d, 0.5, 10) * 10) / 10;
	}

	function tidyCache():Void
	{
		Songs.cache.maybeCompact(true);
		say('cache.bin tidied (' + Term.bytes(Songs.cache.fileBytes()) + ').');
	}

	static function clamp(v:Float, lo:Float, hi:Float):Float
		return v < lo ? lo : v > hi ? hi : v;

	static function cycle<T>(arr:Array<T>, v:T, d:Int):T
	{
		var i:Int = arr.indexOf(v);
		if (i < 0) i = 0;
		return arr[(i + d + arr.length) % arr.length];
	}

	function play(s:SongInfo):Void
	{
		top().sel = list.selected;
		FlxG.switchState(() -> new LoadState(s));
	}

	function updateSide():Void
	{
		final row:MenuRow = list.current();
		if (top().id != 'freeplay' || row == null || row.data == null) {
			sideKey = '';
			side.hideAll();
			return;
		}
		final s:SongInfo = row.data;
		if (s.meta == null) Songs.prewarm(s);
		final key:String = s.key + '|' + (s.meta != null) + '|' + s.building + '|' + s.error + '|' + Prefs.scrollSpeed;
		if (key == sideKey) return;
		sideKey = key;
		side.x = Math.max(list.rightEdge + Term.ch(8), Term.PAD_LEFT + Term.ch(40));
		final m = s.meta;
		final rows:Array<Array<String>> = [['song', s.name]];
		if (m != null) {
			rows.push(['bpm', Term.fmt1(m.bpm).split('.0').join('')]);
			var sp:String = Term.fmt1(m.speed) + 'x';
			if (Prefs.scrollSpeed > 0) sp += '  (shown at ' + Term.fmt1(Prefs.scrollSpeed) + 'x)';
			rows.push(['scroll speed', sp]);
			rows.push(['length', Term.mmss(s.lengthMs())]);
			rows.push(['notes', Term.fmtInt(m.notes)]);
			rows.push(['avg nps', Term.fmtInt(m.avgNps)]);
			rows.push(['peak nps', Term.fmtInt(m.peakNps)]);
			rows.push(null);
			rows.push(['chart', m.format + ', ' + m.keys + ' keys']);
			rows.push(['cache', Term.bytes(s.cacheBytes) + ' for ' + Term.shortCount(m.notes) + ' notes']);
		} else if (s.error != null) {
			rows.push(['chart', 'could not be read', 'hot']);
			rows.push(['', s.error.length > 60 ? s.error.substr(0, 60) + '...' : s.error, 'muted']);
		} else {
			rows.push(['chart', Term.bytes(s.bytes)]);
			rows.push(['stats', s.building ? 'reading the chart...' : 'shown after the first play', 'muted']);
		}
		side.show(rows);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (upPressed()) list.move(-1);
		if (downPressed()) list.move(1);
		if (upPressed() || downPressed()) top().sel = list.selected;
		final row:MenuRow = list.current();
		if (acceptPressed() && row != null) {
			if (row.enter != null) row.enter();
			else if (row.change != null) row.change(1);
			afterChange();
		} else if ((leftPressed() || rightPressed()) && row != null && row.change != null) {
			holdDir = leftPressed() ? -1 : 1;
			holdTime = 0;
			nextRepeat = HOLD_DELAY;
			row.change(holdDir);
			afterChange();
		} else if (holdDir != 0 && row != null && row.repeat == true && (holdDir < 0 ? leftHeld() : rightHeld())) {
			holdTime += elapsed;
			var changed:Bool = false;
			while (holdTime >= nextRepeat) {
				row.change(holdDir);
				nextRepeat += Math.max(HOLD_FASTEST, HOLD_FIRST / (1 + (holdTime - HOLD_DELAY) * HOLD_SPEEDUP));
				changed = true;
			}
			if (changed) {
				holdUnsaved = true;
				render(true);
			}
		} else if (backPressed()) {
			if (stack.length > 1) pop();
			else push('exit');
		}
		if (holdDir != 0 && !(holdDir < 0 ? leftHeld() : rightHeld())) {
			holdDir = 0;
			if (holdUnsaved) {
				holdUnsaved = false;
				afterChange();
			}
		}
		if (FlxG.mouse.wheel != 0) list.move(FlxG.mouse.wheel > 0 ? -1 : 1);

		if (top().id == 'freeplay') {
			updateSide();
			final row:MenuRow = list.current();
			if (row != null && row.data != null && (row.data : SongInfo).meta != null && row.value == '-') render(true);
		}
	}

	function afterChange():Void
	{
		if (['options', 'visuals', 'hud', 'split'].contains(top().id)) {
			Prefs.save();
			Prefs.apply();
		}
		if (stack.length > 0 && FlxG.state == this) render(true);
	}
}
