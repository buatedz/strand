package strand.native;

#if (cpp && static_link)
@:cppFileCode('extern "C" int SDL_GL_SetSwapInterval(int interval);')
#end
class Vsync
{
	public static function set(on:Bool):Bool
	{
		#if (cpp && static_link)
		final r:Int = untyped __cpp__('SDL_GL_SetSwapInterval({0})', on ? 1 : 0);
		return r == 0;
		#else
		return false;
		#end
	}
}
