package strand.play;

import haxe.io.Bytes;
import openfl.Vector;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.utils.ByteArray;

typedef SubTex =
{
	name:String,
	x:Int,
	y:Int,
	w:Int,
	h:Int,
	rot:Bool,
	fx:Int,
	fy:Int,
	fw:Int,
	fh:Int
}

class Sparrow
{
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var subs(default, null):Array<SubTex> = [];
	public var id(default, null):Int = nextId++;

	static var nextId:Int = 0;

	var px:ByteArray;

	public function new(bmp:BitmapData, xml:String)
	{
		width = bmp.width;
		height = bmp.height;
		px = bmp.getPixels(bmp.rect);
		if (xml.charCodeAt(0) == 0xFEFF) xml = xml.substr(1);
		for (node in Xml.parse(xml).firstElement().elementsNamed('SubTexture')) {
			inline function num(a:String, d:Int):Int
			{
				final v:String = node.get(a);
				return v == null ? d : Std.parseInt(v);
			}
			final w:Int = num('width', 0), h:Int = num('height', 0);
			final rot:Bool = node.get('rotated') == 'true';
			subs.push({
				name: node.get('name'),
				x: num('x', 0),
				y: num('y', 0),
				w: w,
				h: h,
				rot: rot,
				fx: num('frameX', 0),
				fy: num('frameY', 0),
				fw: num('frameWidth', rot ? h : w),
				fh: num('frameHeight', rot ? w : h)
			});
		}
	}

	public function frames(prefix:String):Array<SubTex>
	{
		final out:Array<SubTex> = [];
		for (s in subs) {
			if (!StringTools.startsWith(s.name, prefix)) continue;
			final rest:String = StringTools.trim(s.name.substr(prefix.length));
			if (rest.length > 0 && !~/^[0-9]+$/.match(rest)) continue;
			out.push(s);
		}
		out.sort((a, b) -> a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
		return out;
	}

	public inline function argb(x:Int, y:Int):Int
	{
		final o:Int = (y * width + x) * 4;
		return (px[o] << 24) | (px[o + 1] << 16) | (px[o + 2] << 8) | px[o + 3];
	}

	public static function load(dir:String, name:String):Sparrow
	{
		final disk:String = strand.Paths.assets() + '/images/' + dir + '/' + name;
		try {
			if (sys.FileSystem.exists(disk + '.png') && sys.FileSystem.exists(disk + '.xml'))
				return new Sparrow(BitmapData.fromFile(disk + '.png'), sys.io.File.getContent(disk + '.xml'));
		} catch (e:Dynamic) {
			trace('$disk not loaded: $e');
		}
		final emb:String = 'embed/images/' + dir + '/' + name;
		if (!openfl.utils.Assets.exists(emb + '.png')) return null;
		return new Sparrow(openfl.utils.Assets.getBitmapData(emb + '.png', false), openfl.utils.Assets.getText(emb + '.xml'));
	}
}

class NoteSkin
{
	public static final SKINS:Array<String> = ['Classic', 'HSlice + JS'];
	public static final SPLASHES:Array<String> = ['Default', 'Vanilla', 'Classic', 'Diamond', 'Electric', 'Sparkles'];
	static final SPLASH_COLORS:Array<String> = ['purple', 'blue', 'green', 'red'];

	public var atlas(default, null):BitmapData;
	public var rects(default, null):Vector<Float> = new Vector<Float>();

	public var tileW(default, null):Array<Float> = [];
	public var tileH(default, null):Array<Float> = [];

	public var strum(default, null):Array<Int> = [];
	public var confirm(default, null):Array<Array<Int>> = [];
	public var note(default, null):Array<Int> = [];

	public var holdPiece(default, null):Array<Int> = [];
	public var holdEnd(default, null):Array<Int> = [];

	public var splash(default, null):Array<Array<Array<Int>>> = [];

	public var splashOff(default, null):Array<Array<Array<Float>>> = [];
	public var splashFps(default, null):Array<Int> = [22, 26];

	public var scale(default, null):Float;
	public var keys(default, null):Int;

