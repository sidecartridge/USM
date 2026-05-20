# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See also: `AGENTS.md` (project layout, build prereqs, code style, agent workflow rules) and `readme.md` (user-facing CLI usage, modes, caveats). This file covers what's not obvious from those sources or from the code itself.

## What this is

USM is a command-line tool that packages Atari ST `.PRG` executables into 128 KB cartridge ROM images (`.ROM` for emulators, or for actual cart hardware). The whole tool is a single C file: `usm.c`. The output is a fixed-size 128 KB buffer filled with the marker bytes `USM!`, then overwritten with a header, per-program metadata, and program payloads.

## Build / run

- macOS / Linux: `./build_mac_linux.sh` → produces `./usm` (just `gcc -O2 usm.c -o usm && strip usm`).
- Windows (MinGW): `build_mingw.bat` → produces `usm.exe`.
- Visual Studio project files (`usm.sln`, `usm.vcxproj`) also build the tool.
- CI builds for Linux/macOS/Windows live in `.github/workflows/build.yml`; releases in `release.yml`.
- `make tag` reads `version.txt`, tags `v$(VERSION)`, and pushes the tag.

There are no tests, no linter config, and no package manager — this is plain ANSI-ish C with `gcc`/MSVC.

## Architecture: three cart layouts, one tool

`usm.c` writes one of three on-disk layouts per program, depending on the flags. Understanding the differences is the bulk of the mental model:

### Default mode — stub-loader wrapping (recommended)
For each input `.PRG`, the tool writes a small 68k stub (`prg_loader`, an embedded byte array near the top of `usm.c`) followed by the **unmodified** PRG (header + sections + relocations) into the cart image. At runtime the stub:
1. Mshrinks the TOS-provided basepage,
2. `Malloc`s a fresh TPA from the largest free chunk,
3. Builds a complete Pexec-style basepage from scratch,
4. Copies the original PRG from ROM into the TPA at `$100(a5)`,
5. Zero-fills BSS (conditional on the PRGFLAGS fastload bit) and applies PRG relocations,
6. JMPs to the program entry.

