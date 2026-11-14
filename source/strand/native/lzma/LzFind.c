#include "Precomp.h"

#include <string.h>

#include "CpuArch.h"
#include "LzFind.h"
#include "LzHash.h"

#define kBlockMoveAlign       (1 << 7)
#define kBlockSizeAlign       (1 << 16)
#define kBlockSizeReserveMin  (1 << 24)

#define kEmptyHashValue 0

#define kMaxValForNormalize ((UInt32)0)

#define GET_AVAIL_BYTES(p) \
  Inline_MatchFinder_GetNumAvailableBytes(p)

#define kFix5HashSize kFix4HashSize

#define HASH2_CALC hv = GetUi16(cur);

#define HASH3_CALC { \
  UInt32 temp = p->crc[cur[0]] ^ cur[1]; \
  h2 = temp & (kHash2Size - 1); \
  hv = (temp ^ ((UInt32)cur[2] << 8)) & p->hashMask; }

#define HASH4_CALC { \
  UInt32 temp = p->crc[cur[0]] ^ cur[1]; \
  h2 = temp & (kHash2Size - 1); \
  temp ^= ((UInt32)cur[2] << 8); \
  h3 = temp & (kHash3Size - 1); \
  hv = (temp ^ (p->crc[cur[3]] << kLzHash_CrcShift_1)) & p->hashMask; }

#define HASH5_CALC { \
  UInt32 temp = p->crc[cur[0]] ^ cur[1]; \
  h2 = temp & (kHash2Size - 1); \
  temp ^= ((UInt32)cur[2] << 8); \
  h3 = temp & (kHash3Size - 1); \
  temp ^= (p->crc[cur[3]] << kLzHash_CrcShift_1); \
      \
  hv = (temp ^ (p->crc[cur[4]] << kLzHash_CrcShift_2)) & p->hashMask; }

#define HASH_ZIP_CALC hv = ((cur[2] | ((UInt32)cur[0] << 8)) ^ p->crc[cur[1]]) & 0xFFFF;

static void LzInWindow_Free(CMatchFinder *p, ISzAllocPtr alloc)
{

  {
    ISzAlloc_Free(alloc, p->bufBase);
    p->bufBase = NULL;
  }
}

static int LzInWindow_Create2(CMatchFinder *p, UInt32 blockSize, ISzAllocPtr alloc)
{
  if (blockSize == 0)
    return 0;
  if (!p->bufBase || p->blockSize != blockSize)
  {

    LzInWindow_Free(p, alloc);
    p->blockSize = blockSize;

    p->bufBase = (Byte *)ISzAlloc_Alloc(alloc, blockSize);

  }
  return (p->bufBase != NULL);
}

static const Byte *MatchFinder_GetPointerToCurrentPos(void *p)
{
  return ((CMatchFinder *)p)->buffer;
}

static UInt32 MatchFinder_GetNumAvailableBytes(void *p)
{
  return GET_AVAIL_BYTES((CMatchFinder *)p);
}

Z7_NO_INLINE
static void MatchFinder_ReadBlock(CMatchFinder *p)
{
  if (p->streamEndWasReached || p->result != SZ_OK)
    return;

  if (p->directInput)
  {
    UInt32 curSize = 0xFFFFFFFF - GET_AVAIL_BYTES(p);
    if (curSize > p->directInputRem)
      curSize = (UInt32)p->directInputRem;
    p->streamPos += curSize;
    p->directInputRem -= curSize;
    if (p->directInputRem == 0)
      p->streamEndWasReached = 1;
    return;
  }

  for (;;)
  {
    const Byte *dest = p->buffer + GET_AVAIL_BYTES(p);
    size_t size = (size_t)(p->bufBase + p->blockSize - dest);
    if (size == 0)
    {

      return;
    }

    p->result = ISeqInStream_Read(p->stream,
        p->bufBase + (dest - p->bufBase), &size);
    if (p->result != SZ_OK)
      return;
    if (size == 0)
    {
      p->streamEndWasReached = 1;
      return;
    }
    p->streamPos += (UInt32)size;
    if (GET_AVAIL_BYTES(p) > p->keepSizeAfter)
      return;

  }

}

Z7_NO_INLINE
void MatchFinder_MoveBlock(CMatchFinder *p)
{
  const size_t offset = (size_t)(p->buffer - p->bufBase) - p->keepSizeBefore;
  const size_t keepBefore = (offset & (kBlockMoveAlign - 1)) + p->keepSizeBefore;
  p->buffer = p->bufBase + keepBefore;
  memmove(p->bufBase,
      p->bufBase + (offset & ~((size_t)kBlockMoveAlign - 1)),
      keepBefore + (size_t)GET_AVAIL_BYTES(p));
}

int MatchFinder_NeedMove(CMatchFinder *p)
{
  if (p->directInput)
    return 0;
  if (p->streamEndWasReached || p->result != SZ_OK)
    return 0;
  return ((size_t)(p->bufBase + p->blockSize - p->buffer) <= p->keepSizeAfter);
}

void MatchFinder_ReadIfRequired(CMatchFinder *p)
{
  if (p->keepSizeAfter >= GET_AVAIL_BYTES(p))
    MatchFinder_ReadBlock(p);
}

static void MatchFinder_SetDefaultSettings(CMatchFinder *p)
{
  p->cutValue = 32;
  p->btMode = 1;
  p->numHashBytes = 4;
  p->numHashBytes_Min = 2;
  p->numHashOutBits = 0;
  p->bigHash = 0;
}

#define kCrcPoly 0xEDB88320

