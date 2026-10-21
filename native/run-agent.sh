#!/bin/sh
# Native agent entry: status + QGENT dispatcher boundary proof.
# All execution is by the native binaries in native/bin. This shell
# script only launches them and assembles the fixture data section
# (run-time orchestration, same class as the suites' build scripts).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN="$ROOT/bin"; B="$ROOT/.build"; mkdir -p "$ROOT/../logs" "$B"
LOG="$ROOT/../logs/native-agent.log"
{
  echo "== QIDENTITY =="
  "$BIN/qidentity-v17" || true
  echo "== QNODE STATUS =="
  "$BIN/qnode-v17" || true
  echo "== QGENT DISPATCHER (CURRENT_WORK_READ, genesis state) =="
  hex=""
  for pair in 0,0 9,0 10,0 11,0 12,0 1,7 2,101 3,1 4,0 5,0 6,0 7,1 8,1; do
    t=${pair%%,*}; v=${pair##*,}
    for w in $t $v; do
      i=0; while [ $i -lt 8 ]; do printf -v byte '%02x' $(( (w >> (8*i)) & 255 )) 2>/dev/null || byte=$(printf '%02x' $(( (w >> (8*i)) & 255 ))); hex="$hex$byte"; i=$((i+1)); done
    done
  done
  { cat "$ROOT/src/qgent-dispatcher-001.qsource"; echo ".data"; echo "RAW $hex"; } > "$B/fixture.qsource"
  "$BIN/jlsq-v17-grace-piler" < "$B/fixture.qsource" > "$B/fixture.qbn1"
  "$BIN/qverify-v17" < "$B/fixture.qbn1"
  "$BIN/qruntime-v17" < "$B/fixture.qbn1"
} | tee "$LOG"
