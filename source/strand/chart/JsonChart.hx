package strand.chart;

import haxe.io.Bytes;
import strand.chart.NoteBuilder.BuilderLane;
import strand.native.Native;

class JsonChart
{
	static inline final CHUNK:Int = 4 << 20;
	static inline final RAW_LANES:Int = 64;

	public var progress(default, null):Float = 0;

	var file:Int = -1;
	var fileSize:Float = 0;
	var fileRead:Float = 0;
	var buf:Bytes;
	var pos:Int = 0;
	var end:Int = 0;

	var raw:Array<BuilderLane> = [];
	var sectionStarted:Bool = false;
	var pendTime:Array<Float> = [];
	var pendLane:Array<Int> = [];
	var pendLen:Array<Float> = [];
	var pendCount:Int = 0;
	var hurt:Float = 0;
	var badNotes:Float = 0;
	var sb:StringBuf = new StringBuf();

	public function new() {}

	public static function load(path:String, ?onProgress:Float->Void):ChartResult
	{
		final p:JsonChart = new JsonChart();
		return p.run(path, onProgress);
	}

	function run(path:String, onProgress:Float->Void):ChartResult
	{
		file = Native.open(path, Native.READ);
		if (file < 0) throw 'Could not open "$path"';
		fileSize = Native.seekEnd(file);
		Native.seek(file, 0);
		buf = Bytes.alloc(CHUNK);
		var root:Dynamic = null;
		final reporter:Float->Void = onProgress;
		try {
			skipWs();

			if (pos + 2 < end && buf.get(pos) == 0xEF && buf.get(pos + 1) == 0xBB && buf.get(pos + 2) == 0xBF) pos += 3;
			lastReport = reporter;
			root = parseValue(null);
		} catch (e:Dynamic) {
			Native.close(file);
			throw e;
		}
		Native.close(file);
		buf = null;
		return finish(root, path);
	}

	var lastReport:Float->Void = null;
	var reportAt:Float = 0;

