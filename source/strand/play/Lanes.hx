package strand.play;

class Lanes
{
	public static inline final LEFT:Int = 0;
	public static inline final DOWN:Int = 1;
	public static inline final UP:Int = 2;
	public static inline final RIGHT:Int = 3;
	public static inline final DIAMOND:Int = 4;
	public static inline final CIRCLE:Int = 5;

	public static final NOTE_ANIMS:Array<String> = ['purple', 'blue', 'green', 'red', 'rombus', 'circle'];
	public static final STRUM_ANIMS:Array<String> = ['arrowLEFT', 'arrowDOWN', 'arrowUP', 'arrowRIGHT', 'arrowROMBUS', 'arrowCIRCLE'];
	public static final PRESS_ANIMS:Array<String> = ['left', 'down', 'up', 'right', 'rombus', 'circle'];

	static inline final PURPLE:Int = 0;
	static inline final BLUE:Int = 1;
	static inline final GREEN:Int = 2;
	static inline final RED:Int = 3;
	static inline final GREY:Int = 4;
	static inline final YELLOW:Int = 5;
	static inline final VIOLET:Int = 6;
	static inline final DARK_RED:Int = 7;
	static inline final DARK_BLUE:Int = 8;
	static inline final C_PURPLE:Int = 9;
	static inline final C_YELLOW:Int = 14;
	static inline final C_GREY:Int = 13;

	public static final RGB:Array<Array<Int>> = [
		[0xC24B99, 0xFFFFFF, 0x3C1F56], [0x00FFFF, 0xFFFFFF, 0x1542B7], [0x12FA05, 0xFFFFFF, 0x0A4447],
		[0xF9393F, 0xFFFFFF, 0x651038], [0x999999, 0xFFFFFF, 0x201E31], [0xFFFF00, 0xFFFFFF, 0x993300],
		[0x8B4AFF, 0xFFFFFF, 0x3B177D], [0xFF0000, 0xFFFFFF, 0x660000], [0x0033FF, 0xFFFFFF, 0x000066],
		[0xC24B99, 0xFFFFFF, 0x3C1F56], [0x00FFFF, 0xFFFFFF, 0x1542B7], [0x12FA05, 0xFFFFFF, 0x0A4447],
		[0xF9393F, 0xFFFFFF, 0x651038], [0xB8B8B8, 0xFFFFFF, 0x201E31], [0xFFFF00, 0xFFFFFF, 0x993300],
		[0x8B4AFF, 0xFFFFFF, 0x3B177D], [0xFF0000, 0xFFFFFF, 0x660000], [0x0033FF, 0xFFFFFF, 0x000066]
	];

	static final SHAPES:Array<Array<Int>> = [
		[DIAMOND],
		[LEFT, RIGHT],
		[LEFT, DIAMOND, RIGHT],
		[LEFT, DOWN, UP, RIGHT],
		[LEFT, DOWN, DIAMOND, UP, RIGHT],
		[LEFT, UP, RIGHT, LEFT, DOWN, RIGHT],
		[LEFT, UP, RIGHT, DIAMOND, LEFT, DOWN, RIGHT],
		[LEFT, DOWN, UP, RIGHT, LEFT, DOWN, UP, RIGHT],
		[LEFT, DOWN, UP, RIGHT, DIAMOND, LEFT, DOWN, UP, RIGHT]
	];

	static final COLORS:Array<Array<Int>> = [
		[GREY],
		[PURPLE, RED],
		[PURPLE, GREY, RED],
		[PURPLE, BLUE, GREEN, RED],
		[PURPLE, BLUE, GREY, GREEN, RED],
		[PURPLE, GREEN, RED, YELLOW, BLUE, DARK_BLUE],
		[PURPLE, GREEN, RED, GREY, YELLOW, BLUE, DARK_BLUE],
		[PURPLE, BLUE, GREEN, RED, YELLOW, VIOLET, DARK_RED, DARK_BLUE],
		[PURPLE, BLUE, GREEN, RED, GREY, YELLOW, VIOLET, DARK_RED, DARK_BLUE]
	];

	static inline final SIDE_WIDTH:Float = 600;
	public static inline final SWAG_WIDTH:Float = 160 * 0.7;

	public static function shape(keys:Int, lane:Int):Int
	{
		if (keys <= SHAPES.length) return SHAPES[keys - 1][lane];
		return big(keys, lane)[0];
	}

	public static function color(keys:Int, lane:Int):Int
	{
		if (keys <= COLORS.length) return COLORS[keys - 1][lane];
		return big(keys, lane)[1];
	}

	static function big(keys:Int, lane:Int):Array<Int>
	{
		final half:Int = keys >> 1;
		if (keys % 2 == 1 && lane == half) return [DIAMOND, GREY];
		final left:Bool = lane < half;
		final fromEdge:Int = left ? lane : keys - 1 - lane;
		final bands:Int = half >> 2;
		if (fromEdge >= bands * 4) return [CIRCLE, C_GREY];
		final band:Int = fromEdge >> 2;
		final pos:Int = left ? fromEdge % 4 : 3 - fromEdge % 4;
		final group:Int = band >> 1;
		if (band % 2 == 0) return [pos, (group % 2 == 1 ? YELLOW : PURPLE) + pos];
		return [CIRCLE, (group % 2 == 1 ? C_YELLOW : C_PURPLE) + pos];
	}

	public static function laneWidth(keys:Int):Float
	{
		final w:Float = SIDE_WIDTH / keys;
		return w < SWAG_WIDTH ? w : SWAG_WIDTH;
	}

	public static function scale(keys:Int):Float
	{
		final w:Float = SIDE_WIDTH / keys;
		return 0.7 * (w < SWAG_WIDTH ? w / SWAG_WIDTH : 1);
	}

	public static function strumX(keys:Int, lane:Int, side:Int, middle:Bool):Float
	{
		final w:Float = laneWidth(keys);
		final total:Float = w * keys;
		if (!middle) return (side == 0 ? 322 : 962) - total / 2 + w * lane;
		if (side == 1) return 636 - total / 2 + w * lane;
		final leftCount:Int = Std.int(keys / 2);
		if (lane < leftCount) return 306 - w * leftCount + w * lane;
		final rightStart:Float = Math.max(636 + total / 2 + 4, Math.min(971, 1271 - w * (keys - leftCount)));
		return rightStart + w * (lane - leftCount);
	}
}
