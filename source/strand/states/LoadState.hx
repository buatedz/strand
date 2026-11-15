package strand.states;

import flixel.FlxG;
import flixel.text.FlxText;
import openfl.media.Sound;
import strand.Prefs;
import strand.Discord;
import strand.Songs;
import strand.cache.BinCache;
import strand.cache.BinCache.CacheEntry;
import strand.chart.ChartLoader;
import strand.play.NoteStore;
import strand.ui.Term;
import strand.ui.TermState;

class LoadState extends TermState
{
	var song:SongInfo;
	var line:FlxText;
	var detail:FlxText;
	var done:Bool = false;
	var failed:String = null;
	var store:NoteStore = null;
	var sounds:Array<Sound> = [];
	var phase:String = 'starting';
	var phaseProgress:Float = -1;
	var started:Float = 0;
	var cancel:Bool = false;

	public function new(song:SongInfo)
	{
		super();
		this.song = song;
	}

	override public function create():Void
	{
		super.create();
		setTitle(['freeplay', song.name]);
		setHint(['esc  back']);
		line = Term.text(Term.PAD_LEFT + Term.ch(2), mainTop(), '', Term.FG);
		detail = Term.text(Term.PAD_LEFT + Term.ch(2), mainTop() + Term.LINE, '', Term.DIM);
		add(line);
		add(detail);
		started = haxe.Timer.stamp();
		Discord.loading(song.name);
		sys.thread.Thread.create(work);
	}

	function work():Void
	{
		try {
			phase = 'waiting for the background reader';
			Songs.waitFor(song.key);
			phase = 'checking cache.bin';
			final entry:CacheEntry = ChartLoader.entryFor(Songs.cache, song.key, song.paths, Songs.threads());
			Songs.refresh(song);
			if (cancel) {
				done = true;
				return;
			}
			store = new NoteStore(Songs.cache, entry, Prefs.stackMerge);
			final streamIt:Bool = Prefs.streamJson && entry.blocks.length > 1;
			if (streamIt) {
				phase = 'stream json: getting the first notes ready';
				store.startStream(0, Prefs.streamAhead);
			} else {
				phase = 'loading notes';
				store.loadAll(p -> phaseProgress = p);
			}
			if (cancel) {
				done = true;
				return;
			}
			if (Prefs.music) {
				phase = 'loading audio';
				phaseProgress = -1;
				for (f in Songs.audioFiles(song.folder)) {
					try {
						final s:Sound = Sound.fromFile(f);
						if (s != null) sounds.push(s);
					} catch (e:Dynamic) {
						trace('Could not load "$f": $e');
					}
				}
			}
			done = true;
		} catch (e:Dynamic) {
			failed = Std.string(e);
		}
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (failed != null) {
			line.text = 'could not load this song.';
			line.color = Term.ACCENT;
			detail.text = failed;
			if (backPressed() || acceptPressed()) FlxG.switchState(() -> new MenuState('freeplay'));
			return;
		}
		if (done) {
			if (cancel) {
				if (store != null) store.dispose();
				FlxG.switchState(() -> new MenuState('freeplay'));
			} else FlxG.switchState(() -> new PlayState(song, store, sounds));
			done = false;
			return;
		}
		var p:String = phase;
		var f:Float = phaseProgress;
		if (BinCache.status != null) {
			p = BinCache.status;
			f = BinCache.progress;
		} else if (ChartLoader.status != null) {
			p = ChartLoader.status;
			f = ChartLoader.progress;
		}
		line.text = p + (f >= 0 ? '  ' + Term.bar(f, 20) + ' ' + Math.floor(f * 100) + '%' : '');
		detail.text = Term.mmss((haxe.Timer.stamp() - started) * 1000) + ' so far';
		if (backPressed()) {
			cancel = true;
			say('going back once this step ends...');
		}
	}
}
