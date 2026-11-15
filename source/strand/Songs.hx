package strand;

import strand.cache.BinCache;
import strand.cache.BinCache.CacheEntry;
import strand.chart.ChartLoader;
import strand.chart.ChartMeta;

class SongInfo
{
	public var folder:String;
	public var paths:Array<String>;
	public var key:String;
	public var bytes:Float = 0;

	public var meta:ChartMeta = null;
	public var cacheBytes:Float = 0;
	public var error:String = null;
	public var building:Bool = false;

	public function new() {}

	public var name(get, never):String;

	function get_name():String
		return meta != null && meta.song != null && meta.song.length > 0 ? meta.song : folder;

	public function lengthMs():Float
		return meta != null ? meta.lastMs + 1000 : -1;
}

class Songs
{
	public static var cache(default, null):BinCache = null;
	public static var list(default, null):Array<SongInfo> = [];

	static inline final PREWARM_BYTES:Float = 64 * 1048576.0;

	static var queue:Array<SongInfo> = [];
	static var queueLock:sys.thread.Mutex = new sys.thread.Mutex();
	static var queueWake:sys.thread.Lock = new sys.thread.Lock();
	static var worker:sys.thread.Thread = null;
	public static var busyKey(default, null):String = null;

	public static function init():Void
	{
		try {
			for (dir in [Paths.data(), Paths.songs(), Paths.scripts()])
				if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
		} catch (e:Dynamic) {}
		cache = new BinCache(Paths.cache());
		scan();
	}

	public static function scan():Void
	{
		final out:Array<SongInfo> = [];
		try {
			final folders:Array<String> = sys.FileSystem.readDirectory(Paths.data());
			folders.sort(compareNames);
			for (folder in folders) {
				final dir:String = Paths.data() + '/' + folder;
				if (!sys.FileSystem.isDirectory(dir)) continue;
				final charts:Array<String> = chartFiles(dir);
				if (charts.length == 0) continue;
				final s:SongInfo = new SongInfo();
				s.folder = folder;
				if (Prefs.runSplitCharts && charts.length > 1) {
					s.paths = [for (c in charts) dir + '/' + c];
					s.key = ('data/' + folder + '/#layered').toLowerCase();
				} else {
					final chart:String = pickChart(charts, folder);
					s.paths = [dir + '/' + chart];
					s.key = ('data/' + folder + '/' + chart).toLowerCase();
				}
				s.bytes = 0;
				for (p in s.paths) s.bytes += strand.native.Native.fileSize(p);
				refresh(s);
				out.push(s);
			}
		} catch (e:Dynamic) {
			trace('Could not list assets/data: $e');
		}
		list = out;
	}

	static function compareNames(a:String, b:String):Int
	{
		final x:String = a.toLowerCase(), y:String = b.toLowerCase();
		return x < y ? -1 : x > y ? 1 : 0;
	}

	static function chartFiles(dir:String):Array<String>
	{
		final files:Array<String> = [for (f in sys.FileSystem.readDirectory(dir)) if (ChartLoader.isChart(f) && !sys.FileSystem.isDirectory(dir + '/' + f)) f];
		files.sort(compareNames);
		return files;
	}

	static function pickChart(files:Array<String>, folder:String):String
	{
		final lower:String = folder.toLowerCase();
		for (want in [lower + '.thr', lower + '.json'])
			for (f in files) if (f.toLowerCase() == want) return f;
		for (f in files) if (StringTools.endsWith(f.toLowerCase(), '.thr')) return f;
		return files[0];
	}

	public static function refresh(s:SongInfo):Void
	{
		final e:CacheEntry = cache.find(s.key, ChartLoader.stampOfAll(s.paths));
		if (e != null) {
			s.meta = e.meta;
			s.cacheBytes = e.compBytes();
		} else {
			s.meta = null;
			s.cacheBytes = 0;
		}
	}

	public static function threads():Int
	{
		var n:Null<Int> = Std.parseInt(Sys.getEnv('NUMBER_OF_PROCESSORS'));
		if (n == null || n < 1) n = 4;
		return n > 16 ? 16 : n;
	}

	public static function prewarm(s:SongInfo):Void
	{
		if (s.meta != null || s.error != null || s.building || s.bytes > PREWARM_BYTES) return;
		queueLock.acquire();
		if (!queue.contains(s)) queue.unshift(s);
		queueLock.release();
		if (worker == null) worker = sys.thread.Thread.create(work);
		queueWake.release();
	}

	static function work():Void
	{
		while (true) {
			queueLock.acquire();
			final s:SongInfo = queue.shift();
			if (s != null) busyKey = s.key;
			queueLock.release();
			if (s == null) {
				queueWake.wait();
				continue;
			}
			if (s.meta == null && s.error == null) {
				s.building = true;
				try {
					final e:CacheEntry = ChartLoader.entryFor(cache, s.key, s.paths, Std.int(Math.max(1, threads() / 2)));
					s.meta = e.meta;
					s.cacheBytes = e.compBytes();
				} catch (e:Dynamic) {
					s.error = Std.string(e);
				}
				s.building = false;
			}
			queueLock.acquire();
			busyKey = null;
			queueLock.release();
		}
	}

	public static function waitFor(key:String):Void
	{
		while (busyKey == key) Sys.sleep(0.02);
	}

	public static function audioFiles(folder:String):Array<String>
	{
		final dir:String = Paths.songs() + '/' + folder;
		final out:Array<String> = [];
		if (!sys.FileSystem.exists(dir)) return out;
		final files:Array<String> = sys.FileSystem.readDirectory(dir);
		files.sort(compareNames);
		for (f in files) {
			final lower:String = f.toLowerCase();
			if (!StringTools.endsWith(lower, '.ogg') && !StringTools.endsWith(lower, '.wav')) continue;
			if (StringTools.startsWith(lower, 'inst')) out.unshift(dir + '/' + f);
		}
		for (f in files) {
			final lower:String = f.toLowerCase();
			if (!StringTools.endsWith(lower, '.ogg') && !StringTools.endsWith(lower, '.wav')) continue;
			if (StringTools.startsWith(lower, 'voices')) out.push(dir + '/' + f);
		}
		return out;
	}
}
