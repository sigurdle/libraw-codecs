/*
	Sony ARW tone curve (raw IFD tag 0x7010) — a port of the curve LibRaw builds from it
	(`src/metadata/tiff.cpp`, case 0x7010, and `src/metadata/identify.cpp`, the identity start;
	LibRaw 0.21.4), as used by `LibRaw::sony_arw2_load_raw`:
	  Copyright 2019-2021 LibRaw LLC (info@libraw.org)
	  LibRaw uses code from dcraw.c -- Dave Coffin's raw photo decoder,
	  dcraw.c is copyright 1997-2018 by Dave Coffin, dcoffin a cybercom o net.
	  LibRaw do not use RESTRICTED code from dcraw.c
	Modifications (the port described below): Copyright (C) 2026 Sigurd Lerstad, CDDL-1.0.
	LibRaw is dual-licensed LGPL-2.1 or CDDL-1.0, at your option; this port is distributed under the
	CDDL-1.0 election. See LICENSE.CDDL and PROVENANCE.md in this directory.

	ARW2 stores each sample through a piecewise-linear curve with four knots; the curve maps the
	12-bit index (the stored 11-bit sample shifted left by one) back to 14-bit linear sensor values.
	Changed from upstream: the curve is returned as a fresh array instead of filling LibRaw's global
	`curve`, and only the 4096 entries ARW2 can address are built.
*/

/**
 * @param {ArrayLike<number>} knots the four SHORT values of tag 0x7010
 * @returns {Uint16Array} curve[0..4095]: 12-bit index -> 14-bit linear value
 */
export function sonyToneCurve(knots)
{
	const curve = new Uint16Array(4096);
	for (let i = 0; i < 4096; ++i) curve[i] = i;
	const sony = [0, 0, 0, 0, 0, 4095];
	for (let c = 0; c < 4; ++c) sony[c + 1] = (knots[c] >> 2) & 0xfff;
	for (let i = 0; i < 5; ++i)
		for (let j = sony[i] + 1; j <= sony[i + 1]; ++j) curve[j] = curve[j - 1] + (1 << i);
	return curve;
}