void MatchFinder_Construct(CMatchFinder *p)
{
  unsigned i;
  p->buffer = NULL;
  p->bufBase = NULL;
  p->directInput = 0;
  p->stream = NULL;
  p->hash = NULL;
  p->expectedDataSize = (UInt64)(Int64)-1;
  MatchFinder_SetDefaultSettings(p);

  for (i = 0; i < 256; i++)
  {
    UInt32 r = (UInt32)i;
    unsigned j;
    for (j = 0; j < 8; j++)
      r = (r >> 1) ^ (kCrcPoly & ((UInt32)0 - (r & 1)));
    p->crc[i] = r;
  }
}

#undef kCrcPoly

static void MatchFinder_FreeThisClassMemory(CMatchFinder *p, ISzAllocPtr alloc)
{
  ISzAlloc_Free(alloc, p->hash);
  p->hash = NULL;
}

void MatchFinder_Free(CMatchFinder *p, ISzAllocPtr alloc)
{
  MatchFinder_FreeThisClassMemory(p, alloc);
  LzInWindow_Free(p, alloc);
}

static CLzRef* AllocRefs(size_t num, ISzAllocPtr alloc)
{
  const size_t sizeInBytes = (size_t)num * sizeof(CLzRef);
  if (sizeInBytes / sizeof(CLzRef) != num)
    return NULL;
  return (CLzRef *)ISzAlloc_Alloc(alloc, sizeInBytes);
}

#if (kBlockSizeReserveMin < kBlockSizeAlign * 2)
  #error Stop_Compiling_Bad_Reserve
#endif

static UInt32 GetBlockSize(CMatchFinder *p, UInt32 historySize)
{
  UInt32 blockSize = (p->keepSizeBefore + p->keepSizeAfter);

  if (p->keepSizeBefore < historySize || blockSize < p->keepSizeBefore)
    return 0;

  {
    const UInt32 kBlockSizeMax = (UInt32)0 - (UInt32)kBlockSizeAlign;
    const UInt32 rem = kBlockSizeMax - blockSize;
    const UInt32 reserve = (blockSize >> (blockSize < ((UInt32)1 << 30) ? 1 : 2))
        + (1 << 12) + kBlockMoveAlign + kBlockSizeAlign;
    if (blockSize >= kBlockSizeMax
        || rem < kBlockSizeReserveMin)
      return 0;
    if (reserve >= rem)
      blockSize = kBlockSizeMax;
    else
    {
      blockSize += reserve;
      blockSize &= ~(UInt32)(kBlockSizeAlign - 1);
    }
  }

  return blockSize;
}

static UInt32 MatchFinder_GetHashMask2(CMatchFinder *p, UInt32 hs)
{
  if (p->numHashBytes == 2)
    return (1 << 16) - 1;
  if (hs != 0)
    hs--;
  hs |= (hs >> 1);
  hs |= (hs >> 2);
  hs |= (hs >> 4);
  hs |= (hs >> 8);

  if (hs >= (1 << 24))
  {
    if (p->numHashBytes == 3)
      hs = (1 << 24) - 1;

  }

  hs |= (1 << 16) - 1;

  if (p->numHashBytes >= 5)
    hs |= (256 << kLzHash_CrcShift_2) - 1;
  return hs;
}

static UInt32 MatchFinder_GetHashMask(CMatchFinder *p, UInt32 hs)
{
  if (p->numHashBytes == 2)
    return (1 << 16) - 1;
  if (hs != 0)
    hs--;
  hs |= (hs >> 1);
  hs |= (hs >> 2);
  hs |= (hs >> 4);
  hs |= (hs >> 8);

  hs >>= 1;
  if (hs >= (1 << 24))
  {
    if (p->numHashBytes == 3)
      hs = (1 << 24) - 1;
    else
      hs >>= 1;

  }

  hs |= (1 << 16) - 1;

  if (p->numHashBytes >= 5)
    hs |= (256 << kLzHash_CrcShift_2) - 1;
  return hs;
}

int MatchFinder_Create(CMatchFinder *p, UInt32 historySize,
    UInt32 keepAddBufferBefore, UInt32 matchMaxLen, UInt32 keepAddBufferAfter,
    ISzAllocPtr alloc)
{

  p->keepSizeBefore = historySize + keepAddBufferBefore + 1;

  keepAddBufferAfter += matchMaxLen;

  if (keepAddBufferAfter < p->numHashBytes)
    keepAddBufferAfter = p->numHashBytes;

  p->keepSizeAfter = keepAddBufferAfter;

  if (p->directInput)
    p->blockSize = 0;
  if (p->directInput || LzInWindow_Create2(p, GetBlockSize(p, historySize), alloc))
  {
    size_t hashSizeSum;
    {
      UInt32 hs;
      UInt32 hsCur;

      if (p->numHashOutBits != 0)
      {
        unsigned numBits = p->numHashOutBits;
        const unsigned nbMax =
            (p->numHashBytes == 2 ? 16 :
            (p->numHashBytes == 3 ? 24 : 32));
        if (numBits >= nbMax)
          numBits = nbMax;
        if (numBits >= 32)
          hs = (UInt32)0 - 1;
        else
          hs = ((UInt32)1 << numBits) - 1;

        hs |= (1 << 16) - 1;
        if (p->numHashBytes >= 5)
          hs |= (256 << kLzHash_CrcShift_2) - 1;
        {
          const UInt32 hs2 = MatchFinder_GetHashMask2(p, historySize);
          if (hs >= hs2)
            hs = hs2;
        }
        hsCur = hs;
        if (p->expectedDataSize < historySize)
        {
          const UInt32 hs2 = MatchFinder_GetHashMask2(p, (UInt32)p->expectedDataSize);
          if (hsCur >= hs2)
            hsCur = hs2;
        }
      }
      else
      {
        hs = MatchFinder_GetHashMask(p, historySize);
        hsCur = hs;
        if (p->expectedDataSize < historySize)
        {
          hsCur = MatchFinder_GetHashMask(p, (UInt32)p->expectedDataSize);
          if (hsCur >= hs)
            hsCur = hs;
        }
      }

      p->hashMask = hsCur;

      hashSizeSum = hs;
      hashSizeSum++;
      if (hashSizeSum < hs)
        return 0;
      {
        UInt32 fixedHashSize = 0;
        if (p->numHashBytes > 2 && p->numHashBytes_Min <= 2) fixedHashSize += kHash2Size;
        if (p->numHashBytes > 3 && p->numHashBytes_Min <= 3) fixedHashSize += kHash3Size;

        hashSizeSum += fixedHashSize;
        p->fixedHashSize = fixedHashSize;
      }
    }

    p->matchMaxLen = matchMaxLen;

    {
      size_t newSize;
      size_t numSons;
      const UInt32 newCyclicBufferSize = historySize + 1;
      p->historySize = historySize;
      p->cyclicBufferSize = newCyclicBufferSize;

      numSons = newCyclicBufferSize;
      if (p->btMode)
        numSons <<= 1;
      newSize = hashSizeSum + numSons;

      if (numSons < newCyclicBufferSize || newSize < numSons)
        return 0;

      #define NUM_REFS_ALIGN_MASK 0xF
      newSize = (newSize + NUM_REFS_ALIGN_MASK) & ~(size_t)NUM_REFS_ALIGN_MASK;

      if (p->hash && p->numRefs >= newSize)
        return 1;

      MatchFinder_FreeThisClassMemory(p, alloc);
      p->numRefs = newSize;
      p->hash = AllocRefs(newSize, alloc);

      if (p->hash)
      {
        p->son = p->hash + hashSizeSum;
        return 1;
      }
    }
  }

  MatchFinder_Free(p, alloc);
  return 0;
}

