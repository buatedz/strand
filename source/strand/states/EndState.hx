package strand.states;

import flixel.FlxG;
import strand.Discord;
import strand.Songs;
import strand.ui.Term;
import strand.ui.TermState;

class EndState extends TermState
{
	var song:SongInfo;
	var wait:Float = 0.4;

	public function new(song:SongInfo)
	{
		super();
		this.song = song;
	}

	override public function create():Void
	{
		super.create();
		Discord.menus();
		setTitle(['freeplay', song.name]);
		setHint(['any key  back to freeplay']);
		add(Term.text(Term.PAD_LEFT + Term.ch(2), mainTop(), 'thank you for playing', Term.FG));
		if (song.meta != null)
			add(Term.text(Term.PAD_LEFT + Term.ch(2), mainTop() + Term.LINE * 2, song.name + '  ' + Term.fmtInt(song.meta.notes) + ' notes  ' + Term.mmss(song.lengthMs()), Term.DIM));
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		wait -= elapsed;
		if (wait <= 0 && FlxG.keys.justPressed.ANY) FlxG.switchState(() -> new MenuState('freeplay'));
	}
}
