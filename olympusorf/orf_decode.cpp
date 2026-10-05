/*
	Olympus / OM System ORF raw decoder — WASM C++.

	This is a direct port of LibRaw's Olympus decoder (`LibRaw::olympus_load_raw` and the bit reader
	it uses, `LibRaw::getbithuff`, both in `src/decoders/decoders_dcraw.cpp`, LibRaw 0.21.4):
	  Copyright 2019-2021 LibRaw LLC (info@libraw.org)
	  LibRaw uses code from dcraw.c -- Dave Coffin's raw photo decoder,
	  dcraw.c is copyright 1997-2018 by Dave Coffin, dcoffin a cybercom o net.
	  LibRaw do not use RESTRICTED code from dcraw.c
	Modifications (the port described below): Copyright (C) 2026 Sigurd Lerstad, CDDL-1.0.
	LibRaw is dual-licensed **LGPL-2.1 or CDDL-1.0, at your option**; this port is distributed
	under the CDDL-1.0 election. See LICENSE.CDDL in this directory, and PROVENANCE.md for the
	full attribution and what was changed. Same route as plugins/canoncrx and plugins/fujicompressed:
	the codec lives in its OWN isolated .wasm, separately built and replaceable.

	The algorithm — the 12-entry prefix code, the adaptive bit count per column parity, the
	sign/low/high split and the four-neighbor predictor — is carried over VERBATIM. Only LibRaw's
	framework was replaced:
	  - `fgetc(ifp)` over the open file → a bounded read from the strip held in memory; past its end
	    it returns EOF, exactly as the file read would at the end of the file.
	  - getbithuff's thread-local state (`tls->getbits`) → a `BitReader` passed explicitly.
	  - `fseek(ifp, 7, SEEK_CUR)` at the strip start → starting the reader 7 bytes into the strip.
	  - `RAW(row, col)` / `raw_image` → the caller's output buffer, `raw_width` samples per row.
	  - `derror()` (LibRaw's non-fatal "data error") → a count returned to the caller.
	  - `checkCancel()` → dropped; a WASM call runs to completion.

	Boundary (extern "C", prefixed _ on the JS side; see orf_decode_core.js):
	  int orf_decode(const uint8_t *strip, uint32_t size, int width, int height, int raw_width,
	                 uint16_t *out);
	    out is raw_width * height samples. Returns the data-error count (>= 0), or -1 on bad
	    arguments.
*/

#include <stdint.h>
#include <string.h>

typedef unsigned short ushort;
typedef unsigned char uchar;

#define ABS(x) (((int)(x) ^ ((int)(x) >> 31)) - ((int)(x) >> 31))
#define FORC(cnt) for (c = 0; c < cnt; c++)

struct BitReader
{
  const uchar *data;
  uint32_t size, pos;
  unsigned bitbuf;
  int vbits, reset;
  int errors;
};

static inline unsigned fgetc_mem(BitReader *br)
{
  return br->pos < br->size ? br->data[br->pos++] : (unsigned)-1; // EOF
}

// LibRaw::getbithuff, with zero_after_ff off (it is only on for lossless JPEG).
static unsigned getbithuff(BitReader *br, int nbits, ushort *huff)
{
  unsigned c;

  if (nbits > 25)
    return 0;
  if (nbits < 0)
    return br->bitbuf = br->vbits = br->reset = 0;
  if (nbits == 0 || br->vbits < 0)
    return 0;
  while (!br->reset && br->vbits < nbits && (c = fgetc_mem(br)) != (unsigned)-1)
  {
    br->bitbuf = (br->bitbuf << 8) + (uchar)c;
    br->vbits += 8;
  }
  c = br->vbits == 0 ? 0 : br->bitbuf << (32 - br->vbits) >> (32 - nbits);
  if (huff)
  {
    br->vbits -= huff[c] >> 8;
    c = (uchar)huff[c];
  }
  else
    br->vbits -= nbits;
  if (br->vbits < 0)
    ++br->errors;
  return c;
}

#define getbits(n) getbithuff(&br, n, 0)

extern "C" int orf_decode(const uint8_t *strip, uint32_t size, int width, int height, int raw_width, uint16_t *out)
{
  if (!strip || !out || width <= 0 || height <= 0 || raw_width < width || size < 7)
    return -1;

  BitReader br;
  memset(&br, 0, sizeof br);
  br.data = strip;
  br.size = size;
  br.pos = 7; // fseek(ifp, 7, SEEK_CUR)

#define RAW(row, col) out[(row) * raw_width + (col)]

  ushort huff[4096];
  int row, col, nbits, sign, low, high, i, c, w, n, nw;
  int acarry[2][3], *carry, pred, diff;

  huff[n = 0] = 0xc0c;
  for (i = 12; i--;)
    FORC(2048 >> i) huff[++n] = (i + 1) << 8 | i;
  getbits(-1);
  for (row = 0; row < height; row++)
  {
    memset(acarry, 0, sizeof acarry);
    for (col = 0; col < raw_width; col++)
    {
      carry = acarry[col & 1];
      i = 2 * (carry[2] < 3);
      for (nbits = 2 + i; (ushort)carry[0] >> (nbits + i); nbits++)
        ;
      low = (sign = getbits(3)) & 3;
      sign = sign << 29 >> 31;
      if ((high = getbithuff(&br, 12, huff)) == 12)
        high = getbits(16 - nbits) >> 1;
      carry[0] = (high << nbits) | getbits(nbits);
      diff = (carry[0] ^ sign) + carry[1];
      carry[1] = (diff * 3 + carry[1]) >> 5;
      carry[2] = carry[0] > 16 ? 0 : carry[2] + 1;
      if (col >= width)
        continue;
      if (row < 2 && col < 2)
        pred = 0;
      else if (row < 2)
        pred = RAW(row, col - 2);
      else if (col < 2)
        pred = RAW(row - 2, col);
      else
      {
        w = RAW(row, col - 2);
        n = RAW(row - 2, col);
        nw = RAW(row - 2, col - 2);
        if ((w < nw && nw < n) || (n < nw && nw < w))
        {
          if (ABS(w - nw) > 32 || ABS(n - nw) > 32)
            pred = w + n - nw;
          else
            pred = (w + n) >> 1;
        }
        else
          pred = ABS(w - nw) > ABS(n - nw) ? w : n;
      }
      if ((RAW(row, col) = pred + ((diff << 2) | low)) >> 12)
        ++br.errors;
    }
  }
#undef RAW
  return br.errors;
}