static void MatchFinder_SetLimits(CMatchFinder *p)
{
  UInt32 k;
  UInt32 n = kMaxValForNormalize - p->pos;
  if (n == 0)
    n = (UInt32)(Int32)-1;

  k = p->cyclicBufferSize - p->cyclicBufferPos;
  if (k < n)
    n = k;

  k = GET_AVAIL_BYTES(p);
  {
    const UInt32 ksa = p->keepSizeAfter;
    UInt32 mm = p->matchMaxLen;
    if (k > ksa)
      k -= ksa;
    else if (k >= mm)
    {

      k -= mm;
      k++;

    }
    else
    {
      mm = k;
      if (k != 0)
        k = 1;
    }
    p->lenLimit = mm;
  }
  if (k < n)
    n = k;

  p->posLimit = p->pos + n;
}

void MatchFinder_Init_LowHash(CMatchFinder *p)
{
  size_t i;
  CLzRef *items = p->hash;
  const size_t numItems = p->fixedHashSize;
  for (i = 0; i < numItems; i++)
    items[i] = kEmptyHashValue;
}

void MatchFinder_Init_HighHash(CMatchFinder *p)
{
  size_t i;
  CLzRef *items = p->hash + p->fixedHashSize;
  const size_t numItems = (size_t)p->hashMask + 1;
  for (i = 0; i < numItems; i++)
    items[i] = kEmptyHashValue;
}

void MatchFinder_Init_4(CMatchFinder *p)
{
  if (!p->directInput)
    p->buffer = p->bufBase;
  {

    p->pos =
    p->streamPos =
        1;

  }
  p->result = SZ_OK;
  p->streamEndWasReached = 0;
}

#define CYC_TO_POS_OFFSET 0

void MatchFinder_Init(void *_p)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  MatchFinder_Init_HighHash(p);
  MatchFinder_Init_LowHash(p);
  MatchFinder_Init_4(p);

  MatchFinder_ReadBlock(p);

  p->cyclicBufferPos = (p->pos - CYC_TO_POS_OFFSET);

  MatchFinder_SetLimits(p);
}

#ifdef MY_CPU_X86_OR_AMD64
  #if defined(__clang__) && (__clang_major__ >= 4) \
    || defined(Z7_GCC_VERSION) && (Z7_GCC_VERSION >= 40900)

      #define USE_LZFIND_SATUR_SUB_128
      #define USE_LZFIND_SATUR_SUB_256
      #define LZFIND_ATTRIB_SSE41 __attribute__((__target__("sse4.1")))
      #define LZFIND_ATTRIB_AVX2  __attribute__((__target__("avx2")))
  #elif defined(_MSC_VER)
    #if (_MSC_VER >= 1600)
      #define USE_LZFIND_SATUR_SUB_128
    #endif
    #if (_MSC_VER >= 1900)
      #define USE_LZFIND_SATUR_SUB_256
    #endif
  #endif

#elif defined(MY_CPU_ARM64) \

  #if  defined(Z7_CLANG_VERSION) && (Z7_CLANG_VERSION >= 30800) \
    || defined(__GNUC__) && (__GNUC__ >= 6)
      #define USE_LZFIND_SATUR_SUB_128
    #ifdef MY_CPU_ARM64

    #else
      #define LZFIND_ATTRIB_SSE41 __attribute__((__target__("fpu=neon")))
    #endif

  #elif defined(_MSC_VER)
    #if (_MSC_VER >= 1910)
      #define USE_LZFIND_SATUR_SUB_128
    #endif
  #endif

  #if defined(Z7_MSC_VER_ORIGINAL) && defined(MY_CPU_ARM64)
    #include <arm64_neon.h>
  #else
    #include <arm_neon.h>
  #endif

#endif

#ifdef USE_LZFIND_SATUR_SUB_128

#ifdef Z7_SHOW_HW_STATUS
#include <stdio.h>
#define PRF(x) x
PRF(;)
#else
#define PRF(x)
#endif

#ifdef MY_CPU_ARM_OR_ARM64

#ifdef MY_CPU_ARM64

#endif
typedef uint32x4_t LzFind_v128;
#define SASUB_128_V(v, s) \
  vsubq_u32(vmaxq_u32(v, s), s)

