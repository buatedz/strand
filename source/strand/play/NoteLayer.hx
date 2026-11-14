package strand.play;

import openfl.Vector;
import openfl.display.Sprite;
import strand.play.NoteBlock.LaneData;

class NoteLayer extends Sprite
{
	static inline final MAX_QUADS:Int = 400000;
	static inline final CONFIRM_FPS:Float = 24;

	public var store:NoteStore;
	public var skin(default, null):NoteSkin;
	public var downscroll:Bool = false;
	public var pxPerMs:Float = 0.45;

	public var skipPx:Float = 1;
	public var smooth:Bool = false;

	public var strumX:Array<Float> = [];
	public var strumY:Float = 50;

	public var farY:Float = 720;

	public var showNotes:Bool = true;
	public var drawHolds:Bool = true;
	public var showOpponent:Bool = true;
	public var lightOpp:Bool = true;
	public var lightPlayer:Bool = true;

	public var litMs:Float = 150;

	public var stepMs:Float = 150;
	public var splashPlayer:Bool = true;
	public var splashOpp:Bool = false;

	public var drawnNotes(default, null):Int = 0;
	public var skippedNotes(default, null):Float = 0;
	public var maxDrawn(default, null):Int = 0;
	public var maxSkipped(default, null):Float = 0;

	var sides:Array<Sprite> = [];

	var sideIndices:Array<Vector<Int>> = [new Vector<Int>(), new Vector<Int>()];
	var sideTransforms:Array<Vector<Float>> = [new Vector<Float>(), new Vector<Float>()];
	var indices:Vector<Int>;
	var transforms:Vector<Float>;
	var quads:Int = 0;

	var lastHit:Array<Float> = [];
	var lastLen:Array<Float> = [];

	public function new(store:NoteStore, skin:NoteSkin)
	{
		super();
		this.store = store;
		this.skin = skin;
		mouseEnabled = mouseChildren = false;
		for (i in 0...2) {
			final s:Sprite = new Sprite();
			s.mouseEnabled = false;
			sides.push(s);
			addChild(s);
		}
	}

	public function setOpponentAlpha(a:Float):Void
		sides[NoteStore.OPP].alpha = a;

	inline function quad(id:Int, x:Float, y:Float, sx:Float, sy:Float):Void
	{
		if (id >= 0 && quads < MAX_QUADS) {
			indices[quads] = id;
			final o:Int = quads * 6;
			transforms[o] = sx;
			transforms[o + 1] = 0;
			transforms[o + 2] = 0;
			transforms[o + 3] = sy;
			transforms[o + 4] = x;
			transforms[o + 5] = y;
			quads++;
		}
	}

	inline function centred(id:Int, cx:Float, cy:Float):Void
	{
		if (id >= 0) quad(id, cx - skin.tileW[id] / 2, cy - skin.tileH[id] / 2, 1, 1);
	}

	public function render(songTime:Float):Void
	{
		drawnNotes = 0;
		skippedNotes = 0;
		final keys:Int = store.keys;
		for (l in 0...store.laneCount) {
			lastHit[l] = store.lastBefore(l, songTime);
			lastLen[l] = store.lastLen;
		}
		for (side in 0...2) {
			quads = 0;
			indices = sideIndices[side];
			transforms = sideTransforms[side];
			if (side == NoteStore.PLAYER || showOpponent) {
				for (k in 0...keys) drawStrum(side * keys + k, songTime);
				if (showNotes) for (k in 0...keys) drawLane(side * keys + k, songTime);
				if (side == NoteStore.PLAYER ? splashPlayer : splashOpp) for (k in 0...keys) drawSplash(side * keys + k, songTime);
			}
			flush(sides[side]);
		}
		if (drawnNotes > maxDrawn) maxDrawn = drawnNotes;
		if (skippedNotes > maxSkipped) maxSkipped = skippedNotes;
	}

	inline function centreX(l:Int):Float
	{
		final k:Int = l % store.keys;
		return strumX[l] + skin.tileW[skin.strum[k]] / 2;
	}

	inline function centreY(l:Int):Float
		return strumY + skin.tileH[skin.strum[l % store.keys]] / 2;

	function drawStrum(l:Int, t:Float):Void
	{
		final k:Int = l % store.keys;
		final cx:Float = centreX(l), cy:Float = centreY(l);
		final lit:Bool = l < store.keys ? lightOpp : lightPlayer;
		final frames:Array<Int> = skin.confirm[k];
		if (lit && frames.length > 0) {
			final hit:Float = lastHit[l];
			final since:Float = t - hit;
			final holding:Bool = lastLen[l] > 0 && hit + lastLen[l] > t;
			if (holding || since < litMs) {
				final age:Float = holding && since > stepMs ? since % stepMs : since;
				var f:Int = Std.int(age / 1000 * CONFIRM_FPS);
				if (f >= frames.length) f = frames.length - 1;
				centred(frames[f], cx, cy);
				return;
			}
		}
		centred(skin.strum[k], cx, cy);
	}

