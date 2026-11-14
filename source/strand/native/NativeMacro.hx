package strand.native;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class NativeMacro
{
	public static function build():Array<Field>
	{
		final file:String = Context.getPosInfos(Context.currentPos()).file;
		final dir:String = haxe.io.Path.directory(sys.FileSystem.absolutePath(file)).split('\\').join('/');
		Context.getLocalClass().get().meta.add(':buildXml', [macro $v{'<include name="' + dir + '/build.xml" />'}], Context.currentPos());
		return null;
	}
}
#end