#else

#include <smmintrin.h>

typedef __m128i LzFind_v128;

#define SASUB_128_V(v, s)   \
  _mm_sub_epi32(_mm_max_epu32(v, s), s)

#endif

#define SASUB_128(i) \
  *(      LzFind_v128 *)(      void *)(items + (i) * 4) = SASUB_128_V( \
  *(const LzFind_v128 *)(const void *)(items + (i) * 4), sub2);

Z7_NO_INLINE
static
#ifdef LZFIND_ATTRIB_SSE41
LZFIND_ATTRIB_SSE41
#endif
void
Z7_FASTCALL
LzFind_SaturSub_128(UInt32 subValue, CLzRef *items, const CLzRef *lim)
{
  const LzFind_v128 sub2 =
    #ifdef MY_CPU_ARM_OR_ARM64
      vdupq_n_u32(subValue);
    #else
      _mm_set_epi32((Int32)subValue, (Int32)subValue, (Int32)subValue, (Int32)subValue);
    #endif
  Z7_PRAGMA_OPT_DISABLE_LOOP_UNROLL_VECTORIZE
  do
  {
    SASUB_128(0)  SASUB_128(1)  items += 2 * 4;
    SASUB_128(0)  SASUB_128(1)  items += 2 * 4;
  }
  while (items != lim);
}

#ifdef USE_LZFIND_SATUR_SUB_256

#include <immintrin.h>

#if defined(__clang__)
#include <avxintrin.h>
#include <avx2intrin.h>
#endif

#define SASUB_256(i) \
    *(      __m256i *)(      void *)(items + (i) * 8) = \
   _mm256_sub_epi32(_mm256_max_epu32( \
    *(const __m256i *)(const void *)(items + (i) * 8), sub2), sub2);

Z7_NO_INLINE
static
#ifdef LZFIND_ATTRIB_AVX2
LZFIND_ATTRIB_AVX2
#endif
void
Z7_FASTCALL
LzFind_SaturSub_256(UInt32 subValue, CLzRef *items, const CLzRef *lim)
{
  const __m256i sub2 = _mm256_set_epi32(
      (Int32)subValue, (Int32)subValue, (Int32)subValue, (Int32)subValue,
      (Int32)subValue, (Int32)subValue, (Int32)subValue, (Int32)subValue);
  Z7_PRAGMA_OPT_DISABLE_LOOP_UNROLL_VECTORIZE
  do
  {
    SASUB_256(0)  SASUB_256(1)  items += 2 * 8;
    SASUB_256(0)  SASUB_256(1)  items += 2 * 8;
  }
  while (items != lim);
}
#endif

#ifndef FORCE_LZFIND_SATUR_SUB_128
typedef void (Z7_FASTCALL *LZFIND_SATUR_SUB_CODE_FUNC)(
    UInt32 subValue, CLzRef *items, const CLzRef *lim);
static LZFIND_SATUR_SUB_CODE_FUNC g_LzFind_SaturSub;
#endif

#endif

#define SASUB_32(i)  { UInt32 v = items[i];  if (v < subValue) v = subValue; items[i] = v - subValue; }

#ifdef FORCE_LZFIND_SATUR_SUB_128

#define DEFAULT_SaturSub LzFind_SaturSub_128

#else

#define DEFAULT_SaturSub LzFind_SaturSub_32

Z7_NO_INLINE
static
void
Z7_FASTCALL
LzFind_SaturSub_32(UInt32 subValue, CLzRef *items, const CLzRef *lim)
{
  Z7_PRAGMA_OPT_DISABLE_LOOP_UNROLL_VECTORIZE
  do
  {
    SASUB_32(0)  SASUB_32(1)  items += 2;
    SASUB_32(0)  SASUB_32(1)  items += 2;
    SASUB_32(0)  SASUB_32(1)  items += 2;
    SASUB_32(0)  SASUB_32(1)  items += 2;
  }
  while (items != lim);
}

#endif

Z7_NO_INLINE
void MatchFinder_Normalize3(UInt32 subValue, CLzRef *items, size_t numItems)
{
  #define LZFIND_NORM_ALIGN_BLOCK_SIZE (1 << 7)
  Z7_PRAGMA_OPT_DISABLE_LOOP_UNROLL_VECTORIZE
  for (; numItems != 0 && ((unsigned)(ptrdiff_t)items & (LZFIND_NORM_ALIGN_BLOCK_SIZE - 1)) != 0; numItems--)
  {
    SASUB_32(0)
    items++;
  }
  {
    const size_t k_Align_Mask = (LZFIND_NORM_ALIGN_BLOCK_SIZE / 4 - 1);
    CLzRef *lim = items + (numItems & ~(size_t)k_Align_Mask);
    numItems &= k_Align_Mask;
    if (items != lim)
    {
      #if defined(USE_LZFIND_SATUR_SUB_128) && !defined(FORCE_LZFIND_SATUR_SUB_128)
        if (g_LzFind_SaturSub)
          g_LzFind_SaturSub(subValue, items, lim);
        else
      #endif
          DEFAULT_SaturSub(subValue, items, lim);
    }
    items = lim;
  }
  Z7_PRAGMA_OPT_DISABLE_LOOP_UNROLL_VECTORIZE
  for (; numItems != 0; numItems--)
  {
    SASUB_32(0)
    items++;
  }
}

