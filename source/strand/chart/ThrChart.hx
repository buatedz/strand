package strand.chart;

import haxe.io.Bytes;
import strand.native.Native;

class ThrChart
{
	static inline final HEADER:Int = 32;
	static inline final REC:Int = 16;
	static inline final SEC_REC:Int = 40;
	static inline final FLAG_FILTERED:Int = 1;
	static inline final SEC_MUST:Int = 1;
	static inline final FILTER_BLOCK:Int = 65536;
	static inline final MAGIC_NOTES:Int = 0x4E4C4254;
	static inline final MAGIC_SECTIONS:Int = 0x534C4254;

	public static function load(path:String, ?onProgress:Float->Void):JsonChart.ChartResult
	{
		final zip:ZipReader = new ZipReader(path);
		try {
			final r = read(zip, path, onProgress);
			zip.close();
			return r;
		} catch (e:Dynamic) {
			zip.close();
			throw e;
		}
	}

	public static function noteCount(path:String):Float
	{
		try {
			final zip:ZipReader = new ZipReader(path);
			var count:Float = -1;
			try {
				for (e in zip.entries)
					if (e.name.indexOf('/') == -1 && e.name.toLowerCase().indexOf('-metadata.json') != -1) {
						final meta:Dynamic = haxe.Json.parse(zip.readEntry(e).toString());
						final parts:Array<Dynamic> = meta.tbl.parts;
						if (parts != null && parts.length > 0 && parts[0].noteCount != null) count = parts[0].noteCount;
					}
			} catch (e:Dynamic) {}
			zip.close();
			return count;
		} catch (e:Dynamic) {
			return -1;
		}
	}

