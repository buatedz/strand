package strand.ui;

import flixel.text.FlxText;
import openfl.text.TextField;
import openfl.text.TextFormat;

class Term
{
	public static inline final BG:Int = 0xFF101114;
	public static inline final FG:Int = 0xFFE2E0DC;
	public static inline final DIM:Int = 0xFF787480;
	public static inline final FAINT:Int = 0xFF4C4A54;
	public static inline final HINT:Int = 0xFF5C5A62;
	public static inline final ACCENT:Int = 0xFFF0A848;

	public static inline final SIZE:Int = 16;
	public static inline final LINE:Float = 24;
	public static inline final PAD_LEFT:Float = 128;
	public static inline final PAD_TOP:Float = 56;
	public static inline final PAD_BOTTOM:Float = 18;

	public static var fontName(default, null):String = null;
	public static var charW(default, null):Float = 9.6;

	public static function init():Void
	{
		final font = openfl.utils.Assets.getFont(strand.Paths.font());
		fontName = font != null ? font.fontName : '_typewriter';
		final tf:TextField = new TextField();
		tf.defaultTextFormat = new TextFormat(fontName, SIZE);
		tf.embedFonts = font != null;
		tf.text = '0000000000';
		charW = tf.textWidth / 10;
		if (charW <= 0) charW = SIZE * 0.6;
	}

	public static function text(x:Float, y:Float, s:String, color:Int, size:Int = SIZE):FlxText
	{
		final t:FlxText = new FlxText(x, y, 0, s, size);
		t.setFormat(strand.Paths.font(), size, color);
		t.antialiasing = strand.Prefs.antialiasing;
		t.active = false;
		return t;
	}

	public static inline function ch(n:Float):Float
		return n * charW;

	public static function fmtInt(v:Float):String
	{
		final neg:Bool = v < 0;
		var s:String = Std.string(Math.fround(Math.abs(v)));
		if (s.indexOf('e') != -1 || s.indexOf('.') != -1) s = Std.string(Math.round(Math.abs(v)));
		var out:String = '';
		var n:Int = 0;
		var i:Int = s.length;
		while (i-- > 0) {
			out = s.charAt(i) + out;
			if (++n % 3 == 0 && i > 0) out = ',' + out;
		}
		return (neg ? '-' : '') + out;
	}

	public static function fmt1(v:Float):String
	{
		final r:Float = Math.fround(v * 10) / 10;
		final s:String = Std.string(r);
		return s.indexOf('.') == -1 ? s + '.0' : s;
	}

	public static function mmss(ms:Float):String
	{
		if (ms < 0 || Math.isNaN(ms)) ms = 0;
		final s:Int = Math.floor(ms / 1000);
		final h:Int = Std.int(s / 3600);
		final m:Int = Std.int((s % 3600) / 60);
		final sec:String = StringTools.lpad(Std.string(s % 60), '0', 2);
		return h > 0 ? h + ':' + StringTools.lpad(Std.string(m), '0', 2) + ':' + sec : m + ':' + sec;
	}

	public static function bytes(n:Float):String
	{
		if (n < 1024) return Std.int(n) + ' B';
		if (n < 1048576) return fmt1(n / 1024) + ' KB';
		if (n < 1073741824) return fmt1(n / 1048576) + ' MB';
		return fmt1(n / 1073741824) + ' GB';
	}

	public static function memory(n:Float, unit:String):String
	{
		return switch (unit)
		{
			case 'kb': fmtInt(n / 1e3) + ' KB';
			case 'mb': fmt1(n / 1e6) + ' MB';
			case 'gb': fmt2(n / 1e9) + ' GB';
			case 'kib': fmtInt(n / 1024) + ' KiB';
			case 'mib': fmt1(n / 1048576) + ' MiB';
			case 'gib': fmt2(n / 1073741824) + ' GiB';
			default: bytes(n);
		}
	}

	static function fmt2(v:Float):String
	{
		final s:String = Std.string(Math.round(v * 100) / 100);
		final dot:Int = s.indexOf('.');
		return dot < 0 ? s + '.00' : s.length - dot == 2 ? s + '0' : s;
	}

	public static function shortCount(v:Float):String
	{
		if (v < 10000) return fmtInt(v);
		if (v < 1e6) return fmt1(v / 1e3) + 'k';
		if (v < 1e9) return fmt1(v / 1e6) + 'M';
		return fmt1(v / 1e9) + 'B';
	}

	public static function bar(f:Float, w:Int):String
	{
		if (Math.isNaN(f)) f = 0;
		final n:Int = Math.round(Math.max(0, Math.min(1, f)) * w);
		return '[' + StringTools.rpad('', '#', n) + StringTools.rpad('', '.', w - n) + ']';
	}
}
