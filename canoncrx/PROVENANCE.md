# Provenance — Canon CR3 `crx` decoder

`crx_decode.cpp` is a **port of LibRaw's crx decoder**, not an independent implementation.

**Upstream:** LibRaw 0.21.4, `src/decoders/crx.cpp`
**Copyright:** (C) 2018–2019 Alexey Danilchenko; (C) 2019 Alex Tutubalin, LibRaw LLC
**License:** LibRaw is dual-licensed — **GNU LGPL 2.1** *or* **CDDL 1.0**, at the recipient's option.
**Our election: CDDL 1.0.** The full text is in `LICENSE.CDDL` alongside this file.

## What that obliges us to do

CDDL is *file-scoped* copyleft. `crx_decode.cpp` and any modification to it stay under CDDL and
must be made available in source form; it may be combined into a Larger Work under other terms.
Concretely:

* Keep this file, `LICENSE.CDDL`, and the attribution header inside `crx_decode.cpp` intact.
* Keep the decoder in **its own `.wasm`**, built by `build.sh` from the source in this directory —
  which is how it already ships (the vc1/vp6 precedent). That separation is what keeps the license
  boundary clean and unambiguous: the module is separately built and independently replaceable.
* Any bug fix or change to `crx_decode.cpp` remains CDDL and stays published here.
* The Source Code form is public at https://github.com/sigurdle/libraw-codecs, synced by
  `tools/publish-libraw-codecs.mjs`; the application's About box links it.

This is the same route as `plugins/vp6`, which is a port of FFmpeg's LGPL VP6 decoder.

## What was changed from upstream

The algorithm is carried over **verbatim** — the Golomb-Rice/adaptive-k symbol coder, the
predictors, the 5/3 wavelet reconstruction, the quantization tables, tile/subband setup. Only
LibRaw's surrounding framework was replaced, because none of it exists here:

| Upstream | Here | Why |
| --- | --- | --- |
| `LibRaw_abstract_datastream` (seek/read/lock) | the mdat payload as a flat memory span; `crxFillBuffer` is a bounded memcpy | the caller already holds the whole compressed track; no IO layer, no locking |
| `throw LIBRAW_EXCEPTION_IO_*` | error returns | built `-fno-exceptions`; only the refill threw, on a short read, which a memory span cannot do |
| `std::vector` + `catch (...)` around the QP table | `calloc` + a null check | the catch existed solely to turn `bad_alloc` into `-1` — same behaviour, no C++ runtime |
| `crxLoadDecodeLoop` / `crxLoadFinalizeLoopE3` / `crxConvertPlaneLineDf` (virtual, to host OpenMP) | plain sequential loops | single-threaded in WASM |
| `crxLoadRaw()` (reads geometry from LibRaw's global unpacker state) | `crx_decode()`, taking the CMP1 bytes and the mdat span explicitly | no LibRaw object to hang state off |
| `crx_data_header_t` with container/stsc/chunk members | just the fields `crxParseImageHeader` fills | container parsing lives in `helpers/raw/CR3.js` |
| `#ifdef LIBRAW_CR3_MEMPOOL` (`libraw_memmgr`) and `#ifdef LIBRAW_USE_OPENMP` branches | removed | both are off in the default upstream build; carrying them would be dead code |

One genuine addition, needed only because of the target: `-sSTACK_SIZE=1048576` in `build.sh`.
`CrxBitstream` embeds a 64 KB refill buffer and `crxReadImageHeaders` places one on the stack,
which overflows Emscripten's 64 KB default. Upstream never hit this — it runs on a native stack.

## Verification

`tests/RawCanonCRX.test.js` decodes both real samples through this module and compares against
the LibRaw **golden mosaic** (`unprocessed_raw -T`), which is the same code's own output:

* `Canon_EOS250D_raw.cr3` (lossless RAW) — **bit-exact**, 6288×4056
* `Canon_EOS250D_craw.cr3` (lossy C-RAW) — **bit-exact**, 6288×4056

A port being bit-exact against its own upstream is a *regression* check, not an independent
correctness proof — it proves the de-frameworking above changed nothing. The independent evidence
that the format is understood is separate: `tmp/crx/CRX_LOSSLESS_RECON.md` documents a clean-room
reconstruction of the lossless symbol layer that reached bit-exactness on line 0 of all 8 planes
from the golden alone, and its findings (Golomb-Rice with an escape, zigzag mapping, MED
prediction with a `1 << (bpp-1)` virtual row) match what this code does.
