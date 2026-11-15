package strand;

import haxe.io.Bytes;

#if cpp
@:cppFileCode('
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cwchar>

static HANDLE strandDiscordPipe = INVALID_HANDLE_VALUE;

static bool strandDiscordConnect()
{
	for (int i = 0; i < 10; i++) {
		wchar_t name[64];
		swprintf(name, 64, L"\\\\\\\\.\\\\pipe\\\\discord-ipc-%d", i);
		HANDLE h = CreateFileW(name, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
		if (h != INVALID_HANDLE_VALUE) {
			strandDiscordPipe = h;
			return true;
		}
	}
	return false;
}

static void strandDiscordClose()
{
	if (strandDiscordPipe != INVALID_HANDLE_VALUE) CloseHandle(strandDiscordPipe);
	strandDiscordPipe = INVALID_HANDLE_VALUE;
}

static bool strandDiscordWrite(Array<unsigned char> data, int len)
{
	if (strandDiscordPipe == INVALID_HANDLE_VALUE) return false;
	unsigned char * volatile pin = (unsigned char *)data->getBase();
	unsigned char *p = (unsigned char *)pin;
	bool ok = true;
	hx::EnterGCFreeZone();
	int done = 0;
	while (done < len) {
		DWORD put = 0;
		if (!WriteFile(strandDiscordPipe, p + done, (DWORD)(len - done), &put, NULL) || put == 0) { ok = false; break; }
		done += (int)put;
	}
	hx::ExitGCFreeZone();
	return ok;
}

static bool strandDiscordRead(Array<unsigned char> data, int len)
{
	if (strandDiscordPipe == INVALID_HANDLE_VALUE) return false;
	unsigned char * volatile pin = (unsigned char *)data->getBase();
	unsigned char *p = (unsigned char *)pin;
	bool ok = true;
	hx::EnterGCFreeZone();
	int done = 0;
	while (done < len) {
		DWORD got = 0;
		if (!ReadFile(strandDiscordPipe, p + done, (DWORD)(len - done), &got, NULL) || got == 0) { ok = false; break; }
		done += (int)got;
	}
	hx::ExitGCFreeZone();
	return ok;
}
')
#end
class Discord
{
	public static inline final CLIENT_ID:String = '1571213498392776824';
	static inline final IMAGE:String = 'icon';
	static inline final RETRY_SECONDS:Float = 10;

	static var lock:sys.thread.Mutex = new sys.thread.Mutex();
	static var wake:sys.thread.Lock = new sys.thread.Lock();
	static var worker:sys.thread.Thread = null;
	static var enabled:Bool = false;
	static var wanted:Dynamic = null;
	static var version:Int = 0;
	static var nonce:Int = 0;

	public static function setEnabled(on:Bool):Void
	{
		#if cpp
		if (CLIENT_ID == '') return;
		lock.acquire();
		enabled = on;
		version++;
		lock.release();
		if (on && worker == null) worker = sys.thread.Thread.create(run);
		wake.release();
		#end
	}

	public static function menus():Void
		show({details: 'In the Menus'});

	public static function loading(song:String):Void
		show({details: 'Loading a song', state: song});

	public static function playing(song:String, positionMs:Float, lengthMs:Float):Void
	{
		final start:Float = Date.now().getTime() - Math.max(0, positionMs);
		show({details: 'Playing a song', state: song, timestamps: {start: Std.int(start / 1000), end: Std.int((start + lengthMs) / 1000)}});
	}

	static function show(activity:Dynamic):Void
	{
		activity.assets = {large_image: IMAGE, large_text: 'Strand'};
		lock.acquire();
		wanted = activity;
		version++;
		lock.release();
		wake.release();
	}

	#if cpp
	static function run():Void
	{
		var connected:Bool = false;
		var sent:Int = -1;
		while (true) {
			lock.acquire();
			final on:Bool = enabled;
			final v:Int = version;
			final activity:Dynamic = wanted;
			lock.release();

			if (!on) {
				if (connected) {
					setActivity(null);
					untyped __cpp__('strandDiscordClose()');
					connected = false;
				}
				sent = -1;
				wake.wait();
				continue;
			}
			if (!connected) {
				connected = connect();
				sent = -1;
				if (!connected) {
					wake.wait(RETRY_SECONDS);
					continue;
				}
			}
			if (sent != v) {
				if (setActivity(activity)) sent = v;
				else {
					untyped __cpp__('strandDiscordClose()');
					connected = false;
					continue;
				}
			}
			wake.wait();
		}
	}

	static function connect():Bool
	{
		final opened:Bool = untyped __cpp__('strandDiscordConnect()');
		if (!opened) return false;
		if (send(0, {v: 1, client_id: CLIENT_ID}) && receive()) return true;
		untyped __cpp__('strandDiscordClose()');
		return false;
	}

	static function setActivity(activity:Dynamic):Bool
	{
		final pid:Int = untyped __cpp__('(int)GetCurrentProcessId()');
		return send(1, {cmd: 'SET_ACTIVITY', args: {pid: pid, activity: activity}, nonce: Std.string(++nonce)}) && receive();
	}

	static function send(op:Int, payload:Dynamic):Bool
	{
		final json:Bytes = Bytes.ofString(haxe.Json.stringify(payload));
		final frame:Bytes = Bytes.alloc(8 + json.length);
		frame.setInt32(0, op);
		frame.setInt32(4, json.length);
		frame.blit(8, json, 0, json.length);
		return untyped __cpp__('strandDiscordWrite({0}, {1})', frame.getData(), frame.length);
	}

	static function receive():Bool
	{
		final head:Bytes = Bytes.alloc(8);
		final gotHead:Bool = untyped __cpp__('strandDiscordRead({0}, 8)', head.getData());
		if (!gotHead) return false;
		final op:Int = head.getInt32(0);
		final len:Int = head.getInt32(4);
		if (len < 0 || len > 1 << 20) return false;
		if (len > 0) {
			final body:Bytes = Bytes.alloc(len);
			final gotBody:Bool = untyped __cpp__('strandDiscordRead({0}, {1})', body.getData(), len);
			if (!gotBody) return false;
		}
		return op != 2;
	}
	#end
}
