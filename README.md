# libraw-codecs

WebAssembly camera-raw decoders ported from **[LibRaw](https://github.com/LibRaw/LibRaw)**.
LibRaw is dual-licensed LGPL-2.1 or CDDL-1.0 at the recipient's option; these ports are
distributed under the **CDDL-1.0** election (see [`LICENSE`](./LICENSE) and [`NOTICE`](./NOTICE)).

This repository makes the decoder **source** available for the compiled `.wasm` binaries
shipped inside a closed-source application, as CDDL-1.0 section 3.1 requires. The application
is a separate work that combines these decoders into a Larger Work (CDDL-1.0 section 3.6) and is
not covered by this license.

## What's here

| Directory | Decoder | Upstream file |
|-----------|---------|---------------|
| `canoncrx/` | Canon CR3 `crx`, lossless RAW and lossy C-RAW | `src/decoders/crx.cpp` (LibRaw 0.21.4) |
| `fujicompressed/` | Fujifilm compressed RAF, lossless and lossy, Bayer and X-Trans | `src/decoders/fuji_compressed.cpp` (LibRaw 0.21.4) |
| `olympusorf/` | Olympus / OM System ORF | `olympus_load_raw` + `getbithuff` in `src/decoders/decoders_dcraw.cpp` (LibRaw 0.21.4) |

Each directory holds the ported C/C++, the `build.sh` that produced the shipped binary, a
`PROVENANCE.md` stating exactly what was changed from upstream, and the CDDL text. The
application-side JavaScript that loads and drives the modules is not part of this repository.

## Building

Each `build.sh` compiles its sources to a standalone `.wasm` module with
[Emscripten](https://emscripten.org/). The scripts assume an `emsdk` install; set `EMSDK_DIR`.

```sh
cd canoncrx && ./build.sh        # -> crx_decode.{wasm,mjs}
cd fujicompressed && ./build.sh  # -> fuji_decode.{wasm,mjs}
cd olympusorf && ./build.sh      # -> orf_decode.{wasm,mjs}
```

These are the scripts used to build the shipped binaries, unedited, so each also emits a second
`node`-flavored module into the application's `tests/wasm/` for its conformance test. That path
does not exist here, so the script writes the shipped `.wasm` and `.mjs` first and then exits
non-zero at the test link; the decoder is already built at that point.
