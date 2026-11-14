#ifndef ZIP7_INC_LZMA_ENC_H
#define ZIP7_INC_LZMA_ENC_H

#include "7zTypes.h"

EXTERN_C_BEGIN

#define LZMA_PROPS_SIZE 5

typedef struct
{
  int level;
  UInt32 dictSize;
  int lc;
  int lp;
  int pb;
  int algo;
  int fb;
  int btMode;
  int numHashBytes;
  unsigned numHashOutBits;
  UInt32 mc;
  unsigned writeEndMark;
  int numThreads;

  Int32 affinityGroup;

  UInt64 reduceSize;

  UInt64 affinity;
  UInt64 affinityInGroup;
} CLzmaEncProps;

void LzmaEncProps_Init(CLzmaEncProps *p);
void LzmaEncProps_Normalize(CLzmaEncProps *p);
UInt32 LzmaEncProps_GetDictSize(const CLzmaEncProps *props2);

typedef struct CLzmaEnc CLzmaEnc;
typedef CLzmaEnc * CLzmaEncHandle;

CLzmaEncHandle LzmaEnc_Create(ISzAllocPtr alloc);
void LzmaEnc_Destroy(CLzmaEncHandle p, ISzAllocPtr alloc, ISzAllocPtr allocBig);

SRes LzmaEnc_SetProps(CLzmaEncHandle p, const CLzmaEncProps *props);
void LzmaEnc_SetDataSize(CLzmaEncHandle p, UInt64 expectedDataSiize);
SRes LzmaEnc_WriteProperties(CLzmaEncHandle p, Byte *properties, SizeT *size);
unsigned LzmaEnc_IsWriteEndMark(CLzmaEncHandle p);

SRes LzmaEnc_Encode(CLzmaEncHandle p, ISeqOutStreamPtr outStream, ISeqInStreamPtr inStream,
    ICompressProgressPtr progress, ISzAllocPtr alloc, ISzAllocPtr allocBig);
SRes LzmaEnc_MemEncode(CLzmaEncHandle p, Byte *dest, SizeT *destLen, const Byte *src, SizeT srcLen,
    int writeEndMark, ICompressProgressPtr progress, ISzAllocPtr alloc, ISzAllocPtr allocBig);

SRes LzmaEncode(Byte *dest, SizeT *destLen, const Byte *src, SizeT srcLen,
    const CLzmaEncProps *props, Byte *propsEncoded, SizeT *propsSize, int writeEndMark,
    ICompressProgressPtr progress, ISzAllocPtr alloc, ISzAllocPtr allocBig);

EXTERN_C_END

#endif
