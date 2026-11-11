# Roadmap

## Implemented development milestone

Portable typed core, first-class/dependent types, normalization/equivalence, arbitrary-precision numbers, interpolation, record/list operations, Optional/unions, CBOR and semantic hashes. File/stdin CLI, import modes and headers, semantic caching, diagnostics, examples and pinned audits are available. The language also supports Bytes, Date, Time, TimeZone, record completion, with and toMap. See compatibility.md for boundaries.

## Standard completion

- Fix audited grammar, typing and normalization differences.
- Complete the remaining display and escape rules.
- Verify parser and normalization edge cases around imports and test the host against the upstream HTTP and HTTPS fixture server.
- Extend regression coverage as previously failing cases become supported.

## Release and embedding

- Publish to Mooncakes after a versioned release review and registry authentication.
- Add typed conversion helpers and performance/resource measurements.
- Verify additional compiler versions.

Remaining items describe future work.
