package strand.cache;

import haxe.io.Bytes;
import strand.chart.ChartMeta;
import strand.chart.NoteBuilder;
import strand.chart.NoteBuilder.BuilderLane;
import strand.native.Native;

class BinCache
{
	public static inline final MAGIC:String = 'STRNDBIN';
	public static inline final VERSION:Int = 1;
	static inline final HEADER:Int = 64;

	public static inline final BLOCK_ENTRIES:Int = 1 << 19;

	public var path(default, null):String;

	var entries:Map<String, CacheEntry> = new Map();
	var lock:sys.thread.Mutex = new sys.thread.Mutex();
	var fileEnd:Float = HEADER;

	public static var status:String = null;
	public static var progress:Float = -1;

	public function new(path:String)
	{
		this.path = path;
		try load() catch (e:Dynamic) {
			trace('Cache "$path" not readable, starting a new one: $e');
			entries = new Map();
		}
	}

	public function find(key:String, stamp:String):CacheEntry
	{
		lock.acquire();
		final e:CacheEntry = entries.get(key);
		lock.release();
		return e != null && e.stamp == stamp ? e : null;
	}

	public function anyEntry(key:String):CacheEntry
	{
		lock.acquire();
		final e:CacheEntry = entries.get(key);
		lock.release();
		return e;
	}

	public function fileBytes():Float
		return fileEnd;

	function load():Void
	{
		if (!sys.FileSystem.exists(path)) return;
		final f:Int = Native.open(path, Native.READ);
		if (f < 0) throw 'cannot open';
		try {
			final size:Float = Native.seekEnd(f);
			if (size < HEADER) throw 'too small';
			final head:Bytes = Bytes.alloc(HEADER);
			Native.readAt(f, 0, head, 0, HEADER);
			if (head.getString(0, 8) != MAGIC) throw 'not a Strand cache';
			if (head.getInt32(8) > VERSION) throw 'made by a newer Strand';
			final at:Float = head.getDouble(16);
			final comp:Int = Std.int(head.getDouble(24));
			final rawLen:Int = Std.int(head.getDouble(32));
			if (comp <= 0 || at + comp > size) throw 'index missing';
			final data:Bytes = Bytes.alloc(comp + 5);
			data.blit(0, head, 40, 5);
			Native.readAt(f, at, data, 5, comp);
			final raw:Bytes = NoteCodec.decompress(data, comp + 5, rawLen);
			final index:Dynamic = haxe.Json.parse(raw.toString());
			final list:Array<Dynamic> = index.entries;
			for (o in list) {
				final e:CacheEntry = CacheEntry.fromObject(o);
				entries.set(e.key, e);
			}
			fileEnd = at + comp;
		} catch (e:Dynamic) {
			Native.close(f);
			throw e;
		}
		Native.close(f);
	}

	public function reader():CacheReader
		return new CacheReader(path);