Z7_NO_INLINE
static void MatchFinder_CheckLimits(CMatchFinder *p)
{
  if (
      p->keepSizeAfter == GET_AVAIL_BYTES(p))
  {

    if (MatchFinder_NeedMove(p))
      MatchFinder_MoveBlock(p);
    MatchFinder_ReadBlock(p);
  }

  if (p->pos == kMaxValForNormalize)
  if (GET_AVAIL_BYTES(p) >= p->numHashBytes)

  {

    const UInt32 subValue = (p->pos - p->historySize - 1)  ;

    MatchFinder_REDUCE_OFFSETS(p, subValue)
    MatchFinder_Normalize3(subValue, p->hash, (size_t)p->hashMask + 1 + p->fixedHashSize);
    {
      size_t numSonRefs = p->cyclicBufferSize;
      if (p->btMode)
        numSonRefs <<= 1;
      MatchFinder_Normalize3(subValue, p->son, numSonRefs);
    }
  }

  if (p->cyclicBufferPos == p->cyclicBufferSize)
    p->cyclicBufferPos = 0;

  MatchFinder_SetLimits(p);
}

Z7_FORCE_INLINE
static UInt32 * Hc_GetMatchesSpec(size_t lenLimit, UInt32 curMatch, UInt32 pos, const Byte *cur, CLzRef *son,
    size_t _cyclicBufferPos, UInt32 _cyclicBufferSize, UInt32 cutValue,
    UInt32 *d, unsigned maxLen)
{

  const Byte *lim = cur + lenLimit;
  son[_cyclicBufferPos] = curMatch;

  do
  {
    UInt32 delta;

    if (curMatch == 0)
      break;

    delta = pos - curMatch;
    if (delta >= _cyclicBufferSize)
      break;
    {
      ptrdiff_t diff;
      curMatch = son[_cyclicBufferPos - delta + (_cyclicBufferPos < delta ? _cyclicBufferSize : 0)];
      diff = (ptrdiff_t)0 - (ptrdiff_t)delta;
      if (cur[maxLen] == cur[(ptrdiff_t)maxLen + diff])
      {
        const Byte *c = cur;
        while (*c == c[diff])
        {
          if (++c == lim)
          {
            d[0] = (UInt32)(lim - cur);
            d[1] = delta - 1;
            return d + 2;
          }
        }
        {
          const unsigned len = (unsigned)(c - cur);
          if (maxLen < len)
          {
            maxLen = len;
            d[0] = (UInt32)len;
            d[1] = delta - 1;
            d += 2;
          }
        }
      }
    }
  }
  while (--cutValue);

  return d;
}

Z7_FORCE_INLINE
UInt32 * GetMatchesSpec1(UInt32 lenLimit, UInt32 curMatch, UInt32 pos, const Byte *cur, CLzRef *son,
    size_t _cyclicBufferPos, UInt32 _cyclicBufferSize, UInt32 cutValue,
    UInt32 *d, UInt32 maxLen)
{
  CLzRef *ptr0 = son + ((size_t)_cyclicBufferPos << 1) + 1;
  CLzRef *ptr1 = son + ((size_t)_cyclicBufferPos << 1);
  unsigned len0 = 0, len1 = 0;

  UInt32 cmCheck;

  cmCheck = (UInt32)(pos - _cyclicBufferSize);
  if ((UInt32)pos < _cyclicBufferSize)
    cmCheck = 0;

  if (cmCheck < curMatch)
  do
  {
    const UInt32 delta = pos - curMatch;
    {
      CLzRef *pair = son + ((size_t)(_cyclicBufferPos - delta + (_cyclicBufferPos < delta ? _cyclicBufferSize : 0)) << 1);
      const Byte *pb = cur - delta;
      unsigned len = (len0 < len1 ? len0 : len1);
      const UInt32 pair0 = pair[0];
      if (pb[len] == cur[len])
      {
        if (++len != lenLimit && pb[len] == cur[len])
          while (++len != lenLimit)
            if (pb[len] != cur[len])
              break;
        if (maxLen < len)
        {
          maxLen = (UInt32)len;
          *d++ = (UInt32)len;
          *d++ = delta - 1;
          if (len == lenLimit)
          {
            *ptr1 = pair0;
            *ptr0 = pair[1];
            return d;
          }
        }
      }
      if (pb[len] < cur[len])
      {
        *ptr1 = curMatch;

        curMatch = pair[1];
        ptr1 = pair + 1;
        len1 = len;
      }
      else
      {
        *ptr0 = curMatch;
        curMatch = pair[0];
        ptr0 = pair;
        len0 = len;
      }
    }
  }
  while(--cutValue && cmCheck < curMatch);

  *ptr0 = *ptr1 = kEmptyHashValue;
  return d;
}

static void SkipMatchesSpec(UInt32 lenLimit, UInt32 curMatch, UInt32 pos, const Byte *cur, CLzRef *son,
    size_t _cyclicBufferPos, UInt32 _cyclicBufferSize, UInt32 cutValue)
{
  CLzRef *ptr0 = son + ((size_t)_cyclicBufferPos << 1) + 1;
  CLzRef *ptr1 = son + ((size_t)_cyclicBufferPos << 1);
  unsigned len0 = 0, len1 = 0;

  UInt32 cmCheck;

  cmCheck = (UInt32)(pos - _cyclicBufferSize);
  if ((UInt32)pos < _cyclicBufferSize)
    cmCheck = 0;

  if (
      cmCheck < curMatch)
  do
  {
    const UInt32 delta = pos - curMatch;
    {
      CLzRef *pair = son + ((size_t)(_cyclicBufferPos - delta + (_cyclicBufferPos < delta ? _cyclicBufferSize : 0)) << 1);
      const Byte *pb = cur - delta;
      unsigned len = (len0 < len1 ? len0 : len1);
      if (pb[len] == cur[len])
      {
        while (++len != lenLimit)
          if (pb[len] != cur[len])
            break;
        {
          if (len == lenLimit)
          {
            *ptr1 = pair[0];
            *ptr0 = pair[1];
            return;
          }
        }
      }
      if (pb[len] < cur[len])
      {
        *ptr1 = curMatch;
        curMatch = pair[1];
        ptr1 = pair + 1;
        len1 = len;
      }
      else
      {
        *ptr0 = curMatch;
        curMatch = pair[0];
        ptr0 = pair;
        len0 = len;
      }
    }
  }
  while(--cutValue && cmCheck < curMatch);

  *ptr0 = *ptr1 = kEmptyHashValue;
  return;
}

