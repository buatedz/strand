#ifndef ZIP7_INC_LZ_HASH_H
#define ZIP7_INC_LZ_HASH_H

#define kHash2Size (1 << 10)
#define kHash3Size (1 << 16)

#define kFix3HashSize (kHash2Size)
#define kFix4HashSize (kHash2Size + kHash3Size)

#define kLzHash_CrcShift_1 5
#define kLzHash_CrcShift_2 10

#endif
