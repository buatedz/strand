package strand;

class Prefs
{
	public static var downscroll:Bool = false;

	public static var scrollSpeed:Float = 0;
	public static var volume:Int = 70;
	public static var music:Bool = true;

	public static var framerate:String = 'auto';
	public static var vsync:Bool = false;
	public static var antialiasing:Bool = false;
	public static var fpsCounter:Bool = false;
	public static var discordRpc:Bool = true;
	public static var runSplitCharts:Bool = false;
	public static var syncSplitSpeed:Bool = true;
	public static var syncSplitBpm:Bool = true;

	public static var stackMerge:Float = 1;

	public static var drawSkip:Float = 1;

	public static var streamJson:Bool = true;

	public static var streamAhead:Int = 8000;

	public static var noteSkin:String = 'Classic';
	public static var middlescroll:Bool = false;
	public static var opponentNotes:Bool = true;

	public static var oppNoteAlpha:Float = 0.65;
	public static var showNotes:Bool = true;
	public static var drawHolds:Bool = true;
	public static var lightOppStrums:Bool = true;
	public static var lightPlayerStrums:Bool = true;

	public static var strumLitStyle:String = 'Full Anim';
	public static var noteSplashes:Bool = true;
	public static var oppNoteSplashes:Bool = true;
	public static var splashType:String = 'Default';

	public static var hideHud:Bool = false;

	public static var timeBar:String = 'Time Left';
	public static var showNps:Bool = true;

	public static var showRendered:Bool = false;

	public static final LIT_STYLES:Array<String> = ['Full Anim', 'BPM Based'];
	public static final TIME_BARS:Array<String> = ['Time Left', 'Time Elapsed', 'Song Name', 'Disabled'];
	public static final ALPHAS:Array<Float> = [0, 0.1, 0.25, 0.5, 0.65, 0.8, 1];

	public static final FRAMERATES:Array<String> = ['auto', '60', '120', '144', '240', 'unlimited'];
	public static inline final STEP:Float = 0.25;
	public static inline final FINE_STEP:Float = 0.05;
	public static inline final MAX_MERGE:Float = 10;
	public static inline final MAX_SKIP:Float = 32;
	public static final AHEADS:Array<Int> = [2000, 4000, 8000, 15000, 30000];

	static final FIELDS:Array<String> = [
		'downscroll', 'scrollSpeed', 'volume', 'music', 'framerate', 'vsync', 'antialiasing', 'fpsCounter', 'discordRpc', 'stackMerge', 'drawSkip', 'streamJson', 'streamAhead',
		'runSplitCharts', 'syncSplitSpeed', 'syncSplitBpm',
		'noteSkin', 'middlescroll', 'opponentNotes', 'oppNoteAlpha', 'showNotes', 'drawHolds', 'lightOppStrums', 'lightPlayerStrums',
		'strumLitStyle', 'noteSplashes', 'oppNoteSplashes', 'splashType', 'hideHud', 'timeBar', 'showNps', 'showRendered'
	];

	static var defaults:Map<String, Dynamic> = null;

	public static function load():Void
	{
		if (defaults == null) {
			defaults = new Map();
			for (f in FIELDS) defaults.set(f, Reflect.field(Prefs, f));
		}
		try {
			if (!sys.FileSystem.exists(Paths.options())) return;
			final o:Dynamic = haxe.Json.parse(sys.io.File.getContent(Paths.options()));
			for (f in FIELDS) {
				final v:Dynamic = Reflect.field(o, f);
				if (v != null && kind(v) == kind(Reflect.field(Prefs, f))) Reflect.setField(Prefs, f, v);
			}
		} catch (e:Dynamic) {
			trace('options.json not read: $e');
		}
		if (!FRAMERATES.contains(framerate)) framerate = 'auto';
		if (!strand.play.NoteSkin.SKINS.contains(noteSkin)) noteSkin = 'Classic';
		if (!strand.play.NoteSkin.SPLASHES.contains(splashType)) splashType = 'Default';
		if (!LIT_STYLES.contains(strumLitStyle)) strumLitStyle = 'Full Anim';
		if (!TIME_BARS.contains(timeBar)) timeBar = 'Time Left';
		oppNoteAlpha = Math.max(0, Math.min(1, oppNoteAlpha));
		stackMerge = Math.max(0, Math.min(MAX_MERGE, stackMerge));
		drawSkip = drawSkip < 0 ? -1 : Math.min(MAX_SKIP, drawSkip);
	}

	static function kind(v:Dynamic):Int
	{
		if (Std.isOfType(v, Bool)) return 1;
		if (Std.isOfType(v, String)) return 2;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return 3;
		return 0;
	}

	public static function save():Void
	{
		final o:Dynamic = {};
		for (f in FIELDS) Reflect.setField(o, f, Reflect.field(Prefs, f));
		try sys.io.File.saveContent(Paths.options(), haxe.Json.stringify(o, null, '  ')) catch (e:Dynamic) trace('options.json not saved: $e');
	}

	public static function reset():Void
	{
		if (defaults == null) return;
		for (f in FIELDS) Reflect.setField(Prefs, f, defaults.get(f));
		save();
	}

	public static function apply():Void
	{
		flixel.FlxG.sound.volume = volume / 100;
		var fps:Int = switch (framerate)
		{
			case '60': 60;
			case '120': 120;
			case '144': 144;
			case '240': 240;
			case 'unlimited': 1000;
			default:
				var hz:Int = 60;
				try {
					final d = lime.app.Application.current.window.display;
					if (d != null && d.currentMode != null && d.currentMode.refreshRate > 0) hz = d.currentMode.refreshRate;
				} catch (e:Dynamic) {}
				hz;
		}
		if (fps > flixel.FlxG.drawFramerate) {
			flixel.FlxG.updateFramerate = fps;
			flixel.FlxG.drawFramerate = fps;
		} else {
			flixel.FlxG.drawFramerate = fps;
			flixel.FlxG.updateFramerate = fps;
		}
		flixel.FlxSprite.defaultAntialiasing = antialiasing;
		strand.native.Vsync.set(vsync);
		Main.showFps(fpsCounter);
		Discord.setEnabled(discordRpc);
	}
}
