# PROVENANCE — native sources in this repository

- native/src/cosmo-strap-seed.s
  SHA-256 1d693a49f027523bd44e8dc20ac6300ba2bc766a5ac17e4833af77c2717d80a9
  Origin: JLSQ_V17_NATIVE_FOUNDATION_TOOLSUITE_001 (ZIP 6bcf440a…)
- native/src/grace-piler-jon-parser-seed.s
  SHA-256 1696cc2c21c914d6baa01f50caf16d54ac701fd717c3111569971db32dd6be46
  Origin: JLSQ_V17_NATIVE_FOUNDATION_TOOLSUITE_001 (ZIP 6bcf440a…)
- native/src/jlsq_foundation_tools.s
  SHA-256 3b38503a5e7e9ada2579f265681be24b1c484c79edb034d1de167c903c9c15fc
  Origin: JLSQ_V17_NATIVE_FOUNDATION_TOOLSUITE_001 (ZIP 6bcf440a…)
- native/src/qgent-dispatcher-001.qsource
  SHA-256 b3690a14db323117754229661df2769987cd80201db13d610dbc372fcdd4971c
  Origin: QGENT DISPATCHER 001 implementation (Cosmo), vault batch 790

Reproduction proof (2026-10-21, Cosmo): binaries built from these
sources are byte-identical to the toolsuite's shipped binaries,
including qruntime-v17 = b8d8172be891e947f6e11d2226d785e86f7f25f2b517fd47077848ed3f1334e4.
Note: the seed must be assembled from an object named qseed1.o —
the symbol table embeds the object filename (canonical rule from
JLSQ_V17_NATIVE_BOOTSTRAP_001).
