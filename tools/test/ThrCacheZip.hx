import haxe.io.Bytes;
import strand.chart.ChartMeta;
import strand.chart.NoteBuilder;
import strand.chart.ThrChart;
import strand.chart.ThrChart.ZipReader;

class ThrCacheZip
{
	public static function load(path:String):{meta:ChartMeta, builder:NoteBuilder}
	{
		final zip = new ZipReader(path);
		final b:NoteBuilder = new NoteBuilder(4);
		var raw:Bytes = null, comp:Bytes = null;
		final names:Array<String> = [for (e in zip.entries) if (e.name.indexOf('notes-') != -1) e.name];
		names.sort((a, c) -> a < c ? -1 : 1);
		for (name in names) {
			final e = zip.get(name);
			final size:Int = Std.int(e.size);
			if (raw == null || raw.length < size) raw = Bytes.alloc(size);
			final c:Int = Std.int(e.compSize);
			if (comp == null || comp.length < c) comp = Bytes.alloc(c);
			zip.readRaw(e, 0, comp, 0, c);
			ZipReader.decompress(e.method, comp, 0, c, raw, 0, size);
			final count:Int = Std.int(raw.getDouble(8));
			var data:Bytes = raw, at:Int = 32;
			if (raw.getInt32(24) & 1 != 0) {
				data = Bytes.alloc(count * 16);
				ThrChart.unfilter(raw, 32, data, 0, count, 16);
				at = 0;
			}
			for (i in 0...count) {
				final q:Int = at + i * 16;
				final lane:Int = data.get(q + 12);
				final must:Bool = data.getUInt16(q + 14) & (1 << 13) != 0;
				b.add(data.getDouble(q), b.laneOf(lane, (lane < 4) == must), data.getFloat(q + 8));
			}
		}
		zip.close();
		b.finish();
		final m:ChartMeta = new ChartMeta();
		m.format = 'thrcache.zip';
		m.measure(b);
		return {meta: m, builder: b};
	}
}
