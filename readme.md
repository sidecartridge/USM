USM
===

Small tool to ease the creation of Atari ST cart images.

Usage
-----

From the command line:

`usm [-s] [-d] [-c] [-z] [-bX] [-fY] image_filename <list of programs to add with optional -b, -f, -z>`

where:

- *-s* is optional and allows creation of STEem Engine compatible carts
- *-d* enables creation of diagnostic cartridges (only one program allowed, which will relocate to $fa0004)
- *-c* to switch to the classic way of adding the application to the ROM
- *-z* compresses each PRG with LZSS (auto-falls-back to uncompressed if the compressed entry would be larger; see "Compression" below)
- *-bX* allows setting the BSS address to an address other than the default ($only when -c is active, default: $20000)
- *-fY* allows seting the INIT flag. y can be
  - 0       Execute prior to display memory and interrupt vector initialization
  - 1       Execute just before GEMDOS is initialized
  - 3       Execute prior to boot disk
  - 5       Application is a Desk Accessory
  - 6       Application is not a GEM application
  - 7       Application needs parameters
- *image_filename* is the filename of the cart image
- *list of programs to add with optional -b, -f, -z* is a list of ST PRG programs to add to the image, optionally postfixed by a *-b*, *-f*, or *-z* to set the parameters for the current file only

More on defaults: The default value for *-b* is $20000, and the default value for *-f* is 0. Passing *-b*, *-f*, and/or *-z* at the start of the parameter list will override the default values. Passing them after each program in the list will override the defaults for that file only.

`-z` is rejected with `-c` (classic mode runs the program directly from ROM, so there's nowhere to decompress to) and with `-d` (diagnostic carts execute with no TOS context, but the decompressor needs `Malloc`).

Two modes of operation
----------------------

Until the second release there was a single mode of operation (explained below).

The current default mode is to add a TOS PRG file with a small stub loader included which will copy the actual program from ROM to RAM, try to set up the system as well as it can, and then execute the program from RAM. With `-z` the PRG is LZSS-compressed in the cart and decompressed to RAM at launch instead of straight-copied; both stub variants build a fresh TPA via `Malloc` and run the program with a real GEMDOS basepage.

The old mode adds the program to ROM and relocates it to run from there, with the BSS start address set in RAM by the user (or default value is used). This mode works for simple applications, but there will be many problems down the road for non properly written applications for this mode (i.e. pretty much all of them).

Compression (`-z`)
------------------

Custom LZSS variant — byte-aligned 8-token flag groups, 12-bit offsets (1..4096), 4-bit length-minus-3 (matches 3..18). Both the encoder (C) and the decompressor (68k) are written from scratch and ship inside this repo; there's no external library dependency. Typical ratios on structured 68k code are 70–85%; already-packed demos and games tend to grow under LZSS, so `usm -z` automatically falls back to the uncompressed path whenever the compressed entry would be larger than the uncompressed one (it prints a one-line per-program note in either case). Carts can freely mix compressed and uncompressed entries.

Caveats
-------

- Only use single file PRG programs. Programs that try to load external files will not work
- TODO: Some sanity checks are performed, but the program is far from bullet proof
- On BSS, for "old" mode: programs that access the BSS using PC relative code will most likely fail

Building
--------

Use the provided scripts. Or Visual Studio.


Thank yous
----------

Diego Parrilla for supplying the Github actions to automatically build binaries for all platforms, and some other fixes in the code.
tIn/Newline for the original stub loader source code.