	function finish(root:Dynamic, path:String):ChartResult
	{
		var song:Dynamic = root;
		if (root != null && Reflect.hasField(root, 'song') && !Std.isOfType(Reflect.field(root, 'song'), String)) song = Reflect.field(root, 'song');
		if (song == null) throw 'The chart is empty';
		final meta:ChartMeta = new ChartMeta();
		meta.format = 'json';

		final notesField:Dynamic = Reflect.field(song, 'notes');
		if (notesField != null && !Std.isOfType(notesField, Array) && Reflect.isObject(notesField)) return vslice(song, notesField, meta, path);

		meta.song = str(Reflect.field(song, 'song'), haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path)));
		meta.bpm = num(Reflect.field(song, 'bpm'), 100);
		meta.speed = num(Reflect.field(song, 'speed'), 1);
		var keys:Int = Std.int(num(Reflect.field(song, 'keyCount'), 4));
		if (keys < 1 || keys > 32) keys = 4;
		meta.keys = keys;
		final format:String = str(Reflect.field(song, 'format'), '');
		final v1:Bool = StringTools.startsWith(format, 'psych_v1');
		if (v1) meta.format = 'psych 1.0 json';

		final b:NoteBuilder = new NoteBuilder(keys);
		for (bucket in 0...raw.length) {
			final lane:BuilderLane = raw[bucket];
			if (lane == null || lane.length == 0) continue;
			final rawLane:Int = bucket >> 1;
			final must:Bool = bucket & 1 != 0;
			final firstHalf:Bool = rawLane % (keys * 2) < keys;
			final right:Bool = v1 ? firstHalf : firstHalf == must;
			b.lanes[b.laneOf(rawLane, right)].takeFrom(lane);
		}
		raw = null;
		b.dropped = hurt + badNotes;
		b.finish();
		meta.measure(b);
		return {meta: meta, builder: b};
	}

	function vslice(root:Dynamic, notes:Dynamic, meta:ChartMeta, path:String):ChartResult
	{
		final diffs:Array<String> = Reflect.fields(notes);
		var diff:String = null;
		for (want in ['hard', 'normal', 'easy']) if (diff == null && diffs.contains(want)) diff = want;
		if (diff == null) diff = diffs[0];
		meta.format = 'v-slice json';
		meta.song = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
		final speeds:Dynamic = Reflect.field(root, 'scrollSpeed');
		meta.speed = speeds != null && Reflect.isObject(speeds) ? num(Reflect.field(speeds, diff), num(Reflect.field(speeds, 'default'), 1)) : num(speeds, 1);
		meta.bpm = 100;

		try {
			final dir:String = haxe.io.Path.directory(path);
			final base:String = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path)).split('-chart')[0];
			final metaPath:String = dir + '/' + base + '-metadata.json';
			if (sys.FileSystem.exists(metaPath)) {
				final m:Dynamic = haxe.Json.parse(sys.io.File.getContent(metaPath));
				if (m.songName != null) meta.song = m.songName;
				final changes:Array<Dynamic> = m.timeChanges;
				if (changes != null && changes.length > 0) meta.bpm = num(changes[0].bpm, 100);
			}
		} catch (e:Dynamic) {}
		meta.keys = 4;
		final b:NoteBuilder = new NoteBuilder(4);
		final list:Array<Dynamic> = Reflect.field(notes, diff);
		if (list != null) for (n in list) {
			final d:Int = Std.int(num(n.d, -1));
			if (d < 0) continue;
			final kind:Dynamic = n.k;
			if (kind != null && Std.string(kind).toLowerCase().indexOf('hurt') != -1) {
				b.dropped++;
				continue;
			}

			b.add(num(n.t, 0), b.laneOf(d % 4, d < 4), num(n.l, 0));
		}
		b.finish();
		meta.measure(b);
		return {meta: meta, builder: b};
	}

	function fill():Bool
	{
		if (pos < end) return true;
		final n:Int = Native.read(file, buf, 0, CHUNK);
		pos = 0;
		end = n > 0 ? n : 0;
		fileRead += end;
		if (fileSize > 0) {
			progress = fileRead / fileSize;
			if (lastReport != null && progress - reportAt >= 0.002) {
				reportAt = progress;
				lastReport(progress);
			}
		}
		return end > 0;
	}

	inline function peek():Int
		return pos < end ? buf.get(pos) : (fill() ? buf.get(pos) : -1);

	inline function next():Int
		return pos < end ? buf.get(pos++) : (fill() ? buf.get(pos++) : -1);

	inline function skipWs():Void
	{
		while (true) {
			final c:Int = peek();
			if (c == 32 || c == 10 || c == 13 || c == 9) pos++;
			else break;
		}
	}

	function expect(c:Int):Void
	{
		skipWs();
		final got:Int = next();
		if (got != c) throw 'Broken JSON: expected "' + String.fromCharCode(c) + '" but found ' + (got < 0 ? 'the end of the file' : '"' + String.fromCharCode(got) + '"')
			+ ' near byte ' + Std.int(fileRead - end + pos);
	}

	function parseValue(key:String):Dynamic
	{
		skipWs();
		final c:Int = peek();
		switch (c)
		{
			case '{'.code:
				return parseObject();
			case '['.code:
				if (key == 'sectionNotes') {
					streamSectionNotes();
					return null;
				}
				return parseArray();
			case '"'.code:
				return parseString();
			case 't'.code:
				word('true');
				return true;
			case 'f'.code:
				word('false');
				return false;
			case 'n'.code:
				word('null');
				return null;
			default:
				return parseNumber();
		}
	}

	function word(w:String):Void
	{
		for (i in 0...w.length) if (next() != w.charCodeAt(i)) throw 'Broken JSON: expected $w';
	}

	function parseObject():Dynamic
	{
		expect('{'.code);
		final o:Dynamic = {};
		var hadNotes:Bool = false;
		final pendBefore:Int = pendCount;
		skipWs();
		if (peek() == '}'.code) {
			pos++;
			return o;
		}
		while (true) {
			skipWs();
			final k:String = parseString();
			expect(':'.code);
			if (k == 'sectionNotes') hadNotes = true;
			final v:Dynamic = parseValue(k);
			if (k != 'sectionNotes') Reflect.setField(o, k, v);
			skipWs();
			final c:Int = next();
			if (c == ','.code) continue;
			if (c == '}'.code) break;
			throw 'Broken JSON: expected , or } in an object';
		}
		if (hadNotes) flushSection(o, pendBefore);
		return o;
	}

	function parseArray():Array<Dynamic>
	{
		expect('['.code);
		final a:Array<Dynamic> = [];
		skipWs();
		if (peek() == ']'.code) {
			pos++;
			return a;
		}
		while (true) {
			a.push(parseValue(null));
			skipWs();
			final c:Int = next();
			if (c == ','.code) continue;
			if (c == ']'.code) break;
			throw 'Broken JSON: expected , or ] in an array';
		}
		return a;
	}

	function parseString():String
	{
		skipWs();
		if (next() != '"'.code) throw 'Broken JSON: expected a string';

		final start:Int = pos;
		var i:Int = pos;
		while (i < end) {
			final c:Int = buf.get(i);
			if (c == '"'.code) {
				pos = i + 1;
				return buf.getString(start, i - start);
			}
			if (c == '\\'.code) break;
			i++;
		}
		final out:haxe.io.BytesBuffer = new haxe.io.BytesBuffer();
		while (true) {
			final c:Int = next();
			if (c < 0) throw 'Broken JSON: a string never ends';
			if (c == '"'.code) break;
			if (c == '\\'.code) {
				final e:Int = next();
				switch (e)
				{
					case 'n'.code: out.addByte(10);
					case 'r'.code: out.addByte(13);
					case 't'.code: out.addByte(9);
					case 'b'.code: out.addByte(8);
					case 'f'.code: out.addByte(12);
					case 'u'.code:
						var code:Int = 0;
						for (k in 0...4) {
							final h:Int = next();
							code = code * 16 + (h >= 97 ? h - 87 : h >= 65 ? h - 55 : h - 48);
						}
						addUtf8(out, code);
					default: out.addByte(e);
				}
			} else out.addByte(c);
		}
		return out.getBytes().toString();
	}

	static function addUtf8(out:haxe.io.BytesBuffer, c:Int):Void
	{
		if (c < 0x80) out.addByte(c);
		else if (c < 0x800) {
			out.addByte(0xC0 | (c >> 6));
			out.addByte(0x80 | (c & 63));
		} else {
			out.addByte(0xE0 | (c >> 12));
			out.addByte(0x80 | ((c >> 6) & 63));
			out.addByte(0x80 | (c & 63));
		}
	}

	static final POW10:Array<Float> = [for (i in 0...23) Math.pow(10, i)];

	function parseNumber():Float
	{
		skipWs();
		var neg:Bool = false;
		var c:Int = peek();
		if (c == '-'.code) {
			neg = true;
			pos++;
			c = peek();
		} else if (c == '+'.code) {
			pos++;
			c = peek();
		}
		var mant:Float = 0;
		var digits:Int = 0;
		var scale:Int = 0;
		var any:Bool = false;
		while (c >= 48 && c <= 57) {
			if (digits < 18) {
				mant = mant * 10 + (c - 48);
				if (mant != 0) digits++;
			} else scale++;
			any = true;
			pos++;
			c = peek();
		}
		if (c == '.'.code) {
			pos++;
			c = peek();
			while (c >= 48 && c <= 57) {
				if (digits < 18) {
					mant = mant * 10 + (c - 48);
					if (mant != 0) digits++;
					scale--;
				}
				any = true;
				pos++;
				c = peek();
			}
		}
		if (c == 'e'.code || c == 'E'.code) {
			pos++;
			c = peek();
			var eneg:Bool = false;
			if (c == '-'.code || c == '+'.code) {
				eneg = c == '-'.code;
				pos++;
				c = peek();
			}
			var e:Int = 0;
			while (c >= 48 && c <= 57) {
				if (e < 10000) e = e * 10 + (c - 48);
				pos++;
				c = peek();
			}
			scale += eneg ? -e : e;
		}
		if (!any) {
			if (c == 'N'.code) {
				word('NaN');
				return Math.NaN;
			}
			throw 'Broken JSON: unexpected "' + (c < 0 ? 'end of file' : String.fromCharCode(c)) + '" near byte ' + Std.int(fileRead - end + pos);
		}
		var v:Float = mant;
		if (scale != 0) {
			if (scale > 0) v = scale < 23 ? v * POW10[scale] : v * Math.pow(10, scale);
			else v = -scale < 23 ? v / POW10[-scale] : v / Math.pow(10, -scale);
		}
		return neg ? -v : v;
	}

	function streamSectionNotes():Void
	{
		expect('['.code);
		skipWs();
		if (peek() == ']'.code) {
			pos++;
			return;
		}
		while (true) {
			skipWs();
			if (peek() == '['.code) readNote();
			else parseValue(null);
			skipWs();
			final c:Int = next();
			if (c == ','.code) continue;
			if (c == ']'.code) break;
			throw 'Broken JSON: expected , or ] in sectionNotes';
		}
	}

	function readNote():Void
	{
		pos++;
		var time:Float = Math.NaN, lane:Float = -1, len:Float = 0;
		var i:Int = 0;
		var isHurt:Bool = false;
		skipWs();
		if (peek() == ']'.code) {
			pos++;
			badNotes++;
			return;
		}
		while (true) {
			skipWs();
			final c:Int = peek();
			if (i < 3 && (c == '-'.code || (c >= 48 && c <= 57) || c == '.'.code)) {
				final v:Float = parseNumber();
				if (i == 0) time = v;
				else if (i == 1) lane = v;
				else len = v;
			} else {
				final v:Dynamic = parseValue(null);
				if (i == 0) time = num(v, Math.NaN);
				else if (i == 1) lane = num(v, -1);
				else if (i == 2) len = num(v, 0);
				else if (i == 3 && Std.isOfType(v, String) && (v : String).toLowerCase() == 'hurt note') isHurt = true;
			}
			i++;
			skipWs();
			final d:Int = next();
			if (d == ','.code) continue;
			if (d == ']'.code) break;
			throw 'Broken JSON: expected , or ] in a note';
		}
		if (isHurt) {
			hurt++;
			return;
		}
		if (Math.isNaN(time) || lane < 0 || lane >= RAW_LANES) {
			badNotes++;
			return;
		}
		pendTime[pendCount] = time;
		pendLane[pendCount] = Std.int(lane);
		pendLen[pendCount] = len;
		pendCount++;
	}

	function flushSection(section:Dynamic, from:Int):Void
	{
		final must:Bool = Reflect.field(section, 'mustHitSection') == true;
		for (i in from...pendCount) {
			final bucket:Int = pendLane[i] * 2 + (must ? 1 : 0);
			var lane:BuilderLane = raw[bucket];
			if (lane == null) raw[bucket] = lane = new BuilderLane();
			final t:Float = pendTime[i];
			final l:Float = pendLen[i];
			lane.add(Math.fround(t * 1000), l > 0 ? Math.fround(l * 1000) : 0, 1);
		}
		pendCount = from;
		if (from == 0 && pendTime.length > 65536) {
			pendTime = [];
			pendLane = [];
			pendLen = [];
		}
	}

	static inline function num(v:Dynamic, fallback:Float):Float
	{
		if (v == null) return fallback;
		if (Std.isOfType(v, String)) {
			final f:Float = Std.parseFloat(v);
			return Math.isNaN(f) ? fallback : f;
		}
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
			final f:Float = v;
			return Math.isNaN(f) ? fallback : f;
		}
		return fallback;
	}

	static inline function str(v:Dynamic, fallback:String):String
		return v == null ? fallback : Std.string(v);
}

typedef ChartResult = {meta:ChartMeta, builder:NoteBuilder};