	static function read(zip:ZipReader, path:String, onProgress:Float->Void):JsonChart.ChartResult
	{
		var metaEntry:ZipEntry = null;
		for (e in zip.entries) if (e.name.indexOf('/') == -1 && e.name.toLowerCase().indexOf('-metadata.json') != -1) metaEntry = e;
		if (metaEntry == null) throw '"$path" has no metadata.json inside';
		final meta:Dynamic = haxe.Json.parse(zip.readEntry(metaEntry).toString());
		if (meta == null || meta.tbl == null) throw '"$path" has a broken metadata.json';
		final parts:Array<Dynamic> = meta.tbl.parts;
		if (parts == null || parts.length == 0) throw '"$path" lists no charts';
		final part:Dynamic = parts[0];
		final prefix:String = part.prefix != null ? part.prefix : '';
		var keys:Int = part.keyCount != null ? Std.int(part.keyCount) : 4;
		if (keys < 1 || keys > 32) keys = 4;
		final types:Array<Dynamic> = part.types != null ? part.types : [null];
		final hurtType:Array<Bool> = [for (t in types) t != null && Std.isOfType(t, String) && (t : String).toLowerCase() == 'hurt note'];
		final perFile:Float = part.notesPerFile != null ? (part.notesPerFile : Float) : 4194304.0;
		final noteFiles:Int = part.noteFiles != null ? Std.int(part.noteFiles) : 0;
		final noteCount:Float = part.noteCount != null ? (part.noteCount : Float) : 0;
		final song:Dynamic = meta.song != null ? meta.song : {};
		final format:String = song.format != null ? Std.string(song.format) : '';
		final v1:Bool = StringTools.startsWith(format, 'psych_v1');

		final m:ChartMeta = new ChartMeta();
		m.format = '.thr';
		m.song = song.song != null ? Std.string(song.song) : haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
		m.bpm = song.bpm != null ? (song.bpm : Float) : 100;
		m.speed = song.speed != null ? (song.speed : Float) : 1;
		m.keys = keys;

		final secEntry:ZipEntry = zip.get('notes/' + prefix + 'sections.bin');
		if (secEntry == null) throw '"$path" is missing its sections';
		final sec:Bytes = unfilterBin(zip.readEntry(secEntry), SEC_REC);
		if (sec.getInt32(0) != MAGIC_SECTIONS) throw '"$path" has broken sections';
		final secCount:Int = Std.int(sec.getDouble(8));

		final b:NoteBuilder = new NoteBuilder(keys);
		var section:Int = -1;
		var secLeft:Float = 0;
		var must:Bool = false;
		var done:Float = 0;
		var raw:Bytes = null, comp:Bytes = null;
		for (f in 0...noteFiles) {
			final name:String = 'notes/' + prefix + 'notes-' + StringTools.lpad(Std.string(f), '0', 5) + '.bin';
			final e:ZipEntry = zip.get(name);
			if (e == null) throw '"$path" is missing $name';
			final size:Int = Std.int(e.size);
			if (raw == null || raw.length < size) raw = Bytes.alloc(size);
			if (e.method == ZipReader.STORE) zip.readRaw(e, 0, raw, 0, size);
			else {
				final c:Int = Std.int(e.compSize);
				if (comp == null || comp.length < c) comp = Bytes.alloc(c);
				zip.readRaw(e, 0, comp, 0, c);
				ZipReader.decompress(e.method, comp, 0, c, raw, 0, size);
			}
			if (raw.getInt32(0) != MAGIC_NOTES) throw '"$path" has a broken $name';
			final count:Int = Std.int(raw.getDouble(8));
			var data:Bytes = raw;
			var at:Int = HEADER;
			if (raw.getInt32(24) & FLAG_FILTERED != 0) {
				data = Bytes.alloc(count * REC);
				unfilter(raw, HEADER, data, 0, count, REC);
				at = 0;
			}
			for (i in 0...count) {
				while (secLeft <= 0 && section + 1 < secCount) {
					section++;
					final p:Int = HEADER + section * SEC_REC;
					final lo:Int = sec.getInt32(p + 8);
					secLeft = (lo < 0 ? lo + 4294967296.0 : lo * 1.0) + sec.getInt32(p + 32) * 4294967296.0;
					must = sec.getInt32(p + 12) & SEC_MUST != 0;
				}
				secLeft--;
				final q:Int = at + i * REC;
				final type:Int = data.getUInt16(q + 14);
				if (type < hurtType.length && hurtType[type]) {
					b.dropped++;
					continue;
				}
				final lane:Int = data.getUInt16(q + 12);
				final firstHalf:Bool = lane % (keys * 2) < keys;
				b.add(data.getDouble(q), b.laneOf(lane, v1 ? firstHalf : firstHalf == must), data.getFloat(q + 8));
			}
			done += count;
			if (onProgress != null && noteCount > 0) onProgress(Math.min(1, done / noteCount));
		}
		b.finish();
		m.measure(b);
		return {meta: m, builder: b};
	}

	static function unfilterBin(raw:Bytes, recSize:Int):Bytes
	{
		if (raw.getInt32(24) & FLAG_FILTERED == 0) return raw;
		final n:Int = Std.int(raw.getDouble(8));
		final out:Bytes = Bytes.alloc(raw.length);
		out.blit(0, raw, 0, HEADER);
		unfilter(raw, HEADER, out, HEADER, n, recSize);
		return out;
	}

	public static function unfilter(src:Bytes, srcPos:Int, dst:Bytes, dstPos:Int, records:Int, recSize:Int):Void
	{
		var done:Int = 0;
		while (done < records) {
			final n:Int = records - done < FILTER_BLOCK ? records - done : FILTER_BLOCK;
			final inBase:Int = srcPos + done * recSize;
			final outBase:Int = dstPos + done * recSize;
			var prevLo:Int = 0, prevHi:Int = 0;
			for (i in 0...n) {
				final dLo:Int = src.get(inBase + i) | (src.get(inBase + n + i) << 8) | (src.get(inBase + 2 * n + i) << 16) | (src.get(inBase + 3 * n + i) << 24);
				final dHi:Int = src.get(inBase + 4 * n + i) | (src.get(inBase + 5 * n + i) << 8) | (src.get(inBase + 6 * n + i) << 16)
					| (src.get(inBase + 7 * n + i) << 24);
				final lo:Int = dLo + prevLo;
				final carry:Int = ((lo ^ 0x80000000) < (prevLo ^ 0x80000000)) ? 1 : 0;
				final hi:Int = dHi + prevHi + carry;
				prevLo = lo;
				prevHi = hi;
				final p:Int = outBase + i * recSize;
				dst.setInt32(p, lo);
				dst.setInt32(p + 4, hi);
				for (k in 8...recSize) dst.set(p + k, src.get(inBase + k * n + i));
			}
			done += n;
		}
	}
}