	function drawSplash(l:Int, t:Float):Void
	{
		final k:Int = l % store.keys;
		if (k >= skin.splash.length) return;
		final hit:Float = lastHit[l];
		final since:Float = t - hit;
		if (since < 0 || since > 1000) return;
		final anims:Array<Array<Int>> = skin.splash[k];

		final h:Int = Std.int(Math.abs(hit * 7.31)) & 0xFFFF;
		final a:Int = h % anims.length;
		final fps:Float = skin.splashFps[0] + (h >> 4) % (skin.splashFps[1] - skin.splashFps[0] + 1);
		final f:Int = Std.int(since / 1000 * fps);
		final frames:Array<Int> = anims[a];
		if (f >= frames.length) return;
		final off:Array<Float> = skin.splashOff[k][a];
		quad(frames[f], strumX[l] + off[0], strumY + off[1], 1, 1);
	}

	function drawLane(l:Int, songTime:Float):Void
	{
		final blocks:Array<NoteBlock> = store.blocks;
		if (blocks.length == 0) return;
		final k:Int = l % store.keys;
		final dir:Float = downscroll ? -1 : 1;
		final cx:Float = centreX(l);
		final sy:Float = centreY(l);
		final span:Float = Math.abs(farY - sy);
		final noteH:Float = skin.note[k] >= 0 ? skin.tileH[skin.note[k]] : 0;
		final tEnd:Float = songTime + (span + noteH) / pxPerMs;
		final skipMs:Float = skipPx > 0 ? skipPx / pxPerMs : 0;
		final noteId:Int = skin.note[k];
		final holds:Bool = drawHolds && skin.holdPiece[k] >= 0;

		if (holds && lastLen[l] > 0 && lastHit[l] + lastLen[l] > songTime)
			hold(k, cx, sy, songTime, lastHit[l] + lastLen[l], tEnd, songTime, dir);

		var lastDrawn:Float = Math.NEGATIVE_INFINITY;
		var b:Int = store.blockAt(songTime);
		while (b < blocks.length) {
			final block:NoteBlock = blocks[b];
			if (block.startMs >= tEnd) break;
			b++;
			final lanes:Array<LaneData> = block.lanes;
			if (lanes == null) continue;
			final lane:LaneData = lanes[l];
			final times:Array<Float> = lane.times;
			final lens:Array<Float> = holds ? lane.lens : null;
			final n:Int = lane.n;
			var i:Int = lane.lowerBound(songTime);
			while (i < n) {
				final t:Float = times[i];
				if (t >= tEnd) break;
				if (skipMs > 0 && t - lastDrawn < skipMs) {
					final j:Int = lowerBoundFrom(times, n, lastDrawn + skipMs, i + 1);
					skippedNotes += j - i;
					i = j;
					continue;
				}
				final y:Float = sy + dir * (t - songTime) * pxPerMs;
				if (lens != null && lens[i] > 0) hold(k, cx, y, t, t + lens[i], tEnd, songTime, dir);
				centred(noteId, cx, y);
				drawnNotes++;
				lastDrawn = t;
				i++;
			}
		}
	}

	function hold(k:Int, cx:Float, fromY:Float, fromT:Float, endT:Float, tEnd:Float, songTime:Float, dir:Float):Void
	{
		final piece:Int = skin.holdPiece[k];
		final cap:Int = skin.holdEnd[k];
		final pw:Float = skin.tileW[piece];
		final capped:Bool = endT < tEnd && cap >= 0;
		final stopT:Float = capped ? endT : tEnd;
		final len:Float = (stopT - fromT) * pxPerMs;
		if (len >= 0.5) {
			final y:Float = dir > 0 ? fromY : fromY - len;
			quad(piece, cx - pw / 2, y, 1, len / skin.tileH[piece]);
		}
		if (capped) {
			final endY:Float = fromY + dir * (len - 1);
			final cw:Float = skin.tileW[cap];
			final ch:Float = skin.tileH[cap];

			if (dir > 0) quad(cap, cx - cw / 2, endY, 1, 1);
			else quad(cap, cx - cw / 2, endY, 1, -1);
		}
	}

	static inline function lowerBoundFrom(a:Array<Float>, n:Int, t:Float, from:Int):Int
	{
		var lo:Int = from, step:Int = 1, hi:Int = from;
		while (hi < n && a[hi] < t) {
			lo = hi + 1;
			hi += step;
			step <<= 1;
		}
		if (hi > n) hi = n;
		while (lo < hi) {
			final mid:Int = (lo + hi) >>> 1;
			if (a[mid] < t) lo = mid + 1;
			else hi = mid;
		}
		return lo;
	}

	function flush(target:Sprite):Void
	{
		indices.length = quads;
		transforms.length = quads * 6;
		target.graphics.clear();
		if (quads == 0) return;
		target.graphics.beginBitmapFill(skin.atlas, null, false, smooth);
		target.graphics.drawQuads(skin.rects, indices, transforms);
		target.graphics.endFill();
	}

	public function dispose():Void
	{
		for (s in sides) s.graphics.clear();
		if (skin != null) skin.dispose();
		skin = null;
	}
}
