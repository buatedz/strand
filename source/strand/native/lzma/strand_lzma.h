#ifndef STRAND_LZMA_H
#define STRAND_LZMA_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Plain LZMA (the 7-Zip SDK, public domain). props is 5 bytes. lc/lp/pb < 0 keeps the SDK default. */
int strand_lzma_encode(const unsigned char *src, size_t srcLen, unsigned char *dst, size_t *dstLen, unsigned char *props,
	int level, unsigned int dictSize, int lc, int lp, int pb);
int strand_lzma_decode(unsigned char *dst, size_t dstLen, const unsigned char *src, size_t srcLen, const unsigned char *props);

#ifdef __cplusplus
}
#endif

#endif
