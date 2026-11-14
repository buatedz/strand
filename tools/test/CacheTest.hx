import strand.cache.BinCache;
import strand.cache.NoteCodec;
import strand.chart.ChartLoader;
import strand.play.NoteBlock;

class CacheTest
{
	static function main()
	{
		final args:Array<String> = Sys.args();
		final out:String = args.shift();
		if (sys.FileSystem.exists(out)) sys.FileSystem.deleteFile(out);
		final cache:BinCache = new BinCache(out);
		for (path in args) {
			final t0:Float = haxe.Timer.stamp();
			final r = StringTools.endsWith(path, ".thrcache.zip") ? ThrCacheZip.load(path) : ChartLoader.read(path);
			final t1:Float = haxe.Timer.stamp();
			final before:Float = cache.fileBytes();
			final e = cache.store(path, ChartLoader.stampOf(path), r.meta, r.builder, 4);
			final t2:Float = haxe.Timer.stamp();

			final reopened:BinCache = new BinCache(out);
			final entry = reopened.find(path, ChartLoader.stampOf(path));
			final reader = reopened.reader();
			var notes:Float = 0, merged:Float = 0, mergedDrawn:Float = 0;
			for (k in 0...entry.blocks.length) {
				final info = entry.blocks[k];
				final raw = reader.readBlock(info);
				final blk:NoteBlock = new NoteBlock(k, info.startUs / 1000, info.endUs / 1000);
				NoteCodec.decode(raw, info.startUs, 0, blk);
				notes += blk.notes;
				final blk2:NoteBlock = new NoteBlock(k, info.startUs / 1000, info.endUs / 1000);
				NoteCodec.decode(raw, info.startUs, 1, blk2);
				merged += blk2.notes;
				mergedDrawn += blk2.drawn;
			}
			reader.close();
			final t3:Float = haxe.Timer.stamp();
			Sys.println(path);
			Sys.println('  format ${r.meta.format}, song "${r.meta.song}", bpm ${r.meta.bpm}, speed ${r.meta.speed}, keys ${r.meta.keys}');
			Sys.println('  notes ${r.meta.notes} (dropped ${r.meta.dropped}), entries ${r.meta.entries}, blocks ${e.blocks.length}');
			Sys.println('  avg nps ${Math.round(r.meta.avgNps)}, peak nps ${r.meta.peakNps}, ${r.meta.firstMs}..${r.meta.lastMs} ms');
			Sys.println('  cache bytes ${e.compBytes()} (file now ${reopened.fileBytes()})');
			Sys.println('  read ${fmt(t1 - t0)}s, compress ${fmt(t2 - t1)}s, decode x2 ${fmt(t3 - t2)}s');
			Sys.println('  decoded notes $notes ${notes == r.meta.notes ? "OK" : "MISMATCH"}; with 1 ms merge: $merged notes in $mergedDrawn entries');
		}
	}

	static function fmt(f:Float):String
		return Std.string(Math.round(f * 100) / 100);
}
