# Roadmap

## Implemented development milestone

Portable typed core, first-class/dependent types, normalization/equivalence, arbitrary-precision numbers, interpolation, record/list operations, Optional/unions, CBOR and semantic hashes. File/stdin CLI, import modes and headers, semantic caching, diagnostics, examples and pinned audits are available. The language also supports Bytes, Date, Time, TimeZone, record completion, with and toMap. See compatibility.md for boundaries.

## Standard verification

The pinned audit passes 1,525 upstream cases, including the Prelude and the import routes exercised over local HTTP and HTTPS. Future verification can extend coverage of the Node.js adapter and add more versions of the Dhall standard.

## Release and embedding

- Publish to Mooncakes after a versioned release review and registry authentication.
- Add typed conversion helpers and performance/resource measurements.
- Verify additional compiler versions.

Remaining items describe future work.