The stub uses **PC-relative addressing** (`lea prg_payload(pc), a4`) to locate the appended PRG, so the same stub bytes work for every entry in a multi-program cart with no cart-build-time patching. Assembled from `prg_loader.s` using vasm: `stcmd vasm -quiet -Fbin -o prg_loader.bin prg_loader.s` (the project's `stcmd` dockerised toolchain). The resulting bytes are hand-pasted into the `prg_loader[]` array in `usm.c`. **If you edit `prg_loader.s`, you must rebuild `prg_loader.bin` AND copy its bytes back into `usm.c`** — there is no build-time linkage between the two.

### Default + compressed mode (`-z`)
Same shape as the default mode, but the PRG payload is LZSS-compressed and the stub variant is `prg_loader_compressed.s` / `prg_loader_compressed[]` (separate ~304-byte stub embedded next to `prg_loader[]`). Per-program cart layout:

```
[ CA_HEADER 34B ][ prg_loader_compressed bytes ][ uncompressed_size LONG, big-endian ][ compressed payload ]
```

The compressed stub does the same Mshrink + Malloc + basepage skeleton work, then replaces the ROM→RAM copy phase with an inline LZSS-12-4 decompressor (~80 bytes of 68k). Decompresses straight into the TPA at `$100(a5)` and then runs the same BSS clear / relocation / basepage finalization tail. Because the decompressed image *includes* the 28-byte PRG header (whereas the uncompressed stub skips the header in its copy), the compressed stub's relocator and basepage fill use `lea $100+prg_text(a5),a1` (= `$11C(a5)`) where the uncompressed stub uses `lea $100(a5),a1`. **Both stubs share the same sync rule**: edit `.s`, rebuild `.bin` via `stcmd vasm`, paste bytes into `usm.c`. `usm.c` auto-falls-back to the uncompressed stub for any entry whose compressed footprint isn't actually smaller (always the case for tiny PRGs because of the larger stub, and for already-packed demos because LZSS can't shrink them).

### Classic mode (`-c`) — in-ROM relocation
TEXT+DATA are copied into the cart (no PRG header), the program is relocated so TEXT/DATA references resolve to `$fa0000 + offset` (the cart's mapped address) and BSS references resolve to a hardcoded RAM address controlled by `-b` (default `$20000`). This is the older, fragile mode — PC-relative BSS access and programs that load external files won't work. Most real-world PRGs need the default mode.

### LZSS-12-4 stream format (the compressed payload's bitstream)

Sequence of ≤ 9-byte blocks. Each block:

```
[ flag byte ] [ up to 8 tokens ]
```

Flag byte's bits, MSB-first, classify the next 8 tokens:
- bit = 0 → next 1 byte is a literal, copy verbatim.
- bit = 1 → next 2 bytes are a back-reference, big-endian, packed as `(offset - 1) << 4 | (length - 3)`. Offset range 1..4096 (12 bits). Length range 3..18 (4 bits).

No EOF marker — decoder knows the expected uncompressed size from the LONG before the compressed bytes. The C reference encoder (`lzss_compress`) and host-side decoder (`lzss_decompress`) live in `usm.c` alongside a startup self-test (`lzss_selftest`) that runs on every invocation and a hidden `-T <file>` round-trip debug command. The 68k decompressor inside `prg_loader_compressed.s` is the canonical implementation; the host-side decoder mirrors it exactly.

### Cart header model
Cart starts at `$fa0000` on the Atari ST. Non-diagnostic carts begin with a 4-byte magic (`0xABCDEF42`), followed by a chain of `CA_HEADER` records (one per program) — each header points to the next via `CA_NEXT` (absolute ROM address), with the final entry's `CA_NEXT = 0`. `CA_INIT`'s top byte encodes the OS init-time flags configured by `-f` (0/1/3/5/6/7 — see `parse_init_parameter` in `usm.c:97`). `CA_FILENAME` is uppercased 8.3 GEMDOS.

Diagnostic mode (`-d`) replaces the magic with `0xfa52235f`, skips the CA_HEADER entirely, and only accepts a single program — the OS jumps to `$fa0004` after a reset.

STEem (`-s`) prepends 4 zero bytes to the output (its expected cart format).

### Byte order
Atari ST is 68k big-endian; the C code runs on little-endian hosts (and Windows/MSVC) — every multi-byte field is written through `BYTESWAP_LONG` / `BYTESWAP_WORD` macros (`usm.c:54-60`). When adding or reading fields, always go through these macros; raw stores will silently produce a broken ROM on host machines that aren't big-endian 68k.

### Per-file vs. global flags
`-b` (BSS address, classic mode only) and `-f` (init flag) can appear **before** the image filename (global default for all subsequent programs) or **after** a program filename (overrides only for that program). Argument parsing is a hand-rolled loop in `main()` that walks `argv` twice: once for globals, then once per input file for per-file overrides. The first non-flag argument is always the output cart filename.

## Things that bite

- `cart[]` and `prg_temp_buf[]` are 128 KB static buffers near the top of `usm.c`; `compress_temp_buf[]` adds a 256 KB scratch buffer used only by `-z`. Input PRGs larger than 128 KB are rejected. There's no streaming.
- The classic-mode relocation walker uses the standard PRG relocation byte-stream (offset 1 means "skip 254", 0 terminates). Both that walker and the in-stub relocators (uncompressed and compressed) must agree on the contract; don't touch one without re-reading the others.
- `ABSFLAG` non-zero means "no fixups"; classic mode skips the relocation pass in that case but does no further sanity checking. The stubs honour the same rule by testing `(a0)` is non-zero before walking.
- The `pragma pack(2)` block guarding `CA_HEADER` and `PRG_HEADER` is platform-conditional — keep both branches (MSVC `_WIN32` uses a non-stack `#pragma pack(2)`, everyone else uses push/pop). Misaligned struct writes here corrupt the ROM silently.
- The host-side LZSS encoder/decoder pair lives in `usm.c`. Any change to the bitstream format must be made in **three** places that stay in lock-step: `lzss_compress`, `lzss_decompress`, and the inline 68k decompressor inside `prg_loader_compressed.s`. The startup self-test (`lzss_selftest`) and `-T` debug command catch encoder/decoder divergence within `usm.c`; the 68k decompressor's drift will only show up in Hatari.

## Planning artifacts

Project-level planning (Epics / Stories / Tasks, progress tracking, design notes) lives under `docs/` at the repo root. `docs/` is **gitignored** and is private to the author's local workspace. Treat it like scratch paper.

**Hard rule:** never reference the planning structure or any Epic/Story/Task identifier, number, slug, or index in any committed artifact. That means **no** mentions in:
- commit messages, PR titles, or PR descriptions
- source-code comments
- `readme.md` or any other file outside `docs/`

When writing a commit, describe the change in its own terms ("fix CA_NEXT chain for multi-program carts", "reject zero-byte PRG inputs") — not as "completes Story 2 of the bug-squashing epic" or similar.

**Branch-to-Epic rule:** one branch per **Epic**, not per Story. A Story is a single commit on the Epic's branch (or a small set of related commits). The Epic ships as one PR containing the full sequence of Story commits. Branch names describe the work area in their own terms (e.g. `fix/cart-correctness`), never citing a planning ID.

## Editing guardrails

- The `prg_loader[]` and `prg_loader_compressed[]` byte arrays in `usm.c` are **generated output** from `prg_loader.s` and `prg_loader_compressed.s` via vasm — never hand-edit the bytes. If a stub needs a change, edit the `.s` file, rebuild the `.bin` (`stcmd vasm -quiet -Fbin -o prg_loader{,_compressed}.bin prg_loader{,_compressed}.s`), and copy the bytes back into `usm.c`. Both stubs use PC-relative payload addressing (`lea prg_payload(pc), a4`) so there are **no patch slots to keep in sync** — that part of the build pipeline is gone.
- Match the existing C style in `usm.c` — there is no `.clang-format` or linter wired up. Keep the same 4-space indent, brace placement, and `#pragma pack` platform guards (MSVC vs. everyone else).
- Don't refactor the classic-mode relocation walker for style — the byte-stream contract (`1` = skip 254, `0` = terminate) is what the PRG format requires.
- LZSS bitstream changes must update all three implementations in lock-step (`lzss_compress`, `lzss_decompress`, and the inline 68k decompressor in `prg_loader_compressed.s`).

---

## Working style

These behavioral guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think before coding

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical changes

Touch only what you must. Clean up only your own mess.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- When your changes orphan an import/variable/function, remove it. Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

### 4. Goal-driven execution

Define success criteria. Loop until verified. With no test suite here, verification means: build cleanly, then exercise the produced cart image (emulator or hardware) for the scenario the change targets.

### 5. No AI attribution

Never add AI-tool attribution to commits, PR descriptions, code comments, docs, or any other artifact. This means **no**:
- "Generated with Claude Code", "Co-authored by Claude", "Made with ChatGPT", or any similar phrasing.
- `Co-Authored-By: Claude …`, `Co-Authored-By: ChatGPT …`, or any other AI co-author trailer.
- "AI-assisted", "written with the help of an LLM", etc., as comments or changelog entries.

Write the message as the human author. Do not mention AI tools used to produce the work.
