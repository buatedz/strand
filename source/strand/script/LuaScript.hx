package strand.script;

import hxluajit.Lua;
import hxluajit.LuaL;
import hxluajit.Types;

typedef LuaState = cpp.RawPointer<Lua_State>;

class LuaScript
{
	public static inline final FUNCTION_STOP:String = '##PSYCHLUA_FUNCTIONSTOP';
	public static inline final FUNCTION_CONTINUE:String = '##PSYCHLUA_FUNCTIONCONTINUE';
	public static inline final FUNCTION_STOP_LUA:String = '##PSYCHLUA_FUNCTIONSTOPLUA';

	static var byId:Map<Int, LuaScript> = new Map();
	static var nextId:Int = 1;

	public var name(default, null):String;
	public var closed(default, null):Bool = false;
	public var lastError:String = null;

	var lua:LuaState = null;
	var id:Int;
	var functions:Map<String, Array<Dynamic>->Dynamic> = new Map();
	var missing:Map<String, Bool> = new Map();

	public function new(name:String)
	{
		this.name = name;
		lua = LuaL.newstate();
		LuaL.openlibs(lua);
		id = nextId++;
		byId.set(id, this);
		Lua.pushinteger(lua, id);
		Lua.setfield(lua, Lua.REGISTRYINDEX, '__strand_script');
		set('Function_Stop', FUNCTION_STOP);
		set('Function_Continue', FUNCTION_CONTINUE);
		set('Function_StopLua', FUNCTION_STOP_LUA);
	}

	public function run(code:String):Bool
	{
		if (lua == null) return false;
		var status:Int = LuaL.loadstring(lua, code);
		if (status == Lua.OK) status = Lua.pcall(lua, 0, 0, 0);
		if (status != Lua.OK) {
			lastError = popError();
			close();
			return false;
		}
		return true;
	}

	public function set(variable:String, value:Dynamic):Void
	{
		if (lua == null) return;
		missing.remove(variable);
		toLua(lua, value);
		Lua.setglobal(lua, variable);
	}

	public function addFunction(name:String, f:Array<Dynamic>->Dynamic):Void
	{
		if (lua == null) return;
		functions.set(name, f);
		missing.remove(name);
		Lua.pushstring(lua, name);
		Lua.pushcclosure(lua, cpp.Callable.fromStaticFunction(handleCallback), 1);
		Lua.setglobal(lua, name);
	}

	public function call(func:String, args:Array<Dynamic>):Dynamic
	{
		if (lua == null || missing.exists(func)) return FUNCTION_CONTINUE;
		Lua.getglobal(lua, func);
		if (Lua.type(lua, -1) != Lua.TFUNCTION) {
			Lua.pop(lua, 1);
			missing.set(func, true);
			return FUNCTION_CONTINUE;
		}
		for (a in args) toLua(lua, a);
		if (Lua.pcall(lua, args.length, 1, 0) != Lua.OK) {
			lastError = func + ': ' + popError();
			trace('Lua error in $name: $lastError');
			return FUNCTION_CONTINUE;
		}
		var result:Dynamic = fromLua(lua, -1);
		Lua.pop(lua, 1);
		if (result == FUNCTION_STOP_LUA) {
			close();
			return FUNCTION_CONTINUE;
		}
		return result == null ? FUNCTION_CONTINUE : result;
	}

	public function close():Void
	{
		closed = true;
		byId.remove(id);
		if (lua != null) {
			Lua.close(lua);
			lua = null;
		}
	}

	function popError():String
	{
		final s:String = Lua.tostring(lua, -1) != null ? (Lua.tostring(lua, -1) : String) : 'unknown error';
		Lua.pop(lua, 1);
		return s;
	}

	static function toLua(l:LuaState, v:Dynamic):Bool
	{
		switch (Type.typeof(v))
		{
			case TInt:
				Lua.pushinteger(l, (v : Int));
			case TFloat:
				Lua.pushnumber(l, (v : Float));
			case TBool:
				Lua.pushboolean(l, v == true ? 1 : 0);
			case TObject:
				final fields:Array<String> = Reflect.fields(v);
				Lua.createtable(l, 0, fields.length);
				for (field in fields) {
					Lua.pushstring(l, field);
					toLua(l, Reflect.field(v, field));
					Lua.settable(l, -3);
				}
			case TClass(String):
				Lua.pushstring(l, (v : String));
			case TClass(Array):
				final a:Array<Dynamic> = v;
				Lua.createtable(l, a.length, 0);
				for (i in 0...a.length) {
					Lua.pushinteger(l, i + 1);
					toLua(l, a[i]);
					Lua.settable(l, -3);
				}
			default:
				Lua.pushnil(l);
				return false;
		}
		return true;
	}

	static function fromLua(l:LuaState, idx:Int):Dynamic
	{
		final t:Int = Lua.type(l, idx);
		if (t == Lua.TNUMBER) return Lua.tonumber(l, idx);
		if (t == Lua.TSTRING) return (Lua.tostring(l, idx) : String);
		if (t == Lua.TBOOLEAN) return Lua.toboolean(l, idx) == 1;
		if (t == Lua.TTABLE) return tableFromLua(l, idx);
		return null;
	}

	static function tableFromLua(l:LuaState, idx:Int):Dynamic
	{
		final at:Int = idx < 0 ? Lua.gettop(l) + idx + 1 : idx;
		var isArray:Bool = true;
		var count:Int = 0;
		Lua.pushnil(l);
		while (Lua.next(l, at) != 0) {
			if (Lua.type(l, -2) != Lua.TNUMBER || Lua.tonumber(l, -2) < 1) isArray = false;
			count++;
			Lua.pop(l, 1);
		}
		if (count == 0) return {};
		if (isArray) {
			final a:Array<Dynamic> = [];
			Lua.pushnil(l);
			while (Lua.next(l, at) != 0) {
				a[Std.int(Lua.tonumber(l, -2)) - 1] = fromLua(l, -1);
				Lua.pop(l, 1);
			}
			return a;
		}
		final o:haxe.DynamicAccess<Dynamic> = {};
		Lua.pushnil(l);
		while (Lua.next(l, at) != 0) {
			o.set(Std.string(fromLua(l, -2)), fromLua(l, -1));
			Lua.pop(l, 1);
		}
		return o;
	}

	static function handleCallback(l:LuaState):Int
	{
		Lua.getfield(l, Lua.REGISTRYINDEX, '__strand_script');
		final id:Int = Lua.type(l, -1) == Lua.TNUMBER ? Std.int(Lua.tonumber(l, -1)) : -1;
		Lua.pop(l, 1);
		final script:LuaScript = byId.get(id);
		final fname:String = (Lua.tostring(l, Lua.upvalueindex(1)) : String);
		final f = script != null ? script.functions.get(fname) : null;
		if (f == null) return 0;
		final args:Array<Dynamic> = [for (i in 0...Lua.gettop(l)) fromLua(l, i + 1)];
		var ret:Dynamic = null;
		var error:String = null;
		try ret = f(args) catch (e:Dynamic) error = fname + ': ' + Std.string(e);
		if (error != null) {
			Lua.pushstring(l, error);
			return Lua.error(l);
		}
		if (ret == null) return 0;
		toLua(l, ret);
		return 1;
	}
}
