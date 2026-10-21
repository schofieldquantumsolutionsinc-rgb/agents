#!/bin/sh
# Build the native JLSQ V17 tools from committed assembly source.
# as/ld are build-time reproduction tools ONLY (Grace's disclosed
# boundary); execution uses the produced static native binaries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN="$ROOT/bin"; mkdir -p "$BIN" "$ROOT/.build"
B="$ROOT/.build"
build_tool(){ mode=$1 name=$2; as --64 --defsym TOOL_MODE=$mode -o "$B/$name.o" "$ROOT/src/jlsq_foundation_tools.s"; ld -static -nostdlib -o "$BIN/$name" "$B/$name.o"; }
build_tool 1 qreader-v17
build_tool 3 qverify-v17
build_tool 5 qnode-v17
build_tool 6 qouter-v17
build_tool 8 qidentity-v17
as --64 -o "$B/qcompiler.o" "$ROOT/src/grace-piler-jon-parser-seed.s"
ld -o "$BIN/jlsq-v17-grace-piler" "$B/qcompiler.o"
as --64 -o "$B/qseed1.o" "$ROOT/src/cosmo-strap-seed.s"
ld -o "$BIN/qruntime-v17" "$B/qseed1.o"
"$BIN/jlsq-v17-grace-piler" < "$ROOT/src/qgent-dispatcher-001.qsource" > "$ROOT/.build/dispatcher-nodata.qbn1"
# dispatcher fixture: genesis STATE (rev 0) + CURRENT_WORK_READ request
# identity 101, authority 1, rev_seen 0, nonce 1 (fixture built by
# run-agent.sh, which appends the .data section before compiling).
cp "$ROOT/src/qgent-dispatcher-001.qsource" "$ROOT/.build/dispatcher-fixture.qsource"
echo "native build complete: $(ls "$BIN" | wc -l) tools"
