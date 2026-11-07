# Sources and attribution

MoonDhall code and project-specific regression tests are independently implemented. No operation invokes or embeds another Dhall interpreter.

## Dhall specification and acceptance tests

- Repository: https://github.com/dhall-lang/dhall-lang
- Revision: 56b0997a4800bfc815ea221529a6bb2bfd6723dc
- Specification: https://github.com/dhall-lang/dhall-lang/tree/56b0997a4800bfc815ea221529a6bb2bfd6723dc/standard
- Tests: https://github.com/dhall-lang/dhall-lang/tree/56b0997a4800bfc815ea221529a6bb2bfd6723dc/tests
- BSD-3-Clause license: https://github.com/dhall-lang/dhall-lang/blob/56b0997a4800bfc815ea221529a6bb2bfd6723dc/LICENSE

Reference scope includes grammar, substitution, universes/dependent typing, normalization, imports, binary encoding and hashes. The runner downloads upstream with its license intact to ignored .local/dhall-standard. Fixtures and upstream implementation sources are not vendored; committed manifests contain case paths and outcomes only. Actual compatibility is recorded in docs/compatibility.md and docs/upstream-audit.json.

## Runtime and hashing

MoonBit core is distributed with the toolchain under Apache-2.0. The project uses bigint, float, JSON, UTF-8 and string facilities. SHA-256 is independently implemented from FIPS 180-4, including its standard initial values and round constants: https://csrc.nist.gov/pubs/fips/180-4/upd1/final

Node.js provides host I/O. Its crypto API names URL cache files only; semantic hashing is implemented in MoonBit.

## Project license

Apache License 2.0. Copyright 2026 Charles67676767.
