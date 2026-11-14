package strand.chart;

import strand.cache.BinCache;
import strand.cache.BinCache.CacheEntry;

class ChartLoader
{
	public static var status:String = null;
	public static var progress:Float = -1;

	public static function isChart(file:String):Bool
	{
		final lower:String = file.toLowerCase();
		if (!(StringTools.endsWith(lower, '.json') || StringTools.endsWith(lower, '.thr'))) return false;
		final base:String = haxe.io.Path.withoutExtension(lower);
		return !(base == 'events' || StringTools.endsWith(base, '-events') || StringTools.endsWith(base, '-metadata') || base == 'metadata');
	}

	public static function stampOf(path:String):String
	{
		var date:Float = 0;
		try date = sys.FileSystem.stat(path).mtime.getTime() catch (e:Dynamic) {}
		return strand.native.Native.fileSize(path) + ':' + date;
	}

	public static function read(path:String):JsonChart.ChartResult
	{
		final lower:String = path.toLowerCase();
		status = 'reading chart';
		progress = 0;
		final report:Float->Void = p -> progress = p;
		final r = StringTools.endsWith(lower, '.thr') ? ThrChart.load(path, report) : JsonChart.load(path, report);
		status = null;
		progress = -1;
		return r;
	}

	static function fourKeys(keys:Int, e:CacheEntry):CacheEntry
	{
		if (keys != 4) throw 'This chart has $keys keys. Strand only plays 4-key charts for now.';
		return e;
	}

	public static function entryFor(cache:BinCache, key:String, path:String, threads:Int):CacheEntry
	{
		final stamp:String = stampOf(path);
		final hit:CacheEntry = cache.find(key, stamp);
		if (hit != null) return fourKeys(hit.keys, hit);
		final r = read(path);
		fourKeys(r.meta.keys, null);
		status = 'making cache';
		final e:CacheEntry = cache.store(key, stamp, r.meta, r.builder, threads);
		status = null;
		return e;
	}
}