#define MOVE_POS \
  p->cyclicBufferPos++; \
  p->buffer++; \
  { const UInt32 pos1 = p->pos + 1; \
    p->pos = pos1; \
    if (pos1 == p->posLimit) MatchFinder_CheckLimits(p); }

#define MOVE_POS_RET MOVE_POS return distances;

Z7_NO_INLINE
static void MatchFinder_MovePos(CMatchFinder *p)
{

  MOVE_POS
}

#define GET_MATCHES_HEADER2(minLen, ret_op) \
  UInt32 hv; const Byte *cur; UInt32 curMatch; \
  UInt32 lenLimit = p->lenLimit; \
  if (lenLimit < minLen) { MatchFinder_MovePos(p);  ret_op; } \
  cur = p->buffer;

#define GET_MATCHES_HEADER(minLen) GET_MATCHES_HEADER2(minLen, return distances)
#define SKIP_HEADER(minLen)  \
  do { GET_MATCHES_HEADER2(minLen, continue)

#define MF_PARAMS(p)  lenLimit, curMatch, p->pos, p->buffer, p->son, \
    p->cyclicBufferPos, p->cyclicBufferSize, p->cutValue

#define SKIP_FOOTER  \
    SkipMatchesSpec(MF_PARAMS(p)); \
    MOVE_POS \
  } while (--num);

#define GET_MATCHES_FOOTER_BASE(_maxLen_, func) \
  distances = func(MF_PARAMS(p), distances, (UInt32)_maxLen_); \
  MOVE_POS_RET

#define GET_MATCHES_FOOTER_BT(_maxLen_) \
  GET_MATCHES_FOOTER_BASE(_maxLen_, GetMatchesSpec1)

#define GET_MATCHES_FOOTER_HC(_maxLen_) \
  GET_MATCHES_FOOTER_BASE(_maxLen_, Hc_GetMatchesSpec)

#define UPDATE_maxLen { \
    const ptrdiff_t diff = (ptrdiff_t)0 - (ptrdiff_t)d2; \
    const Byte *c = cur + maxLen; \
    const Byte *lim = cur + lenLimit; \
    for (; c != lim; c++) if (*(c + diff) != *c) break; \
    maxLen = (unsigned)(c - cur); }

static UInt32* Bt2_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  GET_MATCHES_HEADER(2)
  HASH2_CALC
  curMatch = p->hash[hv];
  p->hash[hv] = p->pos;
  GET_MATCHES_FOOTER_BT(1)
}

UInt32* Bt3Zip_MatchFinder_GetMatches(CMatchFinder *p, UInt32 *distances)
{
  GET_MATCHES_HEADER(3)
  HASH_ZIP_CALC
  curMatch = p->hash[hv];
  p->hash[hv] = p->pos;
  GET_MATCHES_FOOTER_BT(2)
}

#define SET_mmm  \
  mmm = p->cyclicBufferSize; \
  if (pos < mmm) \
    mmm = pos;

static UInt32* Bt3_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  UInt32 mmm;
  UInt32 h2, d2, pos;
  unsigned maxLen;
  UInt32 *hash;
  GET_MATCHES_HEADER(3)

  HASH3_CALC

  hash = p->hash;
  pos = p->pos;

  d2 = pos - hash[h2];

  curMatch = (hash + kFix3HashSize)[hv];

  hash[h2] = pos;
  (hash + kFix3HashSize)[hv] = pos;

  SET_mmm

  maxLen = 2;

  if (d2 < mmm && *(cur - d2) == *cur)
  {
    UPDATE_maxLen
    distances[0] = (UInt32)maxLen;
    distances[1] = d2 - 1;
    distances += 2;
    if (maxLen == lenLimit)
    {
      SkipMatchesSpec(MF_PARAMS(p));
      MOVE_POS_RET
    }
  }

  GET_MATCHES_FOOTER_BT(maxLen)
}

static UInt32* Bt4_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  UInt32 mmm;
  UInt32 h2, h3, d2, d3, pos;
  unsigned maxLen;
  UInt32 *hash;
  GET_MATCHES_HEADER(4)

  HASH4_CALC

  hash = p->hash;
  pos = p->pos;

  d2 = pos - hash                  [h2];
  d3 = pos - (hash + kFix3HashSize)[h3];
  curMatch = (hash + kFix4HashSize)[hv];

  hash                  [h2] = pos;
  (hash + kFix3HashSize)[h3] = pos;
  (hash + kFix4HashSize)[hv] = pos;

  SET_mmm

  maxLen = 3;

  for (;;)
  {
    if (d2 < mmm && *(cur - d2) == *cur)
    {
      distances[0] = 2;
      distances[1] = d2 - 1;
      distances += 2;
      if (*(cur - d2 + 2) == cur[2])
      {

      }
      else if (d3 < mmm && *(cur - d3) == *cur)
      {
        d2 = d3;
        distances[1] = d3 - 1;
        distances += 2;
      }
      else
        break;
    }
    else if (d3 < mmm && *(cur - d3) == *cur)
    {
      d2 = d3;
      distances[1] = d3 - 1;
      distances += 2;
    }
    else
      break;

    UPDATE_maxLen
    distances[-2] = (UInt32)maxLen;
    if (maxLen == lenLimit)
    {
      SkipMatchesSpec(MF_PARAMS(p));
      MOVE_POS_RET
    }
    break;
  }

  GET_MATCHES_FOOTER_BT(maxLen)
}

