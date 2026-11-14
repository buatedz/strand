#include "Precomp.h"

#include <stdlib.h>

#include "LzmaEnc.h"
#include "LzmaDec.h"
#include "strand_lzma.h"

static void *StrandAlloc(ISzAllocPtr p, size_t size)
{
  (void)p;
  return size == 0 ? NULL : malloc(size);
}

static void StrandFree(ISzAllocPtr p, void *address)
{
  (void)p;
  free(address);
}

static const ISzAlloc strandAlloc = { StrandAlloc, StrandFree };

int strand_lzma_encode(const unsigned char *src, size_t srcLen, unsigned char *dst, size_t *dstLen, unsigned char *props,
  int level, unsigned int dictSize, int lc, int lp, int pb)
{
  CLzmaEncProps p;
  SizeT outLen = *dstLen;
  SizeT propsSize = LZMA_PROPS_SIZE;
  SRes res;
  LzmaEncProps_Init(&p);
  p.level = level;
  if (dictSize != 0) p.dictSize = dictSize;
  if (lc >= 0) p.lc = lc;
  if (lp >= 0) p.lp = lp;
  if (pb >= 0) p.pb = pb;
  if (level >= 9) { p.fb = 273; p.algo = 1; p.btMode = 1; }
  p.numThreads = 1;
  p.reduceSize = srcLen;
  res = LzmaEncode(dst, &outLen, src, srcLen, &p, props, &propsSize, 0, NULL, &strandAlloc, &strandAlloc);
  *dstLen = outLen;
  if (res != SZ_OK) return (int)res;
  if (propsSize != LZMA_PROPS_SIZE) return -1;
  return 0;
}

int strand_lzma_decode(unsigned char *dst, size_t dstLen, const unsigned char *src, size_t srcLen, const unsigned char *props)
{
  SizeT outLen = dstLen;
  SizeT inLen = srcLen;
  ELzmaStatus status;
  SRes res = LzmaDecode(dst, &outLen, src, &inLen, props, LZMA_PROPS_SIZE, LZMA_FINISH_ANY, &status, &strandAlloc);
  if (res != SZ_OK) return (int)res;
  if (outLen != dstLen) return -1;
  return 0;
}
