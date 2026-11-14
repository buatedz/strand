package strand.script;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import strand.Paths;
import strand.states.PlayState;

class ScriptApi
{
	public static function install(s:LuaScript, game:PlayState):Void
	{
		s.addFunction('getProperty', a -> {
			final path:Array<String> = str(a[0]).split('.');
			final owner:Dynamic = resolve(game, path);
			return owner == null ? null : field(game, owner, path[path.length - 1], path.length == 1);
		});
		s.addFunction('setProperty', a -> {
			final path:Array<String> = str(a[0]).split('.');
			final owner:Dynamic = resolve(game, path);
			if (owner == null) return false;
			Reflect.setProperty(owner, path[path.length - 1], a[1]);
			return true;
		});

		s.addFunction('makeLuaText', a -> {
			final tag:String = tagOf(a[0]);
			remove(game, tag, true);
			final t:FlxText = new FlxText(num(a[3], 0), num(a[4], 0), num(a[2], 0), str(a[1]), 16);
			t.setFormat(Paths.vcr(), 16, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
			game.luaObjects.set(tag, t);
			return null;
		});
		s.addFunction('setTextString', a -> withText(game, a, t -> t.text = str(a[1])));
		s.addFunction('setTextSize', a -> withText(game, a, t -> t.size = Std.int(num(a[1], 16))));
		s.addFunction('setTextWidth', a -> withText(game, a, t -> t.fieldWidth = num(a[1], 0)));
		s.addFunction('setTextBorder', a -> withText(game, a, t -> {
			t.borderSize = num(a[1], 1);
			t.borderColor = color(a[2], FlxColor.BLACK);
			if (t.borderStyle == NONE && t.borderSize > 0) t.borderStyle = OUTLINE;
		}));
		s.addFunction('setTextColor', a -> withText(game, a, t -> t.color = color(a[1], FlxColor.WHITE)));
		s.addFunction('setTextFont', a -> withText(game, a, t -> t.font = Fonts.find(str(a[1]))));
		s.addFunction('setTextItalic', a -> withText(game, a, t -> t.italic = a[1] == true));
		s.addFunction('setTextAlignment', a -> withText(game, a, t -> t.alignment = switch (str(a[1]).toLowerCase())
		{
			case 'right': RIGHT;
			case 'center': CENTER;
			default: LEFT;
		}));
		s.addFunction('getTextString', a -> {
			final t:FlxText = text(game, a[0]);
			return t != null ? t.text : null;
		});
		s.addFunction('addLuaText', a -> {
			final o:FlxSprite = text(game, a[0]);
			if (o != null && !game.members.contains(o)) game.add(o);
			return null;
		});
		s.addFunction('removeLuaText', a -> {
			remove(game, tagOf(a[0]), a[1] != false);
			return null;
		});

		s.addFunction('makeLuaSprite', a -> {
			final tag:String = tagOf(a[0]);
			remove(game, tag, true);
			final sprite:FlxSprite = new FlxSprite(num(a[2], 0), num(a[3], 0));
			final image:String = str(a[1]);
			if (image.length > 0) {
				final file:String = Paths.assets() + '/images/' + image + '.png';
				if (sys.FileSystem.exists(file)) sprite.loadGraphic(BitmapData.fromFile(file));
			}
			sprite.antialiasing = strand.Prefs.antialiasing;
			game.luaObjects.set(tag, sprite);
			return null;
		});
		s.addFunction('makeGraphic', a -> {
			final o:FlxSprite = game.luaObjects.get(tagOf(a[0]));
			if (o == null) return false;
			o.makeGraphic(Std.int(num(a[1], 1)), Std.int(num(a[2], 1)), color(a[3], FlxColor.WHITE));
			return true;
		});
		s.addFunction('addLuaSprite', a -> {
			final o:FlxSprite = game.luaObjects.get(tagOf(a[0]));
			if (o != null && !game.members.contains(o)) game.add(o);
			return null;
		});
		s.addFunction('removeLuaSprite', a -> {
			remove(game, tagOf(a[0]), a[1] != false);
			return null;
		});
		s.addFunction('setObjectCamera', a -> {
			final path:Array<String> = str(a[0]).split('.');
			final owner:Dynamic = resolve(game, path);
			final o:Dynamic = owner == null ? null : field(game, owner, path[path.length - 1], path.length == 1);
			if (!Std.isOfType(o, flixel.FlxBasic)) return false;
			final cam:FlxCamera = switch (str(a[1]).toLowerCase())
			{
				case 'other' | 'camother': game.camOther;
				default: FlxG.camera;
			}
			(o : flixel.FlxBasic).cameras = [cam];
			return true;
		});

		s.addFunction('getSongPosition', a -> game.songPosition);
		s.addFunction('getGameMemory', a -> cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE));
		s.addFunction('debugPrint', a -> {
			final line:String = [for (v in a) Std.string(v)].join(' ');
			trace('[${s.name}] $line');
			return null;
		});
		s.addFunction('close', a -> {
			s.close();
			return true;
		});
	}