static UInt32* Bt5_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  UInt32 mmm;
  UInt32 h2, h3, d2, d3, pos;
  unsigned maxLen;
  UInt32 *hash;
  GET_MATCHES_HEADER(5)

  HASH5_CALC

  hash = p->hash;
  pos = p->pos;

  d2 = pos - hash                  [h2];
  d3 = pos - (hash + kFix3HashSize)[h3];

  curMatch = (hash + kFix5HashSize)[hv];

  hash                  [h2] = pos;
  (hash + kFix3HashSize)[h3] = pos;

  (hash + kFix5HashSize)[hv] = pos;

  SET_mmm

  maxLen = 4;

  for (;;)
  {
    if (d2 < mmm && *(cur - d2) == *cur)
    {
      distances[0] = 2;
      distances[1] = d2 - 1;
      distances += 2;
      if (*(cur - d2 + 2) == cur[2])
      {
      }
      else if (d3 < mmm && *(cur - d3) == *cur)
      {
        distances[1] = d3 - 1;
        distances += 2;
        d2 = d3;
      }
      else
        break;
    }
    else if (d3 < mmm && *(cur - d3) == *cur)
    {
      distances[1] = d3 - 1;
      distances += 2;
      d2 = d3;
    }
    else
      break;

    distances[-2] = 3;
    if (*(cur - d2 + 3) != cur[3])
      break;
    UPDATE_maxLen
    distances[-2] = (UInt32)maxLen;
    if (maxLen == lenLimit)
    {
      SkipMatchesSpec(MF_PARAMS(p));
      MOVE_POS_RET
    }
    break;
  }

  GET_MATCHES_FOOTER_BT(maxLen)
}

static UInt32* Hc4_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  UInt32 mmm;
  UInt32 h2, h3, d2, d3, pos;
  unsigned maxLen;
  UInt32 *hash;
  GET_MATCHES_HEADER(4)

  HASH4_CALC

  hash = p->hash;
  pos = p->pos;

  d2 = pos - hash                  [h2];
  d3 = pos - (hash + kFix3HashSize)[h3];
  curMatch = (hash + kFix4HashSize)[hv];

  hash                  [h2] = pos;
  (hash + kFix3HashSize)[h3] = pos;
  (hash + kFix4HashSize)[hv] = pos;

  SET_mmm

  maxLen = 3;

  for (;;)
  {
    if (d2 < mmm && *(cur - d2) == *cur)
    {
      distances[0] = 2;
      distances[1] = d2 - 1;
      distances += 2;
      if (*(cur - d2 + 2) == cur[2])
      {

      }
      else if (d3 < mmm && *(cur - d3) == *cur)
      {
        d2 = d3;
        distances[1] = d3 - 1;
        distances += 2;
      }
      else
        break;
    }
    else if (d3 < mmm && *(cur - d3) == *cur)
    {
      d2 = d3;
      distances[1] = d3 - 1;
      distances += 2;
    }
    else
      break;

    UPDATE_maxLen
    distances[-2] = (UInt32)maxLen;
    if (maxLen == lenLimit)
    {
      p->son[p->cyclicBufferPos] = curMatch;
      MOVE_POS_RET
    }
    break;
  }

  GET_MATCHES_FOOTER_HC(maxLen)
}

static UInt32 * Hc5_MatchFinder_GetMatches(void *_p, UInt32 *distances)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  UInt32 mmm;
  UInt32 h2, h3, d2, d3, pos;
  unsigned maxLen;
  UInt32 *hash;
  GET_MATCHES_HEADER(5)

  HASH5_CALC

  hash = p->hash;
  pos = p->pos;

  d2 = pos - hash                  [h2];
  d3 = pos - (hash + kFix3HashSize)[h3];

  curMatch = (hash + kFix5HashSize)[hv];

  hash                  [h2] = pos;
  (hash + kFix3HashSize)[h3] = pos;

  (hash + kFix5HashSize)[hv] = pos;

  SET_mmm

  maxLen = 4;

  for (;;)
  {
    if (d2 < mmm && *(cur - d2) == *cur)
    {
      distances[0] = 2;
      distances[1] = d2 - 1;
      distances += 2;
      if (*(cur - d2 + 2) == cur[2])
      {
      }
      else if (d3 < mmm && *(cur - d3) == *cur)
      {
        distances[1] = d3 - 1;
        distances += 2;
        d2 = d3;
      }
      else
        break;
    }
    else if (d3 < mmm && *(cur - d3) == *cur)
    {
      distances[1] = d3 - 1;
      distances += 2;
      d2 = d3;
    }
    else
      break;

    distances[-2] = 3;
    if (*(cur - d2 + 3) != cur[3])
      break;
    UPDATE_maxLen
    distances[-2] = (UInt32)maxLen;
    if (maxLen == lenLimit)
    {
      p->son[p->cyclicBufferPos] = curMatch;
      MOVE_POS_RET
    }
    break;
  }

  GET_MATCHES_FOOTER_HC(maxLen)
}

UInt32* Hc3Zip_MatchFinder_GetMatches(CMatchFinder *p, UInt32 *distances)
{
  GET_MATCHES_HEADER(3)
  HASH_ZIP_CALC
  curMatch = p->hash[hv];
  p->hash[hv] = p->pos;
  GET_MATCHES_FOOTER_HC(2)
}

static void Bt2_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  SKIP_HEADER(2)
  {
    HASH2_CALC
    curMatch = p->hash[hv];
    p->hash[hv] = p->pos;
  }
  SKIP_FOOTER
}

void Bt3Zip_MatchFinder_Skip(CMatchFinder *p, UInt32 num)
{
  SKIP_HEADER(3)
  {
    HASH_ZIP_CALC
    curMatch = p->hash[hv];
    p->hash[hv] = p->pos;
  }
  SKIP_FOOTER
}

