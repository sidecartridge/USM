# AGENTS.md

This repository contains **USM**, a small host-side command-line tool (one C file) that packages Atari ST `.PRG` programs into 128 KB cartridge ROM images. See `CLAUDE.md` for architecture details and `readme.md` for end-user CLI usage.

---

## Project layout

- `usm.c` — the entire tool. Single translation unit, no headers of its own.
- `prg_loader.s` — 68k assembly for the default-mode runtime stub loader (the uncompressed variant).
- `prg_loader.bin` — vasm output of `prg_loader.s`. **The byte array `prg_loader[]` inside `usm.c` is a hand-copied snapshot of this file.** They can drift; keep them in sync.
- `prg_loader_compressed.s` — 68k assembly for the LZSS-aware stub used when `-z` is in effect. Shares the same Mshrink + Malloc + basepage skeleton as `prg_loader.s` but replaces the ROM→RAM copy with an inline LZSS-12-4 decompressor.
- `prg_loader_compressed.bin` — vasm output of the above, embedded as `prg_loader_compressed[]` in `usm.c` under the same sync rule as `prg_loader[]`.
- `prg_loader_build.bat` — assembles `prg_loader.s` with vasm (`vasm -quiet -Fbin -o prg_loader.bin prg_loader.s`); the compressed stub uses the analogous incantation.
- `build_mac_linux.sh`, `build_mingw.bat` — host builds (gcc / MinGW gcc).
- `usm.sln`, `usm.vcxproj`, `usm.vcxproj.filters` — Visual Studio build files (kept in sync with the gcc builds).
- `Makefile` — only target is `make tag` (reads `version.txt`, tags and pushes).
- `.github/workflows/` — CI builds for Linux/macOS/Windows + release packaging.
- `SWITCHER.ROM`, `SWITCHER.TOS`, sample binaries — committed test artifacts, leave alone unless asked.

---

## Build prerequisites

- A C compiler: `gcc` (Linux/macOS) or MinGW `gcc` (Windows). MSVC via the `.sln` is also supported.
- **vasm** (Motorola syntax) — only needed if you edit `prg_loader.s` or `prg_loader_compressed.s`. Not required for routine `usm.c` work. The repo's existing `stcmd` Dockerised toolchain ships vasm; the typical invocation is `STCMD_NO_TTY=1 STCMD_QUIET=1 stcmd vasm -quiet -Fbin -o prg_loader{,_compressed}.bin prg_loader{,_compressed}.s`.
- No package manager, no submodules, no SDK.

---

## Build commands

```sh
./build_mac_linux.sh    # Linux/macOS: gcc -O2 usm.c -o usm && strip usm
build_mingw.bat         # Windows MinGW
prg_loader_build.bat    # only when prg_loader.s changed
```

You can also just run `gcc -O2 usm.c -o usm` directly; the scripts add nothing beyond that and a `strip`.

---

## Tests

There is **no test suite**. Validation is done by:
1. Building `usm`.
2. Running it against a known `.PRG` to produce a cart image.
3. Loading the image in an Atari ST emulator (Hatari, STEem with `-s`) or on real hardware.

---

## Code style

- No `.clang-format`, no `.clang-tidy`, no `.editorconfig` in this repo. **Match `usm.c` as written**: ~4-space indent, K&R-ish braces, lowercase `snake_case` for functions and locals, ALL_CAPS for typedef'd structs and macros (`CA_HEADER`, `BYTESWAP_LONG`).
- Multi-byte writes always go through `BYTESWAP_LONG` / `BYTESWAP_WORD`. Don't bypass them.
- Keep the `#pragma pack(2)` platform guards intact around `CA_HEADER` / `PRG_HEADER` (MSVC `_WIN32` uses a bare `#pragma pack(2)`; everyone else uses `push`/`pop`).
- Fixed-width types (`uint32_t`, `uint16_t`, `int8_t`) for anything that ends up in the cart image.

---

## Workflow rules for agents

- Do not discard or overwrite local changes without explicit user approval.
- You may compile directly (`gcc -O2 usm.c -o usm`) for verification without invoking the build scripts.
- Don't bump `version.txt` or run `make tag` without an explicit ask — it pushes a git tag.
- If you edit `prg_loader.s`, you must also rebuild `prg_loader.bin` and re-copy the bytes into `usm.c`; otherwise the change has no effect at runtime.
- No Cursor or Copilot rule files are present in this repo.

---

## "Done" checklist

- `usm` compiles cleanly with `gcc -O2 -Wall usm.c -o usm` (no new warnings beyond the baseline).
- If `prg_loader.s` was touched: `prg_loader.bin` regenerated and `prg_loader[]` in `usm.c` updated; `0x3a`/`0x40` patch offsets at `usm.c:389-392` still point at the right slots.
- The change has been exercised end-to-end by producing a cart image and loading it in an emulator or on hardware.