	static function resolve(game:PlayState, path:Array<String>):Dynamic
	{
		if (path.length == 1) return game;
		var o:Dynamic = field(game, game, path[0], true);
		for (i in 1...path.length - 1) {
			if (o == null) return null;
			o = Reflect.getProperty(o, path[i]);
		}
		return o;
	}

	static function field(game:PlayState, owner:Dynamic, name:String, top:Bool):Dynamic
	{
		if (top && game.luaObjects.exists(name)) return game.luaObjects.get(name);
		return Reflect.getProperty(owner, name);
	}

	static function remove(game:PlayState, tag:String, destroy:Bool):Void
	{
		final o:FlxSprite = game.luaObjects.get(tag);
		if (o == null) return;
		game.remove(o, true);
		if (destroy) {
			o.destroy();
			game.luaObjects.remove(tag);
		}
	}

	static function text(game:PlayState, tag:Dynamic):FlxText
	{
		final o:FlxSprite = game.luaObjects.get(tagOf(tag));
		return Std.isOfType(o, FlxText) ? cast o : null;
	}

	static function withText(game:PlayState, a:Array<Dynamic>, f:FlxText->Void):Bool
	{
		final t:FlxText = text(game, a[0]);
		if (t == null) return false;
		f(t);
		return true;
	}

	static inline function tagOf(v:Dynamic):String
		return StringTools.replace(str(v), '.', '');

	static inline function str(v:Dynamic):String
		return v == null ? '' : Std.string(v);

	static function num(v:Dynamic, fallback:Float):Float
	{
		if (v == null) return fallback;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
		final f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? fallback : f;
	}

	static function color(v:Dynamic, fallback:FlxColor):FlxColor
	{
		if (v == null) return fallback;
		var s:String = StringTools.trim(Std.string(v));
		if (StringTools.startsWith(s, '#')) s = s.substr(1);
		else if (StringTools.startsWith(s.toLowerCase(), '0x')) s = s.substr(2);
		if (s.length == 6) s = 'FF' + s;
		if (s.length != 8) return fallback;
		var n:Int = 0;
		for (i in 0...8) {
			final c:Int = s.charCodeAt(i);
			final d:Int = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
			if (d < 0) return fallback;
			n = (n << 4) | d;
		}
		return n;
	}
}

class Fonts
{
	static var loaded:Map<String, String> = new Map();

	public static function find(file:String):String
	{
		if (loaded.exists(file)) return loaded.get(file);
		var name:String = Paths.vcr();
		final embedded:String = 'embed/fonts/' + file;
		if (openfl.utils.Assets.exists(embedded, FONT)) name = embedded;
		else {
			final windir:String = Sys.getEnv('WINDIR');
			for (path in [Paths.assets() + '/fonts/' + file, (windir != null ? windir : 'C:/Windows') + '/Fonts/' + file]) {
				if (!sys.FileSystem.exists(path)) continue;
				try {
					final f:openfl.text.Font = openfl.text.Font.fromFile(path);
					if (f != null) {
						openfl.text.Font.registerFont(f);
						name = f.fontName;
						break;
					}
				} catch (e:Dynamic) {}
			}
		}
		loaded.set(file, name);
		return name;
	}
}