	var cells:Array<Cell> = [];
	var cellOf:Map<String, Int> = new Map();

	public function new(keys:Int, skinName:String, splashName:Null<String>)
	{
		this.keys = keys;
		scale = Lanes.scale(keys);
		final file:String = 'NOTE_assets' + postfix(skinName);
		final main:Sparrow = Sparrow.load('noteskins', file);
		final fallback:Sparrow = file == 'NOTE_assets-classic' ? main : Sparrow.load('noteskins', 'NOTE_assets-classic');
		final skin:Sparrow = main != null ? main : fallback;
		final precoloured:Bool = StringTools.endsWith(file, '-hslice_+_js') && main != null;

		for (l in 0...keys) {
			final shape:Int = Lanes.shape(keys, l);
			final rgb:Array<Int> = Lanes.RGB[Lanes.color(keys, l) % Lanes.RGB.length];

			final own:Bool = skin.frames(Lanes.STRUM_ANIMS[shape]).length > 0;
			final src:Sparrow = own ? skin : fallback;
			final pal:Array<Int> = own && precoloured ? null : rgb;
			strum.push(first(src, Lanes.STRUM_ANIMS[shape], null, 1));
			confirm.push(all(src, Lanes.PRESS_ANIMS[shape] + ' confirm', pal, 1));
			final na:String = Lanes.NOTE_ANIMS[shape];
			note.push(first(src, na + '0', pal, 1, na));
			holdPiece.push(first(src, na + ' hold piece', pal, 0.6));
			var end:Int = first(src, na + ' hold end', pal, 0.6);
			if (end < 0 && shape == Lanes.LEFT) end = first(src, 'pruple end hold', pal, 0.6);
			holdEnd.push(end);
		}

		if (splashName != null) loadSplashes(splashName);
		pack();
	}

	public static function postfix(name:String):String
		return name == null || name == 'Default' ? '' : '-' + StringTools.replace(StringTools.trim(name).toLowerCase(), ' ', '_');

	function loadSplashes(name:String):Void
	{
		final file:String = 'noteSplashes' + postfix(name);
		var sp:Sparrow = Sparrow.load('noteSplashes', file);
		var cfg:String = readText('noteSplashes', file + '.txt');
		if (sp == null) {
			sp = Sparrow.load('noteSplashes', 'noteSplashes');
			cfg = readText('noteSplashes', 'noteSplashes.txt');
		}
		if (sp == null) return;
		var anim:String = 'note splash';
		final offs:Array<Array<Float>> = [];
		if (cfg != null) {
			final lines:Array<String> = [for (l in cfg.split('\n')) if (StringTools.trim(l).length > 0) StringTools.trim(l)];
			if (lines.length > 0) anim = lines[0];
			if (lines.length > 1) {
				final f:Array<String> = lines[1].split(' ');
				final a:Null<Int> = Std.parseInt(f[0]), b:Null<Int> = Std.parseInt(f.length > 1 ? f[1] : f[0]);
				if (a != null && b != null) splashFps = [a, b];
			}
			for (i in 2...lines.length) {
				final f:Array<String> = lines[i].split(' ');
				if (f.length < 2) continue;
				final x:Float = Std.parseFloat(f[0]), y:Float = Std.parseFloat(f[1]);
				if (!Math.isNaN(x) && !Math.isNaN(y)) offs.push([x, y]);
			}
		}
		if (offs.length == 0) offs.push([0, 0]);

		var count:Int = 0;
		while (count < 8) {
			var ok:Bool = true;
			for (c in SPLASH_COLORS) if (sp.frames('$anim $c ${count + 1}').length == 0) ok = false;
			if (!ok) break;
			count++;
		}
		if (count == 0) return;
		final mult:Float = scale / 0.7;
		for (l in 0...keys) {
			final shape:Int = Lanes.shape(keys, l);
			final dir:Int = shape < 4 ? shape : Lanes.UP;
			final rgb:Array<Int> = Lanes.RGB[Lanes.color(keys, l) % Lanes.RGB.length];
			final anims:Array<Array<Int>> = [];
			final where:Array<Array<Float>> = [];
			for (a in 0...count) {
				final frames:Array<SubTex> = sp.frames('$anim ${SPLASH_COLORS[dir]} ${a + 1}');
				anims.push([for (f in frames) add(sp, f, rgb, mult, 0.6)]);

				final o:Array<Float> = offs[wrap(dir + a * 4, offs.length)];
				final f0:SubTex = frames[0];
				where.push([
					-Lanes.SWAG_WIDTH * 0.95 - 10 - o[0] + f0.fw / 2 * (1 - mult),
					-Lanes.SWAG_WIDTH - 10 - o[1] + f0.fh / 2 * (1 - mult)
				]);
			}
			splash.push(anims);
			splashOff.push(where);
		}
	}

