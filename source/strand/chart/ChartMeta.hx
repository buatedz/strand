package strand.chart;

class ChartMeta
{
	public var song:String = '';
	public var bpm:Float = 100;
	public var speed:Float = 1;
	public var keys:Int = 4;

	public var notes:Float = 0;

	public var entries:Float = 0;
	public var firstMs:Float = 0;
	public var lastMs:Float = 0;
	public var avgNps:Float = 0;
	public var peakNps:Float = 0;
	public var dropped:Float = 0;
	public var format:String = 'json';

	public function new() {}

	public function toObject():Dynamic
		return {
			song: song,
			bpm: bpm,
			speed: speed,
			keys: keys,
			notes: notes,
			entries: entries,
			firstMs: firstMs,
			lastMs: lastMs,
			avgNps: avgNps,
			peakNps: peakNps,
			dropped: dropped,
			format: format
		};

	public static function fromObject(o:Dynamic):ChartMeta
	{
		final m:ChartMeta = new ChartMeta();
		if (o == null) return m;
		m.song = o.song != null ? o.song : '';
		m.bpm = num(o.bpm, 100);
		m.speed = num(o.speed, 1);
		m.keys = Std.int(num(o.keys, 4));
		m.notes = num(o.notes, 0);
		m.entries = num(o.entries, 0);
		m.firstMs = num(o.firstMs, 0);
		m.lastMs = num(o.lastMs, 0);
		m.avgNps = num(o.avgNps, 0);
		m.peakNps = num(o.peakNps, 0);
		m.dropped = num(o.dropped, 0);
		m.format = o.format != null ? o.format : 'json';
		return m;
	}

	static inline function num(v:Dynamic, fallback:Float):Float
	{
		if (v == null) return fallback;
		final f:Float = v;
		return Math.isNaN(f) ? fallback : f;
	}

	public function measure(b:NoteBuilder):Void
	{
		notes = 0;
		entries = 0;
		var first:Float = Math.POSITIVE_INFINITY, last:Float = Math.NEGATIVE_INFINITY;
		for (l in b.lanes) {
			notes += l.notes;
			entries += l.length;
			if (l.length > 0) {
				if (l.times[0] < first) first = l.times[0];
				if (l.times[l.length - 1] > last) last = l.times[l.length - 1];
			}
		}
		dropped = b.dropped;
		if (entries == 0) {
			firstMs = lastMs = 0;
			avgNps = peakNps = 0;
			return;
		}
		firstMs = first / 1000;
		lastMs = last / 1000;
		final span:Float = Math.max(1, lastMs - firstMs);
		avgNps = notes / (span / 1000);

		final buckets:Int = Std.int(Math.min(1 << 24, Math.ceil(span / 1000) + 1));
		final per:Array<Float> = [];
		per[buckets - 1] = 0;
		for (i in 0...buckets) per[i] = 0;
		for (l in b.lanes) {
			for (i in 0...l.length) {
				var k:Int = Std.int((l.times[i] / 1000 - firstMs) / 1000);
				if (k >= buckets) k = buckets - 1;
				per[k] += l.counts[i];
			}
		}
		var peak:Float = 0;
		for (v in per) if (v > peak) peak = v;
		peakNps = peak;
	}
}
