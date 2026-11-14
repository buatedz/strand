package strand;

class Paths
{
	public static var root(get, never):String;
	static var rootCache:String = null;

	static function get_root():String
	{
		if (rootCache == null) {
			var dir:String = haxe.io.Path.directory(Sys.programPath());
			if (dir == '') dir = Sys.getCwd();
			rootCache = haxe.io.Path.removeTrailingSlashes(dir.split('\\').join('/'));
		}
		return rootCache;
	}

	public static inline function assets():String
		return root + '/assets';

	public static inline function data():String
		return root + '/assets/data';

	public static inline function songs():String
		return root + '/assets/songs';

	public static inline function scripts():String
		return root + '/assets/scripts';

	public static inline function cache():String
		return root + '/assets/cache.bin';

	public static inline function options():String
		return root + '/options.json';

	public static inline function font():String
		return 'embed/fonts/SpaceMono-Regular.ttf';

	public static inline function vcr():String
		return 'embed/fonts/vcr.ttf';
}
