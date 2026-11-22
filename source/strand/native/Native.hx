package strand.native;

import haxe.io.Bytes;

#if cpp
@:build(strand.native.NativeMacro.build())
@:cppFileCode('
#include <cstdio>
#include <cstring>
#include <mutex>
#include "strand_lzma.h"
#include "zstd.h"

static std::mutex strandFileLock;
static FILE *strandFiles[1024];

static int strandFileOpen(::String path, int mode)
{
	FILE *f = 0;
#ifdef _WIN32
	const wchar_t *m = mode == 0 ? L"rb" : (mode == 1 ? L"wb" : L"r+b");
	hx::strbuf buf;
	const wchar_t *name = path.wchar_str(&buf);
	hx::EnterGCFreeZone();
	f = _wfopen(name, m);
	hx::ExitGCFreeZone();
#else
	const char *m = mode == 0 ? "rb" : (mode == 1 ? "wb" : "r+b");
	hx::strbuf buf;
	const char *name = path.utf8_str(&buf);
	hx::EnterGCFreeZone();
	f = fopen(name, m);
	hx::ExitGCFreeZone();
#endif
	if (!f) return -1;
	std::lock_guard<std::mutex> lock(strandFileLock);
	for (int i = 0; i < 1024; i++)
	{
		if (!strandFiles[i])
		{
			strandFiles[i] = f;
			return i;
		}
	}
	fclose(f);
	return -2;
}

static FILE *strandFileOf(int id)
{
	if (id < 0 || id >= 1024) return 0;
	std::lock_guard<std::mutex> lock(strandFileLock);
	return strandFiles[id];
}

static void strandFileClose(int id)
{
	FILE *f = 0;
	{
		std::lock_guard<std::mutex> lock(strandFileLock);
		if (id < 0 || id >= 1024) return;
		f = strandFiles[id];
		strandFiles[id] = 0;
	}
	if (f)
	{
		hx::EnterGCFreeZone();
		fclose(f);
		hx::ExitGCFreeZone();
	}
}

static int strandFileRead(int id, Array<unsigned char> data, int pos, int len)
{
	FILE *f = strandFileOf(id);
	if (!f || len <= 0) return 0;
	unsigned char * volatile pin = (unsigned char *)data->getBase();
	unsigned char *p = (unsigned char *)pin + pos;
	hx::EnterGCFreeZone();
	size_t got = fread(p, 1, (size_t)len, f);
	hx::ExitGCFreeZone();
	return (int)got;
}

static int strandFileWrite(int id, Array<unsigned char> data, int pos, int len)
{
	FILE *f = strandFileOf(id);
	if (!f || len <= 0) return 0;
	unsigned char * volatile pin = (unsigned char *)data->getBase();
	unsigned char *p = (unsigned char *)pin + pos;
	hx::EnterGCFreeZone();
	size_t put = fwrite(p, 1, (size_t)len, f);
	hx::ExitGCFreeZone();
	return (int)put;
}

static bool strandFileSeek(int id, double offset, int whence)
{
	FILE *f = strandFileOf(id);
	if (!f) return false;
	int w = whence == 2 ? SEEK_END : SEEK_SET;
#ifdef _WIN32
	return _fseeki64(f, (long long)offset, w) == 0;
#else
	return fseeko(f, (off_t)offset, w) == 0;
#endif
}

static double strandFileTell(int id)
{
	FILE *f = strandFileOf(id);
	if (!f) return -1;
#ifdef _WIN32
	return (double)_ftelli64(f);
#else
	return (double)ftello(f);
#endif
}

static bool strandFileFlush(int id)
{
	FILE *f = strandFileOf(id);
	if (!f) return false;
	hx::EnterGCFreeZone();
	int r = fflush(f);
	hx::ExitGCFreeZone();
	return r == 0;
}

static int strandLzmaEncode(Array<unsigned char> src, int srcPos, int srcLen, Array<unsigned char> dst, int dstPos, int dstRoom, Array<unsigned char> props, int level, int dict, int lc, int lp, int pb)
{
	unsigned char * volatile pinSrc = (unsigned char *)src->getBase();
	unsigned char * volatile pinDst = (unsigned char *)dst->getBase();
	unsigned char * volatile pinProps = (unsigned char *)props->getBase();
	const unsigned char *s = (const unsigned char *)pinSrc + srcPos;
	unsigned char *d = (unsigned char *)pinDst + dstPos;
	unsigned char *pr = (unsigned char *)pinProps;
	size_t outLen = (size_t)dstRoom;
	hx::EnterGCFreeZone();
	int r = strand_lzma_encode(s, (size_t)srcLen, d, &outLen, pr, level, (unsigned int)dict, lc, lp, pb);
	hx::ExitGCFreeZone();
	if (r != 0) return -1;
	return (int)outLen;
}

static bool strandLzmaDecode(Array<unsigned char> src, int srcPos, int srcLen, Array<unsigned char> dst, int dstPos, int dstLen, Array<unsigned char> props, int propsPos)
{
	unsigned char * volatile pinSrc = (unsigned char *)src->getBase();
	unsigned char * volatile pinDst = (unsigned char *)dst->getBase();
	unsigned char * volatile pinProps = (unsigned char *)props->getBase();
	const unsigned char *s = (const unsigned char *)pinSrc + srcPos;
	unsigned char *d = (unsigned char *)pinDst + dstPos;
	const unsigned char *pr = (const unsigned char *)pinProps + propsPos;
	hx::EnterGCFreeZone();
	int r = strand_lzma_decode(d, (size_t)dstLen, s, (size_t)srcLen, pr);
	hx::ExitGCFreeZone();
	return r == 0;
}

static bool strandZstdDecode(Array<unsigned char> src, int srcPos, int srcLen, Array<unsigned char> dst, int dstPos, int dstLen)
{
	static thread_local ZSTD_DCtx *ctx = 0;
	if (!ctx) ctx = ZSTD_createDCtx();
	if (!ctx) return false;
	unsigned char * volatile pinSrc = (unsigned char *)src->getBase();
	unsigned char * volatile pinDst = (unsigned char *)dst->getBase();
	const unsigned char *s = (const unsigned char *)pinSrc + srcPos;
	unsigned char *d = (unsigned char *)pinDst + dstPos;
	hx::EnterGCFreeZone();
	size_t r = ZSTD_decompressDCtx(ctx, d, (size_t)dstLen, s, (size_t)srcLen);
	hx::ExitGCFreeZone();
	return !ZSTD_isError(r) && r == (size_t)dstLen;
}
')
#end
class Native
{
	public static inline final READ:Int = 0;
	public static inline final WRITE:Int = 1;
	public static inline final UPDATE:Int = 2;

	public static function open(path:String, mode:Int):Int
	{
		#if cpp
		return untyped __cpp__('strandFileOpen({0}, {1})', path, mode);
		#else
		throw 'Strand needs the cpp target';
		#end
	}

	public static function close(id:Int):Void
	{
		#if cpp
		untyped __cpp__('strandFileClose({0})', id);
		#end
	}

	public static function read(id:Int, bytes:Bytes, pos:Int, len:Int):Int
	{
		if (len <= 0) return 0;
		if (pos < 0 || pos + len > bytes.length) throw 'Native.read out of range';
		#if cpp
		return untyped __cpp__('strandFileRead({0}, {1}, {2}, {3})', id, bytes.getData(), pos, len);
		#else
		return 0;
		#end
	}

	public static function readFully(id:Int, bytes:Bytes, pos:Int, len:Int):Void
	{
		var got:Int = 0;
		while (got < len) {
			final n:Int = read(id, bytes, pos + got, len - got);
			if (n <= 0) throw 'The file ended early';
			got += n;
		}
	}

	public static function write(id:Int, bytes:Bytes, pos:Int, len:Int):Void
	{
		if (len <= 0) return;
		if (pos < 0 || pos + len > bytes.length) throw 'Native.write out of range';
		#if cpp
		final put:Int = untyped __cpp__('strandFileWrite({0}, {1}, {2}, {3})', id, bytes.getData(), pos, len);
		if (put != len) throw 'Could not write the file (disk full?)';
		#end
	}

	public static function seek(id:Int, offset:Float):Void
	{
		#if cpp
		final ok:Bool = untyped __cpp__('strandFileSeek({0}, {1}, 0)', id, offset);
		if (!ok) throw 'Could not move inside the file';
		#end
	}

	public static function seekEnd(id:Int):Float
	{
		#if cpp
		final ok:Bool = untyped __cpp__('strandFileSeek({0}, 0, 2)', id);
		if (!ok) throw 'Could not move inside the file';
		#end
		return tell(id);
	}

	public static function tell(id:Int):Float
	{
		#if cpp
		return untyped __cpp__('strandFileTell({0})', id);
		#else
		return -1;
		#end
	}

	public static function flush(id:Int):Void
	{
		#if cpp
		untyped __cpp__('strandFileFlush({0})', id);
		#end
	}

	public static function readAt(id:Int, offset:Float, bytes:Bytes, pos:Int, len:Int):Void
	{
		if (len <= 0) return;
		seek(id, offset);
		readFully(id, bytes, pos, len);
	}

	public static function lzmaEncode(src:Bytes, srcPos:Int, srcLen:Int, dst:Bytes, dstPos:Int, props:Bytes, level:Int, dict:Int, lc:Int = -1, lp:Int = -1,
			pb:Int = -1):Int
	{
		#if cpp
		return untyped __cpp__('strandLzmaEncode({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8}, {9}, {10}, {11})', src.getData(), srcPos, srcLen, dst.getData(), dstPos,
			dst.length - dstPos, props.getData(), level, dict, lc, lp, pb);
		#else
		return -1;
		#end
	}

	public static function lzmaDecode(src:Bytes, srcPos:Int, srcLen:Int, dst:Bytes, dstPos:Int, dstLen:Int, props:Bytes, propsPos:Int):Bool
	{
		#if cpp
		return untyped __cpp__('strandLzmaDecode({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7})', src.getData(), srcPos, srcLen, dst.getData(), dstPos, dstLen,
			props.getData(), propsPos);
		#else
		return false;
		#end
	}

	public static function zstdDecode(src:Bytes, srcPos:Int, srcLen:Int, dst:Bytes, dstPos:Int, dstLen:Int):Bool
	{
		if (srcPos < 0 || srcPos + srcLen > src.length || dstPos < 0 || dstPos + dstLen > dst.length) return false;
		#if cpp
		return untyped __cpp__('strandZstdDecode({0}, {1}, {2}, {3}, {4}, {5})', src.getData(), srcPos, srcLen, dst.getData(), dstPos, dstLen);
		#else
		return false;
		#end
	}

	public static function fileSize(path:String):Float
	{
		final f:Int = open(path, READ);
		if (f < 0) return -1;
		final n:Float = seekEnd(f);
		close(f);
		return n;
	}
}
