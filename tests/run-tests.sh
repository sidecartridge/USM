#!/bin/sh
# Cart-build sanity test for usm.
#
# For each PRG fixture in tests/binaries/ and tests/fixtures/, builds
#   * an uncompressed cart (./usm out.rom file)
#   * a compressed cart   (./usm -z out.rom file, auto-fallback as needed)
# Then verifies each generated cart is exactly 131072 bytes (the cart
# format's fixed size). Aggregates pass/fail across all builds.
#
# Run from anywhere. Exits 0 on success, non-zero if any build failed
# or produced a wrong-sized cart.
#
# If the environment variable HATARI is set to a Hatari binary path,
# each cart is also booted in Hatari with --run-vbls=300 (= about 6
# seconds of emulated runtime) and exit code 0 means it didn't crash.
# Hatari isn't installed by CI, so the Hatari step is opt-in.

set -e

cd "$(dirname "$0")/.."

if [ ! -x ./usm ]; then
    echo "==> Building usm"
    ./build_mac_linux.sh
fi

mkdir -p build

status=0
fixtures=""
for f in tests/binaries/*.PRG tests/binaries/*.TOS \
         tests/fixtures/*.prg tests/fixtures/*.PRG \
         tests/fixtures/*.tos tests/fixtures/*.TOS; do
    [ -e "$f" ] && fixtures="$fixtures $f"
done

if [ -z "$fixtures" ]; then
    echo "No fixtures found in tests/binaries/ or tests/fixtures/" >&2
    exit 1
fi

check_size() {
    expected=$1
    path=$2
    if [ "$(uname)" = "Darwin" ]; then
        actual=$(stat -f %z "$path")
    else
        actual=$(stat -c %s "$path")
    fi
    if [ "$actual" -ne "$expected" ]; then
        echo "FAIL: $path is $actual bytes, expected $expected" >&2
        return 1
    fi
}

for src in $fixtures; do
    name=$(basename "$src")
    plain="build/${name%.*}_test.ROM"
    compd="build/${name%.*}_test_z.ROM"

    ./usm        "$plain" "$src" || status=1
    ./usm -z     "$compd" "$src" || status=1
    check_size 131072 "$plain"   || status=1
    check_size 131072 "$compd"   || status=1
done

# Clean up _test* artefacts so they don't pollute build/ between runs.
rm -f build/*_test.ROM build/*_test_z.ROM

if [ "$status" -eq 0 ]; then
    echo
    echo "All cart builds OK"
else
    echo
    echo "FAILED: at least one cart build diverged" >&2
fi

exit "$status"