	static function wrap(i:Int, n:Int):Int
		return n <= 1 ? 0 : i % n;

	static function readText(dir:String, file:String):String
	{
		final disk:String = strand.Paths.assets() + '/images/' + dir + '/' + file;
		try {
			if (sys.FileSystem.exists(disk)) return sys.io.File.getContent(disk);
		} catch (e:Dynamic) {}
		final emb:String = 'embed/images/' + dir + '/' + file;
		return openfl.utils.Assets.exists(emb) ? openfl.utils.Assets.getText(emb) : null;
	}

	function first(sp:Sparrow, prefix:String, pal:Array<Int>, alpha:Float, ?alt:String):Int
	{
		var f:Array<SubTex> = sp.frames(prefix);
		if (f.length == 0 && alt != null) f = sp.frames(alt);
		return f.length > 0 ? add(sp, f[0], pal, 1, alpha, true) : -1;
	}

	function all(sp:Sparrow, prefix:String, pal:Array<Int>, alpha:Float):Array<Int>
		return [for (f in sp.frames(prefix)) add(sp, f, pal, 1, alpha, true)];

	function add(sp:Sparrow, f:SubTex, pal:Array<Int>, mult:Float, alpha:Float, noteScale:Bool = false):Int
	{
		final s:Float = noteScale ? scale : mult;
		final key:String = sp.id + ':' + sp.subs.indexOf(f) + ':' + (pal == null ? 'raw' : pal.join(',')) + ':' + s + ':' + alpha;
		if (cellOf.exists(key)) return cellOf.get(key);
		final id:Int = cells.length;
		cells.push(new Cell(sp, f, pal, s, alpha));
		cellOf.set(key, id);
		return id;
	}

	function pack():Void
	{
		for (c in cells) c.bake();
		final order:Array<Cell> = cells.copy();
		order.sort((a, b) -> b.h - a.h);
		final W:Int = 4096, PAD:Int = 2;
		var x:Int = PAD, y:Int = PAD, rowH:Int = 0;
		for (c in order) {
			if (x + c.w + PAD > W) {
				x = PAD;
				y += rowH + PAD;
				rowH = 0;
			}
			c.ax = x;
			c.ay = y;
			x += c.w + PAD;
			if (c.h > rowH) rowH = c.h;
		}
		final H:Int = y + rowH + PAD;
		final buf:Bytes = Bytes.alloc(W * H * 4);
		buf.fill(0, buf.length, 0);
		for (c in cells) {
			for (row in 0...c.h) buf.blit(((c.ay + row) * W + c.ax) * 4, c.px, row * c.w * 4, c.w * 4);
			c.px = null;
		}
		atlas = new BitmapData(W, H, true, 0);
		final ba:ByteArray = ByteArray.fromBytes(buf);
		ba.endian = openfl.utils.Endian.BIG_ENDIAN;
		ba.position = 0;
		atlas.setPixels(new Rectangle(0, 0, W, H), ba);
		for (c in cells) {
			rects.push(c.ax);
			rects.push(c.ay);
			rects.push(c.w);
			rects.push(c.h);
			tileW.push(c.w);
			tileH.push(c.h);
		}

		for (l in 0...holdPiece.length) {
			final id:Int = holdPiece[l];
			if (id < 0) continue;
			final c:Cell = cells[id];
			final cut:Int = c.h > 4 ? 1 : 0;
			holdPiece[l] = Std.int(rects.length / 4);
			rects.push(c.ax);
			rects.push(c.ay + cut);
			rects.push(c.w);
			rects.push(c.h - cut * 2);
			tileW.push(c.w);
			tileH.push(c.h - cut * 2);
		}
		cells = null;
		cellOf = null;
	}