class ZipEntry
{
	public var name:String;
	public var method:Int = 0;
	public var compSize:Float = 0;
	public var size:Float = 0;
	public var headerOffset:Float = 0;
	public var dataOffset:Float = -1;

	public function new(name:String)
		this.name = name;
}

class ZipReader
{
	public static inline final STORE:Int = 0;
	public static inline final DEFLATE:Int = 8;
	public static inline final LZMA:Int = 14;

	public var path(default, null):String;
	public var entries(default, null):Array<ZipEntry> = [];

	var byName:Map<String, ZipEntry> = new Map();
	var file:Int = -1;
	var size:Float = 0;
	var small:Bytes = Bytes.alloc(64);

	public function new(path:String)
	{
		this.path = path;
		file = Native.open(path, Native.READ);
		if (file < 0) throw 'Could not open "$path"';
		size = Native.seekEnd(file);
		try readDirectory() catch (e:Dynamic) {
			close();
			throw e;
		}
	}

	public function close():Void
	{
		if (file >= 0) Native.close(file);
		file = -1;
	}

	public inline function get(name:String):ZipEntry
		return byName.get(name);

	function readDirectory():Void
	{
		if (size < 22) throw '"$path" is not a .thr file (too small)';
		final tailLen:Int = Std.int(Math.min(size, 65557));
		final tail:Bytes = Bytes.alloc(tailLen);
		Native.readAt(file, size - tailLen, tail, 0, tailLen);
		var at:Int = tailLen - 22;
		while (at >= 0 && tail.getInt32(at) != 0x06054b50) at--;
		if (at < 0) throw '"$path" is not a .thr file (no zip directory found)';
		var count:Float = tail.getUInt16(at + 10);
		var cdSize:Float = u32(tail, at + 12);
		var cdStart:Float = u32(tail, at + 16);
		if (at >= 20 && tail.getInt32(at - 20) == 0x07064b50) {
			final rec:Bytes = Bytes.alloc(56);
			Native.readAt(file, u64(tail, at - 20 + 8), rec, 0, 56);
			if (rec.getInt32(0) != 0x06064b50) throw '"$path" has a broken zip64 directory';
			count = u64(rec, 32);
			cdSize = u64(rec, 40);
			cdStart = u64(rec, 48);
		}
		if (cdSize > 1073741824.0) throw '"$path" has a zip directory that is too big';
		final cd:Bytes = Bytes.alloc(Std.int(cdSize));
		Native.readAt(file, cdStart, cd, 0, cd.length);
		var p:Int = 0;
		var n:Float = 0;
		while (n < count && p + 46 <= cd.length) {
			if (cd.getInt32(p) != 0x02014b50) throw '"$path" has a broken zip directory';
			final nameLen:Int = cd.getUInt16(p + 28);
			final extraLen:Int = cd.getUInt16(p + 30);
			final commentLen:Int = cd.getUInt16(p + 32);
			final e:ZipEntry = new ZipEntry(cd.getString(p + 46, nameLen));
			e.method = cd.getUInt16(p + 10);
			e.compSize = u32(cd, p + 20);
			e.size = u32(cd, p + 24);
			e.headerOffset = u32(cd, p + 42);
			var x:Int = p + 46 + nameLen;
			final xEnd:Int = x + extraLen;
			while (x + 4 <= xEnd) {
				final id:Int = cd.getUInt16(x);
				final len:Int = cd.getUInt16(x + 2);
				if (id == 0x0001) {
					var q:Int = x + 4;
					if (e.size == 4294967295.0 && q + 8 <= x + 4 + len) {
						e.size = u64(cd, q);
						q += 8;
					}
					if (e.compSize == 4294967295.0 && q + 8 <= x + 4 + len) {
						e.compSize = u64(cd, q);
						q += 8;
					}
					if (e.headerOffset == 4294967295.0 && q + 8 <= x + 4 + len) e.headerOffset = u64(cd, q);
				}
				x += 4 + len;
			}
			entries.push(e);
			byName.set(e.name, e);
			p = xEnd + commentLen;
			n++;
		}
	}

