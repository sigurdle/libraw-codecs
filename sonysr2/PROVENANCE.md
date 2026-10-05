# Provenance — Sony SR2Private decryption and ARW2 tone curve

Two small ports of LibRaw code, not independent implementations:

* `sony_decrypt.js` — `LibRaw::sony_decrypt`. It decrypts the block of Sony metadata (as-shot white
  balance, levels) that every ARW carries encrypted.
* `sony_tone_curve.js` — the curve LibRaw builds from raw IFD tag 0x7010, which maps ARW2's stored
  samples back to 14-bit linear values.

**Upstream:** LibRaw 0.21.4 — `src/metadata/sony.cpp` (`LibRaw::sony_decrypt`); `src/metadata/tiff.cpp`
(case 0x7010) and `src/metadata/identify.cpp` (the identity curve it starts from)
**Copyright:** (C) 2019–2021 LibRaw LLC; LibRaw uses code from dcraw.c, (C) 1997–2018 Dave Coffin
(LibRaw does not use dcraw's RESTRICTED code)
**Modifications:** (C) 2026 Sigurd Lerstad
**License:** LibRaw is dual-licensed — **GNU LGPL 2.1** *or* **CDDL 1.0**, at the recipient's option.
**Our election: CDDL 1.0.** The full text is in `LICENSE.CDDL` alongside this file.

## What that obliges us to do

CDDL is *file-scoped* copyleft: both files and any change to them stay CDDL and stay published;
the application that imports it is a Larger Work under its own terms.

* Keep this file, `LICENSE.CDDL`, and the attribution headers in both files intact.
* Keep the ports in their own files. The code that finds the block and reads its tags
  (`helpers/raw/SonySR2.js`) is the application's own and is not covered.
* The Source Code form is public at https://github.com/sigurdle/libraw-codecs, synced by
  `tools/publish-libraw-codecs.mjs`; the application's About box links it.

## What was changed from upstream

| Upstream | Here | Why |
| --- | --- | --- |
| pad stored byte-swapped (`htonl`), words XORed in host order | pad in natural order, each word XORed big-endian byte by byte | the same bytes, independent of host endianness |
| pad and position in thread-local state, `start` flag | a local pad; every call starts a fresh stream | the metadata path only ever calls it with `start` = 1 |
| C, `unsigned` arithmetic | JS, `Math.imul` and `>>> 0` for 32-bit wraparound | same arithmetic modulo 2^32 |
| tone curve written into LibRaw's global `curve` (65536 entries) | a fresh 4096-entry array returned | ARW2 addresses only 12-bit indices |

## Verification

`tests/RawSonySR2.test.js` decrypts the SR2Private block of two real ARWs (NEX-3, ILCE-7RM5) and reads
the as-shot white balance and levels LibRaw's `raw_identify -v` reports for the same files; and maps
the NEX-3's ARW2 samples through the tone curve, bit-exact against LibRaw's unprocessed mosaic.
