package strand.chart;

import haxe.io.Bytes;
import haxe.io.BytesData;
import cpp.NativeArray;
import strand.chart.NoteBuilder.BuilderLane;
import strand.native.Native;

class JsonChart
{
	static inline final CHUNK:Int = 4 << 20;
	static inline final RAW_LANES:Int = 64;
	static inline final WINDOW:Int = 1024;
	static inline final HURT:String = 'hurt note';

	public var progress(default, null):Float = 0;

	var file:Int = -1;
	var fileSize:Float = 0;
	var fileRead:Float = 0;
	var buf:Bytes;
	var data:BytesData;
	var pos:Int = 0;
	var end:Int = 0;
	var eof:Bool = false;
	var direct:Bool;
	var val:Float = 0;
	var hurtNote:Bool = false;

	var raw:Array<BuilderLane> = [];
	var sectionStarted:Bool = false;
	var pendTime:Array<Float> = [];
	var pendLane:Array<Int> = [];
	var pendLen:Array<Float> = [];
	var pendCount:Int = 0;
	var hurt:Float = 0;
	var badNotes:Float = 0;
	var sb:StringBuf = new StringBuf();

	public function new(direct:Bool = true)
	{
		this.direct = direct;
	}

	public static function load(path:String, ?onProgress:Float->Void):ChartResult
	{
		try {
			return new JsonChart(true).run(path, onProgress);
		} catch (e:LateMustHit) {
			return new JsonChart(false).run(path, onProgress);
		}
	}

	function run(path:String, onProgress:Float->Void):ChartResult
	{
		file = Native.open(path, Native.READ);
		if (file < 0) throw 'Could not open "$path"';
		fileSize = Native.seekEnd(file);
		Native.seek(file, 0);
		buf = Bytes.alloc(CHUNK);
		data = buf.getData();
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
		data = null;
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
		pos = 0;
		end = 0;
		return readMore();
	}

	function ensure():Void
	{
		if (eof || end - pos >= WINDOW) return;
		final keep:Int = end - pos;
		if (keep > 0 && pos > 0) buf.blit(0, buf, pos, keep);
		pos = 0;
		end = keep;
		while (end < WINDOW && readMore()) {}
	}

