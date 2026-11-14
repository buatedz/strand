package;

import flixel.FlxG;
import flixel.FlxGame;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import strand.Prefs;
import strand.Songs;
import strand.ui.Term;

class Main extends Sprite
{
	static var fps:TextField = null;
	static var fpsFrames:Int = 0;
	static var fpsTime:Float = 0;
	static var peakMem:Float = 0;

	public function new()
	{
		super();
		Prefs.load();
		Term.init();
		Songs.init();
		addChild(new FlxGame(1280, 720, strand.states.MenuState, 60, 60, true, false));
		FlxG.mouse.visible = false;
		FlxG.mouse.useSystemCursor = true;
		FlxG.autoPause = false;
		FlxG.fixedTimestep = false;
		FlxG.sound.muteKeys = [];
		FlxG.sound.volumeUpKeys = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.soundTrayEnabled = false;
		Prefs.apply();
	}

	public static function showFps(on:Bool):Void
	{
		if (on && fps == null) {
			fps = new TextField();
			fps.selectable = false;
			fps.mouseEnabled = false;
			fps.embedFonts = Term.fontName != '_typewriter';
			fps.defaultTextFormat = new TextFormat(Term.fontName, 12, Term.HINT & 0xFFFFFF);
			fps.width = 360;
			fps.x = 8;
			fps.y = 4;
			fpsTime = haxe.Timer.stamp();
			fps.addEventListener(Event.ENTER_FRAME, tick);
			FlxG.stage.addChild(fps);
		} else if (!on && fps != null) {
			fps.removeEventListener(Event.ENTER_FRAME, tick);
			if (fps.parent != null) fps.parent.removeChild(fps);
			fps = null;
		}
	}

	static function tick(_):Void
	{
		fpsFrames++;
		final color:Int = Std.isOfType(FlxG.state, strand.states.PlayState) ? 0xFFFFFF : Term.HINT & 0xFFFFFF;
		if (fps.textColor != color) fps.textColor = color;
		final now:Float = haxe.Timer.stamp();
		if (now - fpsTime >= 0.5) {
			final mem:Float = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			if (mem > peakMem) peakMem = mem;
			fps.text = 'fps ' + Math.round(fpsFrames / (now - fpsTime)) + '   mem ' + Term.bytes(mem) + '   peak ' + Term.bytes(peakMem);
			fpsFrames = 0;
			fpsTime = now;
		}
	}
}