	public function store(key:String, stamp:String, meta:ChartMeta, b:NoteBuilder, threads:Int):CacheEntry
	{
		status = 'cutting into blocks';
		progress = 0;
		final cuts:Array<Float> = cutTimes(b);
		var firstUs:Float = Math.POSITIVE_INFINITY, lastUs:Float = 0;
		for (l in b.lanes) if (l.length > 0) {
			if (l.times[0] < firstUs) firstUs = l.times[0];
			if (l.times[l.length - 1] > lastUs) lastUs = l.times[l.length - 1];
		}
		if (firstUs == Math.POSITIVE_INFINITY) firstUs = 0;
		final blockCount:Int = cuts.length + 1;
		final from:Array<Array<Int>> = [];
		final to:Array<Array<Int>> = [];
		final pos:Array<Int> = [for (l in 0...b.laneCount) 0];
		for (k in 0...blockCount) {
			final cut:Float = k < cuts.length ? cuts[k] : Math.POSITIVE_INFINITY;
			final f:Array<Int> = [];
			final t:Array<Int> = [];
			for (l in 0...b.laneCount) {
				final lane:BuilderLane = b.lanes[l];
				f.push(pos[l]);
				var e:Int = cut == Math.POSITIVE_INFINITY ? lane.length : lowerBound(lane.times, lane.length, cut, pos[l]);
				t.push(e);
				pos[l] = e;
			}
			from.push(f);
			to.push(t);
		}

		final entry:CacheEntry = new CacheEntry();
		entry.key = key;
		entry.stamp = stamp;
		entry.meta = meta;
		entry.keys = b.keys;
		final results:Array<Bytes> = [for (k in 0...blockCount) null];
		final raws:Array<Int> = [for (k in 0...blockCount) 0];
		final errors:Array<String> = [];
		var nextJob:Int = 0;
		var finished:Int = 0;
		final jobLock:sys.thread.Mutex = new sys.thread.Mutex();
		final done:sys.thread.Lock = new sys.thread.Lock();
		final workers:Int = threads < 1 ? 1 : threads > blockCount ? blockCount : threads;
		status = 'compressing';
		for (w in 0...workers) {
			sys.thread.Thread.create(function() {
				while (true) {
					jobLock.acquire();
					final k:Int = nextJob++;
					jobLock.release();
					if (k >= blockCount || errors.length > 0) break;
					try {
						final base:Float = k == 0 ? firstUs : cuts[k - 1];
						final raw:Bytes = NoteCodec.encode(b, from[k], to[k], base);
						final comp:Bytes = NoteCodec.compress(raw);
						jobLock.acquire();
						results[k] = comp;
						raws[k] = raw.length;
						finished++;
						progress = finished / blockCount;
						jobLock.release();
					} catch (e:Dynamic) {
						jobLock.acquire();
						errors.push(Std.string(e));
						jobLock.release();
					}
				}
				done.release();
			});
		}
		for (w in 0...workers) done.wait();
		if (errors.length > 0) throw 'Could not make the cache: ' + errors[0];

		status = 'writing cache.bin';
		lock.acquire();
		try {
			final f:Int = openForWrite();
			try {
				var at:Float = fileEnd;
				Native.seek(f, at);
				for (k in 0...blockCount) {
					final comp:Bytes = results[k];
					Native.write(f, comp, 0, comp.length);
					final info:BlockInfo = new BlockInfo();
					info.offset = at;
					info.comp = comp.length;
					info.raw = raws[k];
					info.startUs = k == 0 ? firstUs : cuts[k - 1];
					info.endUs = k < cuts.length ? cuts[k] : lastUs + 1;
					var opp:Float = 0, pl:Float = 0, n:Float = 0;
					for (l in 0...b.laneCount) {
						final lane:BuilderLane = b.lanes[l];
						var c:Float = 0;
						for (i in from[k][l]...to[k][l]) c += lane.counts[i];
						if (l < b.keys) opp += c;
						else pl += c;
						n += to[k][l] - from[k][l];
					}
					info.entries = n;
					info.opp = opp;
					info.player = pl;
					entry.blocks.push(info);
					at += comp.length;
					results[k] = null;
				}
				entries.set(key, entry);
				writeIndex(f, at);
				Native.close(f);
			} catch (e:Dynamic) {
				Native.close(f);
				throw e;
			}
		} catch (e:Dynamic) {
			lock.release();
			status = null;
			throw e;
		}
		lock.release();
		maybeCompact();
		status = null;
		progress = -1;
		return entry;
	}

	function openForWrite():Int
	{
		var f:Int = -1;
		if (sys.FileSystem.exists(path)) f = Native.open(path, Native.UPDATE);
		if (f < 0) {
			f = Native.open(path, Native.WRITE);
			if (f < 0) throw 'Could not write "$path"';
			final head:Bytes = Bytes.alloc(HEADER);
			head.blit(0, Bytes.ofString(MAGIC), 0, 8);
			head.setInt32(8, VERSION);
			Native.write(f, head, 0, HEADER);
			fileEnd = HEADER;
		}
		return f;
	}

	function writeIndex(f:Int, at:Float):Void
	{
		final list:Array<Dynamic> = [for (e in entries) e.toObject()];
		final raw:Bytes = Bytes.ofString(haxe.Json.stringify({entries: list}));
		final comp:Bytes = NoteCodec.compress(raw);
		Native.seek(f, at);
		Native.write(f, comp, 5, comp.length - 5);
		Native.flush(f);
		final head:Bytes = Bytes.alloc(HEADER);
		head.blit(0, Bytes.ofString(MAGIC), 0, 8);
		head.setInt32(8, VERSION);
		head.setDouble(16, at);
		head.setDouble(24, comp.length - 5);
		head.setDouble(32, raw.length);
		head.blit(40, comp, 0, 5);
		Native.seek(f, 0);
		Native.write(f, head, 0, HEADER);
		Native.flush(f);
		fileEnd = at + comp.length - 5;
	}

	function liveBytes():Float
	{
		var n:Float = HEADER;
		for (e in entries) for (b in e.blocks) n += b.comp;
		return n;
	}

	public function maybeCompact(force:Bool = false):Void
	{
		lock.acquire();
		try {
			final live:Float = liveBytes();
			final dead:Float = fileEnd - live;
			if (force || (dead > live && dead > 8 * 1048576.0)) compact();
		} catch (e:Dynamic) {
			trace('Could not tidy the cache: $e');
		}
		lock.release();
	}

