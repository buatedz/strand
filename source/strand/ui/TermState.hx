package strand.ui;

import flixel.FlxG;
import flixel.FlxState;
import flixel.text.FlxText;
import flixel.input.keyboard.FlxKey;

class TermState extends FlxState
{
	var titleText:FlxText;
	var hintText:FlxText;
	var statusText:FlxText;
	var statusTimer:Float = 0;

	override public function create():Void
	{
		super.create();
		bgColor = Term.BG;
		titleText = Term.text(Term.PAD_LEFT, Term.PAD_TOP, 'Strand', Term.DIM);
		add(titleText);
		hintText = Term.text(Term.PAD_LEFT, FlxG.height - Term.PAD_BOTTOM - 12, '', Term.HINT, 10);
		add(hintText);
		statusText = Term.text(Term.PAD_LEFT + Term.ch(2), FlxG.height - Term.PAD_BOTTOM - 12 - Term.LINE * 2, '', Term.DIM);
		add(statusText);
	}

	public inline function mainTop():Float
		return Term.PAD_TOP + Term.LINE * 2.5;

	public inline function mainBottom():Float
		return statusText.y - Term.LINE * 0.5;

	function setTitle(crumbs:Array<String>):Void
	{
		var s:String = 'Strand';
		if (crumbs.length > 0) s += '~' + [for (c in crumbs) '  /  ' + c.split('~').join('-')].join('') + '~';
		titleText.applyMarkup(s, [new flixel.text.FlxText.FlxTextFormatMarkerPair(new flixel.text.FlxText.FlxTextFormat(Term.FAINT), '~')]);
	}

	function setHint(items:Array<String>):Void
		hintText.text = items.join('     ');

	function say(text:String, seconds:Float = 3.2):Void
	{
		statusText.text = text;
		statusTimer = text == '' ? 0 : seconds;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (statusTimer > 0) {
			statusTimer -= elapsed;
			if (statusTimer <= 0) statusText.text = '';
		}
	}

	inline function upPressed():Bool
		return FlxG.keys.anyJustPressed([W, UP]);

	inline function downPressed():Bool
		return FlxG.keys.anyJustPressed([S, DOWN]);

	inline function leftPressed():Bool
		return FlxG.keys.anyJustPressed([A, LEFT]);

	inline function rightPressed():Bool
		return FlxG.keys.anyJustPressed([D, RIGHT]);

	inline function acceptPressed():Bool
		return FlxG.keys.anyJustPressed([ENTER, SPACE, Z]);

	inline function backPressed():Bool
		return FlxG.keys.anyJustPressed([ESCAPE, BACKSPACE, X]);
}