static void Bt3_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  SKIP_HEADER(3)
  {
    UInt32 h2;
    UInt32 *hash;
    HASH3_CALC
    hash = p->hash;
    curMatch = (hash + kFix3HashSize)[hv];
    hash[h2] =
    (hash + kFix3HashSize)[hv] = p->pos;
  }
  SKIP_FOOTER
}

static void Bt4_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  SKIP_HEADER(4)
  {
    UInt32 h2, h3;
    UInt32 *hash;
    HASH4_CALC
    hash = p->hash;
    curMatch = (hash + kFix4HashSize)[hv];
    hash                  [h2] =
    (hash + kFix3HashSize)[h3] =
    (hash + kFix4HashSize)[hv] = p->pos;
  }
  SKIP_FOOTER
}

static void Bt5_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  SKIP_HEADER(5)
  {
    UInt32 h2, h3;
    UInt32 *hash;
    HASH5_CALC
    hash = p->hash;
    curMatch = (hash + kFix5HashSize)[hv];
    hash                  [h2] =
    (hash + kFix3HashSize)[h3] =

    (hash + kFix5HashSize)[hv] = p->pos;
  }
  SKIP_FOOTER
}

#define HC_SKIP_HEADER(minLen) \
    do { if (p->lenLimit < minLen) { MatchFinder_MovePos(p); num--; continue; } { \
    const Byte *cur; \
    UInt32 *hash; \
    UInt32 *son; \
    UInt32 pos = p->pos; \
    UInt32 num2 = num; \
      \
    { const UInt32 rem = p->posLimit - pos; if (num2 >= rem) num2 = rem; } \
    num -= num2; \
    { const UInt32 cycPos = p->cyclicBufferPos; \
      son = p->son + cycPos; \
      p->cyclicBufferPos = cycPos + num2; } \
    cur = p->buffer; \
    hash = p->hash; \
    do { \
    UInt32 curMatch; \
    UInt32 hv;

#define HC_SKIP_FOOTER \
    cur++;  pos++;  *son++ = curMatch; \
    } while (--num2); \
    p->buffer = cur; \
    p->pos = pos; \
    if (pos == p->posLimit) MatchFinder_CheckLimits(p); \
    }} while(num); \

static void Hc4_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  HC_SKIP_HEADER(4)

    UInt32 h2, h3;
    HASH4_CALC
    curMatch = (hash + kFix4HashSize)[hv];
    hash                  [h2] =
    (hash + kFix3HashSize)[h3] =
    (hash + kFix4HashSize)[hv] = pos;

  HC_SKIP_FOOTER
}

static void Hc5_MatchFinder_Skip(void *_p, UInt32 num)
{
  CMatchFinder *p = (CMatchFinder *)_p;
  HC_SKIP_HEADER(5)

    UInt32 h2, h3;
    HASH5_CALC
    curMatch = (hash + kFix5HashSize)[hv];
    hash                  [h2] =
    (hash + kFix3HashSize)[h3] =

    (hash + kFix5HashSize)[hv] = pos;

  HC_SKIP_FOOTER
}

void Hc3Zip_MatchFinder_Skip(CMatchFinder *p, UInt32 num)
{
  HC_SKIP_HEADER(3)

    HASH_ZIP_CALC
    curMatch = hash[hv];
    hash[hv] = pos;

  HC_SKIP_FOOTER
}

void MatchFinder_CreateVTable(CMatchFinder *p, IMatchFinder2 *vTable)
{
  vTable->Init = MatchFinder_Init;
  vTable->GetNumAvailableBytes = MatchFinder_GetNumAvailableBytes;
  vTable->GetPointerToCurrentPos = MatchFinder_GetPointerToCurrentPos;
  if (!p->btMode)
  {
    if (p->numHashBytes <= 4)
    {
      vTable->GetMatches = Hc4_MatchFinder_GetMatches;
      vTable->Skip = Hc4_MatchFinder_Skip;
    }
    else
    {
      vTable->GetMatches = Hc5_MatchFinder_GetMatches;
      vTable->Skip = Hc5_MatchFinder_Skip;
    }
  }
  else if (p->numHashBytes == 2)
  {
    vTable->GetMatches = Bt2_MatchFinder_GetMatches;
    vTable->Skip = Bt2_MatchFinder_Skip;
  }
  else if (p->numHashBytes == 3)
  {
    vTable->GetMatches = Bt3_MatchFinder_GetMatches;
    vTable->Skip = Bt3_MatchFinder_Skip;
  }
  else if (p->numHashBytes == 4)
  {
    vTable->GetMatches = Bt4_MatchFinder_GetMatches;
    vTable->Skip = Bt4_MatchFinder_Skip;
  }
  else
  {
    vTable->GetMatches = Bt5_MatchFinder_GetMatches;
    vTable->Skip = Bt5_MatchFinder_Skip;
  }
}

void LzFindPrepare(void)
{
  #ifndef FORCE_LZFIND_SATUR_SUB_128
  #ifdef USE_LZFIND_SATUR_SUB_128
  LZFIND_SATUR_SUB_CODE_FUNC f = NULL;
  #ifdef MY_CPU_ARM_OR_ARM64
  {
    if (CPU_IsSupported_NEON())
    {

      PRF(printf("\n=== LzFind NEON\n"));
      f = LzFind_SaturSub_128;
    }

  }
  #else
  if (CPU_IsSupported_SSE41())
  {

    PRF(printf("\n=== LzFind SSE41\n"));
    f = LzFind_SaturSub_128;

    #ifdef USE_LZFIND_SATUR_SUB_256
    if (CPU_IsSupported_AVX2())
    {

      PRF(printf("\n=== LzFind AVX2\n"));
      f = LzFind_SaturSub_256;
    }
    #endif
  }
  #endif
  g_LzFind_SaturSub = f;
  #endif
  #endif
}

#undef MOVE_POS
#undef MOVE_POS_RET
#undef PRF
