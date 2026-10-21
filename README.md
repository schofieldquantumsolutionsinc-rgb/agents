# Schofield Quantum Agents — Native JLSQ V17

This repository's agent path is now **100% native JLSQ V17 execution**.

The native tools are reproduced from the committed assembly sources
in `native/src/` (JLSQ V17 Native Foundation Toolsuite 001) using the
system assembler/linker as build-time reproduction tools only — the
same disclosed boundary as the toolsuite itself. All agent execution
is by the resulting static native binaries. The QGENT dispatcher
(`native/src/qgent-dispatcher-001.qsource`, compiled at build time by
JLSQ V17 GRACE PILER) runs on the native QRUNTIME/QSEED-1 profile.

## Capability truth table

- status: SUPPORTED (native QNODE + QIDENTITY + QGENT dispatcher
  CURRENT_WORK_READ, executed and evidenced in the workflow logs)
- build_apk: UNSUPPORTED
- search: NOT YET IMPLEMENTED
- learn: NOT YET IMPLEMENTED
- network / inference / persistence services: NOT YET IMPLEMENTED /
  UNKNOWN per the QGENT action matrix — never advertised as working

## History

The previous Python path (`agent_system.py`, setup-python workflow,
`requests` dependency) was replaced 2026-10-21 after the native
dispatcher passed its rehearsal QEST ledger (23 PASS / 0 FAIL;
production QESTs recorded separately). Its exact prior bytes remain
in git history at commit 22973cf1d5bcd6bc2357e874e9b78a2107b8f697
(agent_system.py blob 311af8732340bef22df74c4714760d89572783a8).

Owner: Jonathan Lynn Schofield / Schofield Quantum Solutions / JLSQ Inc.
