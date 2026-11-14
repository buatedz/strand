package strand.play;

class LaneData
{
	public var n:Int = 0;

	public var times:Array<Float>;

	public var cum:Array<Float>;

	public var lens:Array<Float>;

	public function new() {}

	public inline function lowerBound(t:Float):Int
	{
		var lo:Int = 0, hi:Int = n;
		while (lo < hi) {
			final mid:Int = (lo + hi) >>> 1;
			if (times[mid] < t) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}

	public inline function notesBefore(i:Int):Float
		return i <= 0 ? 0 : cum[i - 1];
}

class NoteBlock
{
	public var index:Int;

	public var startMs:Float;
	public var endMs:Float;
	public var lanes:Array<LaneData> = null;

	public var notes:Float = 0;

	public var drawn:Float = 0;

	public var before:Array<Float> = [0, 0];

	public function new(index:Int, startMs:Float, endMs:Float)
	{
		this.index = index;
		this.startMs = startMs;
		this.endMs = endMs;
	}

	public inline function loaded():Bool
		return lanes != null;
}