	function readMore():Bool
	{
		if (eof) return false;
		final n:Int = Native.read(file, buf, end, CHUNK - end);
		if (n <= 0) {
			eof = true;
			return false;
		}
		end += n;
		fileRead += n;
		if (fileSize > 0) {
			progress = fileRead / fileSize;
			if (lastReport != null && progress - reportAt >= 0.002) {
				reportAt = progress;
				lastReport(progress);
			}
		}
		return true;
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
					streamSectionNotes(-1);
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
		var directUsed:Bool = false;
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
			if (k == 'sectionNotes') {
				hadNotes = true;
				skipWs();
				if (peek() == '['.code) {
					var bit:Int = -1;
					if (direct && Reflect.hasField(o, 'mustHitSection')) {
						bit = Reflect.field(o, 'mustHitSection') == true ? 1 : 0;
						directUsed = true;
					}
					streamSectionNotes(bit);
				} else parseValue(k);
			} else {
				if (directUsed && k == 'mustHitSection') throw new LateMustHit();
				Reflect.setField(o, k, parseValue(k));
			}
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

	function streamSectionNotes(bit:Int):Void
	{
		expect('['.code);
		skipWs();
		if (peek() == ']'.code) {
			pos++;
			return;
		}
		while (true) {
			ensure();
			final f:Int = fastNote(bit);
			if (f == ','.code) continue;
			if (f == ']'.code) break;
			skipWs();
			if (peek() == '['.code) readNote(bit);
			else parseValue(null);
			skipWs();
			final c:Int = next();
			if (c == ','.code) continue;
			if (c == ']'.code) break;
			throw 'Broken JSON: expected , or ] in sectionNotes';
		}
	}

	function fastNote(bit:Int):Int
	{
		final d:BytesData = data;
		final lim:Int = end;
		var i:Int = skipWsAt(d, pos, lim);
		if (i >= lim || NativeArray.unsafeGet(d, i) != '['.code) return 0;
		i = scanNum(d, skipWsAt(d, i + 1, lim), lim);
		if (i < 0) return 0;
		final time:Float = val;
		i = skipWsAt(d, i, lim);
		if (i >= lim || NativeArray.unsafeGet(d, i) != ','.code) return 0;
		i = scanNum(d, skipWsAt(d, i + 1, lim), lim);
		if (i < 0) return 0;
		final lane:Float = val;
		var len:Float = 0;
		var isHurt:Bool = false;
		var k:Int = 2;
		while (true) {
			i = skipWsAt(d, i, lim);
			if (i >= lim) return 0;
			var c:Int = NativeArray.unsafeGet(d, i);
			if (c == ']'.code) break;
			if (c != ','.code) return 0;
			i = skipWsAt(d, i + 1, lim);
			if (i >= lim) return 0;
			c = NativeArray.unsafeGet(d, i);
			if (k == 2) {
				i = scanNum(d, i, lim);
				if (i < 0) return 0;
				len = val;
			} else if (c == '"'.code) {
				i = scanStr(d, i + 1, lim);
				if (i < 0) return 0;
				if (k == 3 && hurtNote) isHurt = true;
			} else if (c == 't'.code) {
				if (!lit(d, i, lim, 't'.code, 'r'.code, 'u'.code, 'e'.code)) return 0;
				i += 4;
			} else if (c == 'f'.code) {
				if (i + 4 >= lim || NativeArray.unsafeGet(d, i + 4) != 'e'.code || !lit(d, i, lim, 'f'.code, 'a'.code, 'l'.code, 's'.code)) return 0;
				i += 5;
			} else if (c == 'n'.code) {
				if (!lit(d, i, lim, 'n'.code, 'u'.code, 'l'.code, 'l'.code)) return 0;
				i += 4;
			} else {
				i = scanNum(d, i, lim);
				if (i < 0) return 0;
			}
			k++;
		}
		i = skipWsAt(d, i + 1, lim);
		if (i >= lim) return 0;
		final sep:Int = NativeArray.unsafeGet(d, i);
		if (sep != ','.code && sep != ']'.code) return 0;
		pos = i + 1;
		if (isHurt) hurt++;
		else if (lane < 0 || lane >= RAW_LANES) badNotes++;
		else addNote(time, Std.int(lane), len, bit);
		return sep;
	}

	static inline function skipWsAt(d:BytesData, i:Int, lim:Int):Int
	{
		while (i < lim) {
			final c:Int = NativeArray.unsafeGet(d, i);
			if (c == 32 || c == 10 || c == 13 || c == 9) i++;
			else break;
		}
		return i;
	}

	static inline function lit(d:BytesData, i:Int, lim:Int, a:Int, b:Int, c:Int, e:Int):Bool
		return i + 3 < lim && NativeArray.unsafeGet(d, i) == a && NativeArray.unsafeGet(d, i + 1) == b && NativeArray.unsafeGet(d, i + 2) == c
			&& NativeArray.unsafeGet(d, i + 3) == e;

	function scanStr(d:BytesData, i:Int, lim:Int):Int
	{
		final start:Int = i;
		while (i < lim) {
			final c:Int = NativeArray.unsafeGet(d, i);
			if (c == '"'.code) break;
			if (c == '\\'.code || c >= 128) return -1;
			i++;
		}
		if (i >= lim) return -1;
		hurtNote = i - start == 9;
		if (hurtNote) for (j in 0...9) {
			var c:Int = NativeArray.unsafeGet(d, start + j);
			if (c >= 'A'.code && c <= 'Z'.code) c += 32;
			if (c != StringTools.fastCodeAt(HURT, j)) {
				hurtNote = false;
				break;
			}
		}
		return i + 1;
	}

	function scanNum(d:BytesData, i:Int, lim:Int):Int
	{
		if (i >= lim) return -1;
		var c:Int = NativeArray.unsafeGet(d, i);
		var neg:Bool = false;
		if (c == '-'.code) {
			neg = true;
			i++;
			c = i < lim ? NativeArray.unsafeGet(d, i) : -1;
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
			i++;
			c = i < lim ? NativeArray.unsafeGet(d, i) : -1;
		}
		if (c == '.'.code) {
			i++;
			c = i < lim ? NativeArray.unsafeGet(d, i) : -1;
			while (c >= 48 && c <= 57) {
				if (digits < 18) {
					mant = mant * 10 + (c - 48);
					if (mant != 0) digits++;
					scale--;
				}
				any = true;
				i++;
				c = i < lim ? NativeArray.unsafeGet(d, i) : -1;
			}
		}
		if (!any || c < 0 || c == 'e'.code || c == 'E'.code || c == '.'.code) return -1;
		var v:Float = mant;
		if (scale != 0) {
			if (scale > 0) v = scale < 23 ? v * POW10[scale] : v * Math.pow(10, scale);
			else v = -scale < 23 ? v / POW10[-scale] : v / Math.pow(10, -scale);
		}
		val = neg ? -v : v;
		return i;
	}

	inline function addNote(time:Float, lane:Int, len:Float, bit:Int):Void
	{
		if (bit < 0) {
			pendTime[pendCount] = time;
			pendLane[pendCount] = lane;
			pendLen[pendCount] = len;
			pendCount++;
		} else {
			final bucket:Int = lane * 2 + bit;
			var l:BuilderLane = raw[bucket];
			if (l == null) raw[bucket] = l = new BuilderLane();
			l.add(Math.fround(time * 1000), len > 0 ? Math.fround(len * 1000) : 0, 1);
		}
	}

	function readNote(bit:Int):Void
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
		addNote(time, Std.int(lane), len, bit);
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

class LateMustHit
{
	public function new() {}
}
