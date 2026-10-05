# Provenance — Fujifilm compressed RAF decoder

`fuji_decode.cpp` is a **port of LibRaw's Fujifilm compressed decoder**, not an independent
implementation.

**Upstream:** LibRaw 0.21.4, `src/decoders/fuji_compressed.cpp` (and `parse_fuji_compressed_header`
from the same file)
**Copyright:** (C) 2016–2019 Alexey Danilchenko; adopted to LibRaw by Alex Tutubalin, LibRaw LLC
**Modifications:** (C) 2026 Sigurd Lerstad
**License:** LibRaw is dual-licensed — **GNU LGPL 2.1** *or* **CDDL 1.0**, at the recipient's option.
**Our election: CDDL 1.0.** The full text is in `LICENSE.CDDL` alongside this file.

## What that obliges us to do

CDDL is *file-scoped* copyleft. `fuji_decode.cpp` and any modification to it stay under CDDL and
must be made available in source form; it may be combined into a Larger Work under other terms.
Concretely:

* Keep this file, `LICENSE.CDDL`, and the attribution header inside `fuji_decode.cpp` intact.
* Keep the decoder in **its own `.wasm`**, built by `build.sh` from the source in this directory.
* Any bug fix or change to `fuji_decode.cpp` remains CDDL and stays published.
* The Source Code form is public at https://github.com/sigurdle/libraw-codecs, synced by
  `tools/publish-libraw-codecs.mjs`; the application's About box links it.

Same route as `plugins/canoncrx` (LibRaw's crx decoder).

## What was changed from upstream

The algorithm is carried over **verbatim**: the adaptive-gradient symbol coder (`fuji_zerobits`,
`fuji_read_code`, `bitDiff`), the even/odd sample predictors, the lossless and lossy quantization
tables, the X-Trans and Bayer line schedules, and the line-buffer scatter into the mosaic. Only
LibRaw's surrounding framework was replaced:

| Upstream | Here | Why |
| --- | --- | --- |
| `LibRaw_abstract_datastream` (seek/read/lock) in `fuji_fill_buffer` | a bounded `memcpy` from the stream span, same per-fill and per-block limits | the caller already holds the whole CFA section; no IO layer, no locking |
| `throw LIBRAW_EXCEPTION_IO_EOF` in the refill | an `eof` flag on the block; the refill serves 0xFF bytes (zeros would spin `fuji_zerobits` forever), the strip runs out, `fuji_decode` returns `-4` | built `-fno-exceptions`; a truncated file still fails, just without unwinding |
| `derror()` on a bad code or block width | counted, returned in `info[3]` | upstream's `derror` is a non-fatal warning too |
| `libraw_internal_data.unpacker_data.fuji_*`, `imgdata.sizes`, `xtrans_abs`, `FC()` | a `FujiStream` context; the CFA layout at the sensor origin is passed in as 36 bytes | no LibRaw object; the RAF reader already knows the layout from the RAF directory |
| `parse_fuji_compressed_header` (patching LibRaw's state, `data_offset += 16`) | `parse_header` filling the context, offsets relative to the stream start | the same fields and the same validation |
| `fuji_compressed_load_raw` / `fuji_decode_loop` (OpenMP over blocks) | `fuji_decode()`, a plain sequential loop | single-threaded in WASM |
| `LibRaw::` member functions | `static` functions taking the context | no class to hang them on |

## Verification

`tests/RawFujiCompressed.test.js` decodes three real samples through this module and compares
against the LibRaw **golden mosaic** (`unprocessed_raw -T`):

* `Fujifilm_GFX50S_14bit_compressed.raf` (lossless, Bayer) — **bit-exact**, 9216×6210
* `Fujifilm_XT4_14bit_lossless.raf` (lossless, X-Trans) — **bit-exact**, 6384×4182
* `Fujifilm_XT4_14bit_compressed.raf` (lossy, X-Trans) — **bit-exact**, 6384×4182

A port being bit-exact against its own upstream is a regression check: it proves the
de-frameworking above changed nothing.