	function compact():Void
	{
		status = 'tidying cache.bin';
		final temp:String = path + '.tmp';
		final src:Int = Native.open(path, Native.READ);
		if (src < 0) return;
		final dst:Int = Native.open(temp, Native.WRITE);
		if (dst < 0) {
			Native.close(src);
			return;
		}
		try {
			final head:Bytes = Bytes.alloc(HEADER);
			head.blit(0, Bytes.ofString(MAGIC), 0, 8);
			head.setInt32(8, VERSION);
			Native.write(dst, head, 0, HEADER);
			var at:Float = HEADER;
			var buf:Bytes = Bytes.alloc(1 << 20);
			final moved:Map<String, Array<Float>> = new Map();
			for (e in entries) {
				final offsets:Array<Float> = [];
				for (b in e.blocks) {
					if (buf.length < b.comp) buf = Bytes.alloc(b.comp);
					Native.readAt(src, b.offset, buf, 0, b.comp);
					Native.write(dst, buf, 0, b.comp);
					offsets.push(at);
					at += b.comp;
				}
				moved.set(e.key, offsets);
			}
			for (e in entries) {
				final offsets:Array<Float> = moved.get(e.key);
				for (i in 0...e.blocks.length) e.blocks[i].offset = offsets[i];
			}
			writeIndex(dst, at);
			Native.close(dst);
			Native.close(src);
			sys.FileSystem.deleteFile(path);
			sys.FileSystem.rename(temp, path);
		} catch (e:Dynamic) {
			Native.close(dst);
			Native.close(src);
			try sys.FileSystem.deleteFile(temp) catch (x:Dynamic) {}

			entries = new Map();
			try load() catch (x:Dynamic) {}
			throw e;
		}
	}

	public function remove(key:String):Void
	{
		lock.acquire();
		try {
			if (entries.exists(key)) {
				entries.remove(key);
				final f:Int = openForWrite();
				writeIndex(f, fileEnd);
				Native.close(f);
			}
		} catch (e:Dynamic) {
			trace('Could not update the cache: $e');
		}
		lock.release();
	}

	static function cutTimes(b:NoteBuilder):Array<Float>
	{
		final total:Float = b.totalEntries();
		if (total <= BLOCK_ENTRIES) return [];
		final step:Int = 64;
		final sample:Array<Float> = [];
		for (l in b.lanes) {
			var i:Int = 0;
			while (i < l.length) {
				sample.push(l.times[i]);
				i += step;
			}
		}
		sample.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
		final per:Int = Std.int(BLOCK_ENTRIES / step);
		final cuts:Array<Float> = [];
		var k:Int = per;
		while (k < sample.length) {
			final t:Float = sample[k];
			if (cuts.length == 0 || t > cuts[cuts.length - 1]) cuts.push(t);
			k += per;
		}
		return cuts;
	}

	static function lowerBound(a:Array<Float>, n:Int, t:Float, from:Int):Int
	{
		var lo:Int = from, hi:Int = n;
		while (lo < hi) {
			final mid:Int = (lo + hi) >>> 1;
			if (a[mid] < t) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}
}

class CacheReader
{
	var file:Int;
	var buf:Bytes = Bytes.alloc(1 << 16);

	public function new(path:String)
	{
		file = Native.open(path, Native.READ);
		if (file < 0) throw 'Could not open "$path"';
	}

	public function readBlock(info:BlockInfo):Bytes
	{
		if (buf.length < info.comp) buf = Bytes.alloc(info.comp);
		Native.readAt(file, info.offset, buf, 0, info.comp);
		return NoteCodec.decompress(buf, info.comp, info.raw);
	}

	public function close():Void
	{
		if (file >= 0) Native.close(file);
		file = -1;
	}
}

class BlockInfo
{
	public var offset:Float = 0;
	public var comp:Int = 0;
	public var raw:Int = 0;
	public var startUs:Float = 0;
	public var endUs:Float = 0;
	public var entries:Float = 0;
	public var opp:Float = 0;
	public var player:Float = 0;

	public function new() {}
}

class CacheEntry
{
	public var key:String;
	public var stamp:String;
	public var meta:ChartMeta;
	public var keys:Int = 4;
	public var blocks:Array<BlockInfo> = [];

	public function new() {}

	public function compBytes():Float
	{
		var n:Float = 0;
		for (b in blocks) n += b.comp;
		return n;
	}

	public function toObject():Dynamic
		return {
			key: key,
			stamp: stamp,
			keys: keys,
			meta: meta.toObject(),
			blocks: [for (b in blocks) [b.offset, b.comp, b.raw, b.startUs, b.endUs, b.entries, b.opp, b.player]]
		};

	public static function fromObject(o:Dynamic):CacheEntry
	{
		final e:CacheEntry = new CacheEntry();
		e.key = o.key;
		e.stamp = o.stamp;
		e.keys = o.keys != null ? Std.int(o.keys) : 4;
		e.meta = ChartMeta.fromObject(o.meta);
		final list:Array<Dynamic> = o.blocks;
		for (a in list) {
			final b:BlockInfo = new BlockInfo();
			b.offset = a[0];
			b.comp = Std.int(a[1]);
			b.raw = Std.int(a[2]);
			b.startUs = a[3];
			b.endUs = a[4];
			b.entries = a[5];
			b.opp = a[6];
			b.player = a[7];
			e.blocks.push(b);
		}
		return e;
	}
}
