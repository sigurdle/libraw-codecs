/*
	Sony SR2Private decryption — a port of LibRaw's `LibRaw::sony_decrypt`
	(`src/metadata/sony.cpp`, LibRaw 0.21.4):
	  Copyright 2019-2021 LibRaw LLC (info@libraw.org)
	  LibRaw uses code from dcraw.c -- Dave Coffin's raw photo decoder,
	  dcraw.c is copyright 1997-2018 by Dave Coffin, dcoffin a cybercom o net.
	  LibRaw do not use RESTRICTED code from dcraw.c
	Modifications (the port described below): Copyright (C) 2026 Sigurd Lerstad, CDDL-1.0.
	LibRaw is dual-licensed LGPL-2.1 or CDDL-1.0, at your option; this port is distributed under the
	CDDL-1.0 election. See LICENSE.CDDL and PROVENANCE.md in this directory.

	The cipher is carried over verbatim: a 127-word pad seeded from the key by k = k * 48828125 + 1,
	extended by the shift-XOR recurrence, then each 32-bit word of the data XORed with the next pad
	word. Changed from upstream: upstream keeps the pad byte-swapped (htonl) and XORs words in host
	order; here the pad stays in its natural order and each word is XORed big-endian, byte by byte —
	the same bytes, without depending on the host's endianness. The pad lives in a local instead of
	LibRaw's thread-local state, and the call always starts a fresh stream (upstream's `start` = 1,
	the only way this metadata path calls it).
*/

/**
 * Decrypt `data` (a Uint8Array, modified in place) with Sony's SR2 key. Only whole 32-bit words are
 * decrypted, as upstream does (`len / 4` words).
 */
export function sonyDecrypt(data, key)
{
	const pad = new Uint32Array(128);
	key >>>= 0;
	for (let p = 0; p < 4; ++p) pad[p] = key = (Math.imul(key, 48828125) + 1) >>> 0;
	pad[3] = (pad[3] << 1 | (pad[0] ^ pad[2]) >>> 31) >>> 0;
	for (let p = 4; p < 127; ++p) pad[p] = ((pad[p - 4] ^ pad[p - 2]) << 1 | (pad[p - 3] ^ pad[p - 1]) >>> 31) >>> 0;

	for (let w = 0, p = 127; w + 4 <= data.length; w += 4, ++p) {
		const v = pad[p & 127] = (pad[(p + 1) & 127] ^ pad[(p + 65) & 127]) >>> 0;
		data[w] ^= v >>> 24;
		data[w + 1] ^= (v >>> 16) & 255;
		data[w + 2] ^= (v >>> 8) & 255;
		data[w + 3] ^= v & 255;
	}
	return data;
}
