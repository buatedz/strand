package strand.ui;

import flixel.group.FlxGroup;
import flixel.text.FlxText;

typedef MenuRow =
{
	?label:String,
	?value:String,

	?act:Bool,

	?gap:Bool,

	?noSel:Bool,
	?muted:Bool,
	?enter:Void->Void,

	?change:Int->Void,

	?data:Dynamic
}

class MenuList extends FlxGroup
{
	public var rows(default, null):Array<MenuRow> = [];
	public var selected:Int = 0;
	public var x:Float;
	public var y:Float;
	public var maxHeight:Float;

	public var rightEdge(default, null):Float = 0;

	var cursors:Array<FlxText> = [];
	var labels:Array<FlxText> = [];
	var values:Array<FlxText> = [];
	var scroll:Int = 0;

	public function new(x:Float, y:Float, maxHeight:Float)
	{
		super();
		this.x = x;
		this.y = y;
		this.maxHeight = maxHeight;
	}

	public function setRows(list:Array<MenuRow>, ?keepSelection:Bool = false):Void
	{
		rows = list;
		if (!keepSelection || selected >= rows.length || !selectable(selected)) {
			selected = 0;
			while (selected < rows.length && !selectable(selected)) selected++;
			if (selected >= rows.length) selected = 0;
			scroll = 0;
		}
		redraw();
	}

	public inline function current():MenuRow
		return rows.length > 0 ? rows[selected] : null;

	function selectable(i:Int):Bool
	{
		final r:MenuRow = rows[i];
		return r != null && r.gap != true && r.noSel != true;
	}

	public function move(dir:Int):Void
	{
		if (rows.length == 0) return;
		var i:Int = selected;
		for (k in 0...rows.length) {
			i = (i + dir + rows.length) % rows.length;
			if (selectable(i)) break;
		}
		selected = i;
		redraw();
	}

	function visibleRows():Int
		return Std.int(Math.max(1, Math.floor(maxHeight / Term.LINE)));

	function textAt(list:Array<FlxText>, i:Int, color:Int):FlxText
	{
		var t:FlxText = list[i];
		if (t == null) {
			t = Term.text(0, 0, '', color);
			list[i] = t;
			add(t);
		}
		t.visible = true;
		t.color = color;
		return t;
	}

	public function redraw():Void
	{
		final room:Int = visibleRows();
		if (selected < scroll) scroll = selected;
		if (selected >= scroll + room) scroll = selected - room + 1;
		if (scroll > Math.max(0, rows.length - room)) scroll = Std.int(Math.max(0, rows.length - room));
		var labelChars:Int = 0;
		for (r in rows) if (r.label != null && r.gap != true && r.value != null) labelChars = Std.int(Math.max(labelChars, r.label.length));
		final labelX:Float = x + Term.ch(2);
		final valueX:Float = labelX + Term.ch(labelChars + 3);
		rightEdge = valueX;
		var shown:Int = 0;
		for (i in 0...room) {
			final idx:Int = scroll + i;
			final ty:Float = y + i * Term.LINE;
			if (idx >= rows.length) {
				if (cursors[i] != null) {
					cursors[i].visible = false;
					labels[i].visible = false;
					values[i].visible = false;
				}
				continue;
			}
			final r:MenuRow = rows[idx];
			final sel:Bool = idx == selected;
			final c:FlxText = textAt(cursors, i, Term.ACCENT);
			final l:FlxText = textAt(labels, i, sel ? Term.FG : (r.act == true ? Term.FAINT : Term.DIM));
			final v:FlxText = textAt(values, i, r.muted == true || r.value == '-' ? Term.DIM : Term.FG);
			c.text = sel && r.gap != true ? '>' : '';
			c.setPosition(x, ty);
			l.text = r.gap == true ? '' : (r.label != null ? r.label : '');
			l.setPosition(labelX, ty);
			v.text = r.gap == true || r.value == null ? '' : r.value;
			v.setPosition(valueX, ty);
			if (v.text.length > 0) rightEdge = Math.max(rightEdge, valueX + v.width);
			else rightEdge = Math.max(rightEdge, labelX + l.width);
			shown++;
		}
	}
}

class InfoGrid extends FlxGroup
{
	public var x:Float;
	public var y:Float;

	var labels:Array<FlxText> = [];
	var values:Array<FlxText> = [];
	var lastKey:String = '';

	public function new(x:Float, y:Float)
	{
		super();
		this.x = x;
		this.y = y;
	}

	public function show(rows:Array<Array<String>>):Void
	{
		final key:String = x + '|' + y + '|' + Std.string(rows);
		if (key == lastKey) return;
		lastKey = key;
		var labelChars:Int = 0;
		for (r in rows) if (r != null) labelChars = Std.int(Math.max(labelChars, r[0].length));
		final valueX:Float = x + Term.ch(labelChars + 2);
		var i:Int = 0;
		for (k in 0...rows.length) {
			final r:Array<String> = rows[k];
			final ty:Float = y + k * Term.LINE;
			if (r == null) continue;
			var l:FlxText = labels[i];
			var v:FlxText = values[i];
			if (l == null) {
				labels[i] = l = Term.text(0, 0, '', Term.DIM);
				values[i] = v = Term.text(0, 0, '', Term.FG);
				add(l);
				add(v);
			}
			l.visible = v.visible = true;
			l.text = r[0];
			l.setPosition(x, ty);
			v.text = r[1];
			v.color = r.length > 2 && r[2] == 'hot' ? Term.ACCENT : (r[1] == '-' || (r.length > 2 && r[2] == 'muted') ? Term.DIM : Term.FG);
			v.setPosition(valueX, ty);
			i++;
		}
		for (k in i...labels.length) {
			labels[k].visible = false;
			values[k].visible = false;
		}
	}

	public function hideAll():Void
		show([]);
}
