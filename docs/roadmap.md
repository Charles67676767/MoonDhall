# Roadmap

## Implemented development milestone

Portable typed core, first-class/dependent types, normalization/equivalence, arbitrary-precision numbers, interpolation, record/list operations, Optional/unions, CBOR and semantic hashes. File/stdin CLI, imports, caching, diagnostics, examples and pinned audits are available. See compatibility.md for boundaries.

## Standard completion

- Fix audited grammar, typing and normalization differences.
- Add Bytes/date/time, toMap, with, completion, type projection and record-type merge.
- Complete unresolved-import binary forms and display/escape rules.
- Integrate the official import fixture server, headers and standard cache.
- Extend regression coverage as previously failing cases become supported.

## Release and embedding

- Publish to Mooncakes after a versioned release review and registry authentication.
- Add typed conversion helpers and performance/resource measurements.
- Verify additional compiler versions.

Remaining items describe future work.
