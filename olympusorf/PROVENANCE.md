# Provenance — Olympus / OM System ORF decoder

`orf_decode.cpp` is a **port of LibRaw's Olympus decoder**, not an independent implementation.

**Upstream:** LibRaw 0.21.4, `src/decoders/decoders_dcraw.cpp` — `LibRaw::olympus_load_raw` and
the bit reader it uses, `LibRaw::getbithuff`
**Copyright:** (C) 2019–2021 LibRaw LLC; LibRaw uses code from dcraw.c, (C) 1997–2018 Dave Coffin
(LibRaw does not use dcraw's RESTRICTED code)
**Modifications:** (C) 2026 Sigurd Lerstad
**License:** LibRaw is dual-licensed — **GNU LGPL 2.1** *or* **CDDL 1.0**, at the recipient's option.
**Our election: CDDL 1.0.** The full text is in `LICENSE.CDDL` alongside this file.

## What that obliges us to do

CDDL is *file-scoped* copyleft. `orf_decode.cpp` and any modification to it stay under CDDL and must
be made available in source form; it may be combined into a Larger Work under other terms.

* Keep this file, `LICENSE.CDDL`, and the attribution header inside `orf_decode.cpp` intact.
* Keep the decoder in **its own `.wasm`**, built by `build.sh` from the source in this directory.
* Any bug fix or change to `orf_decode.cpp` remains CDDL and stays published.
* The Source Code form is public at https://github.com/sigurdle/libraw-codecs, synced by
  `tools/publish-libraw-codecs.mjs`; the application's About box links it.

Same route as `plugins/canoncrx` and `plugins/fujicompressed`.

## What was changed from upstream

The algorithm is carried over **verbatim**: the 12-entry prefix code, the adaptive bit count per
column parity, the sign/low/high split and the four-neighbor predictor. Only LibRaw's framework was
replaced:

| Upstream | Here | Why |
| --- | --- | --- |
| `fgetc(ifp)` in `getbithuff` | a bounded read from the strip in memory, `EOF` past its end | the caller holds the strip; the end behaves exactly as end-of-file |
| `tls->getbits` (thread-local bit state) | a `BitReader` passed explicitly | no LibRaw object, single-threaded |
| `fseek(ifp, 7, SEEK_CUR)` | the reader starts 7 bytes into the strip | the strip is a span, not a file position |
| `RAW(row, col)` / `raw_image` | the caller's output buffer, `raw_width` samples per row | no LibRaw image buffer |
| `derror()` | counted, returned | upstream's `derror` is a non-fatal warning too |
| `checkCancel()` | dropped | a WASM call runs to completion |
| `zero_after_ff` in `getbithuff` | not carried | it is only set for lossless JPEG, never on this path |

Where the decoder's parameters come from — white balance, black levels, valid bits and the crop, all
in the Olympus MakerNote — is the application's own reading of the file
(`helpers/raw/OlympusORF.js`), not ported code.

## Verification

`tests/RawOlympusORF.test.js` decodes four real samples through this module and compares against the
LibRaw **golden mosaic** (`unprocessed_raw -T`): E-520 (2008), E-M10 Mark IV, E-M1 Mark III and
OM System OM-1 — all **bit-exact**. A port being bit-exact against its own upstream is a regression
check: it proves the de-frameworking above changed nothing.