	function dataOffset(e:ZipEntry):Float
	{
		if (e.dataOffset >= 0) return e.dataOffset;
		Native.readAt(file, e.headerOffset, small, 0, 30);
		if (small.getInt32(0) != 0x04034b50) throw '"$path" has a broken entry "${e.name}"';
		e.dataOffset = e.headerOffset + 30 + small.getUInt16(26) + small.getUInt16(28);
		return e.dataOffset;
	}

	public function readRaw(e:ZipEntry, offset:Float, bytes:Bytes, pos:Int, len:Int):Void
		Native.readAt(file, dataOffset(e) + offset, bytes, pos, len);

	public function readEntry(e:ZipEntry):Bytes
	{
		if (e.size > 2147483000.0) throw 'Entry "${e.name}" is too big to read at once';
		final n:Int = Std.int(e.size);
		final out:Bytes = Bytes.alloc(n);
		if (e.method == STORE) {
			readRaw(e, 0, out, 0, n);
			return out;
		}
		final comp:Bytes = Bytes.alloc(Std.int(e.compSize));
		readRaw(e, 0, comp, 0, comp.length);
		decompress(e.method, comp, 0, comp.length, out, 0, n);
		return out;
	}

	public static function decompress(method:Int, src:Bytes, pos:Int, len:Int, dst:Bytes, dstPos:Int, dstLen:Int):Void
	{
		switch (method)
		{
			case STORE:
				dst.blit(dstPos, src, pos, len);
			case DEFLATE:
				final u:haxe.zip.Uncompress = new haxe.zip.Uncompress(-15);
				u.setFlushMode(haxe.zip.FlushMode.SYNC);
				final input:Bytes = (pos == 0 && len == src.length) ? src : src.sub(pos, len);
				final output:Bytes = (dstPos == 0 && dstLen == dst.length) ? dst : Bytes.alloc(dstLen);
				var srcAt:Int = 0, dstAt:Int = 0, guard:Int = 0;
				while (dstAt < dstLen) {
					final r = u.execute(input, srcAt, output, dstAt);
					srcAt += r.read;
					dstAt += r.write;
					if (r.done) break;
					if (r.read == 0 && r.write == 0 && ++guard > 4) break;
				}
				u.close();
				if (dstAt != dstLen) throw 'Compressed data is broken (got $dstAt of $dstLen bytes)';
				if (output != dst) dst.blit(dstPos, output, 0, dstLen);
			case LZMA:

				if (len < 9 || src.getUInt16(pos + 2) != 5) throw 'LZMA data is broken';
				if (!Native.lzmaDecode(src, pos + 9, len - 9, dst, dstPos, dstLen, src, pos + 4)) throw 'LZMA data is broken';
			default:
				throw 'Unknown compression method $method';
		}
	}

	static inline function u32(b:Bytes, p:Int):Float
	{
		final v:Int = b.getInt32(p);
		return v < 0 ? v + 4294967296.0 : v;
	}

	static inline function u64(b:Bytes, p:Int):Float
		return u32(b, p) + u32(b, p + 4) * 4294967296.0;
}