	public function dispose():Void
	{
		if (atlas != null) atlas.dispose();
		atlas = null;
	}
}

private class Cell
{
	public var w:Int;
	public var h:Int;
	public var ax:Int = 0;
	public var ay:Int = 0;

	public var px:Bytes;

	var sp:Sparrow;
	var f:SubTex;
	var pal:Array<Int>;
	var s:Float;
	var alpha:Float;

	public function new(sp:Sparrow, f:SubTex, pal:Array<Int>, s:Float, alpha:Float)
	{
		this.sp = sp;
		this.f = f;
		this.pal = pal;
		this.s = s;
		this.alpha = alpha;
		w = Std.int(Math.max(1, Math.ceil(f.fw * s)));
		h = Std.int(Math.max(1, Math.ceil(f.fh * s)));
	}

	public function bake():Void
	{
		px = Bytes.alloc(w * h * 4);

		final cw:Int = f.rot ? f.h : f.w;
		final ch:Int = f.rot ? f.w : f.h;
		final N:Int = s >= 0.99 ? 1 : 3;
		final inv:Float = 1 / (N * N);
		var rr:Float = 0, rg:Float = 0, rb:Float = 0, gr:Float = 0, gg:Float = 0, gb:Float = 0, br:Float = 0, bg:Float = 0, bb:Float = 0;
		if (pal != null) {
			rr = ((pal[0] >> 16) & 0xFF) / 255;
			rg = ((pal[0] >> 8) & 0xFF) / 255;
			rb = (pal[0] & 0xFF) / 255;
			gr = ((pal[1] >> 16) & 0xFF) / 255;
			gg = ((pal[1] >> 8) & 0xFF) / 255;
			gb = (pal[1] & 0xFF) / 255;
			br = ((pal[2] >> 16) & 0xFF) / 255;
			bg = ((pal[2] >> 8) & 0xFF) / 255;
			bb = (pal[2] & 0xFF) / 255;
		}
		for (oy in 0...h) {
			for (ox in 0...w) {
				var sa:Float = 0, sr:Float = 0, sg:Float = 0, sb:Float = 0;
				for (j in 0...N) {
					final cy:Int = Math.floor((oy + (j + 0.5) / N) / s) + f.fy;
					if (cy < 0 || cy >= ch) continue;
					for (i in 0...N) {
						final cx:Int = Math.floor((ox + (i + 0.5) / N) / s) + f.fx;
						if (cx < 0 || cx >= cw) continue;

						final c:Int = f.rot ? sp.argb(f.x + f.w - 1 - cy, f.y + cx) : sp.argb(f.x + cx, f.y + cy);
						final a:Float = ((c >>> 24) & 0xFF) / 255;
						if (a <= 0) continue;
						var r:Float = ((c >> 16) & 0xFF) / 255;
						var g:Float = ((c >> 8) & 0xFF) / 255;
						var b:Float = (c & 0xFF) / 255;
						if (pal != null) {
							final nr:Float = r * rr + g * gr + b * br;
							final ng:Float = r * rg + g * gg + b * bg;
							final nb:Float = r * rb + g * gb + b * bb;
							r = nr > 1 ? 1 : nr;
							g = ng > 1 ? 1 : ng;
							b = nb > 1 ? 1 : nb;
						}
						sa += a;
						sr += r * a;
						sg += g * a;
						sb += b * a;
					}
				}
				final o:Int = (oy * w + ox) * 4;
				if (sa <= 0) {
					px.setInt32(o, 0);
					continue;
				}
				final outA:Float = sa * inv * alpha;
				px.set(o, Math.round(outA * 255));
				px.set(o + 1, Math.round(sr / sa * 255));
				px.set(o + 2, Math.round(sg / sa * 255));
				px.set(o + 3, Math.round(sb / sa * 255));
			}
		}
		sp = null;
	}
}
