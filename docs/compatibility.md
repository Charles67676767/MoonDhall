# Compatibility

MoonDhall implements a growing Dhall subset, not a complete standard-conforming implementation. APIs can change before a registry release.

## Implemented profile

- Bool; arbitrary-precision decimal, binary and hexadecimal Natural and Integer; IEEE-754 Double; double-quoted and multiline Text, interpolation, escapes and indentation removal.
- Let, annotations, lambda/application, named variable indices, first-class types, aliases, Type / Kind / Sort and dependent Pi types.
- Records and record types, dotted fields, field selection, projection by labels or type, right-biased preference and recursive merging.
- Record completion, record and Optional path updates, and conversion of homogeneous records to key/value lists.
- Bytes literals and Date, Time and TimeZone literals with the standard show functions. Fractional seconds preserve every digit.
- Homogeneous lists and annotated empty lists; Optional; unions/constructors and exhaustive merge; equivalence assertions.
- Boolean conditionals/operators, Natural arithmetic, text/list concatenation.
- Natural: isZero, even, odd, show, toInteger, subtract, fold, build.
- Integer: abs, clamp, negate, show, toDouble. Double: show. Text: show, replace.
- List: length, head, last, reverse, indexed, fold, build.
- Alpha/beta normalization, equivalence, supported-core CBOR and semantic SHA-256.
- Local, environment and HTTP(S) imports in Code, Text, Bytes and Location modes. The CLI supports inline and per-origin headers, same-origin redirects, and raw and semantic caches.

Empty record values are {=}; {} is a record type. Boolean == and != are Bool-only; === forms an equivalence type used by assert. Exact integer JSON output does not prevent downstream IEEE-754 consumers losing digits.

## Remaining standard gaps

Known gaps include grammar, normalization, type inference and semantic-hash cases listed in the pinned audit.

CBOR supports the current expression profile, including unresolved import forms, Bytes and temporal literals. Standalone untyped empty lists require an annotation. Use type_of or normalize_expr to check a decoded expression before evaluation.

The Node.js adapter follows up to five same-origin redirects. It keeps HTTP request headers on relative remote imports and checks CORS on cross-origin imports. Per-origin configuration comes from DHALL_HEADERS or dhall/headers.dhall in the XDG configuration directory. Verified hashed imports are stored as CBOR in the standard dhall subdirectory of the XDG cache. The raw resource cache is separate and bypassed for requests that carry configured headers. Library embedders supply their own host I/O and enforce the corresponding request policies.

JSON encodes Bytes as hexadecimal strings with the 0x prefix and temporal values as their Dhall text forms. These are MoonDhall JSON conversion choices.

Complex nested text lexical constructs still fail some upstream tests. Text/show uses JSON quoting, which differs from complete Dhall display rules.

## Resource limits

- Parsed source: 262144 string code units; tokens: 20000.
- Parser and inference recursion: 128; canonicalization, reducer, JSON and CBOR traversal: up to 256.
- Each normalization operation: 200000 steps; inference may perform several operations.
- Natural/fold: 10000 iterations; import ancestors: 64; CLI dependency requests: 256.
- JSON subtree and guarded concatenation: 1048576 code units; imports: 256 KiB; CLI/binary input: 1 MiB.
- CBOR bounds collections, nesting and nodes; rejects malformed UTF-8, duplicate map keys, trailing bytes and truncated input.

These are implementation limits, not standard semantics or a global memory guarantee. Diagnostics count Unicode scalar columns, not terminal display cells.

## Verification

[Manifest](../tests/upstream.json), [regression cases](../tests/conformance-profile.json), and [audit snapshot](upstream-audit.json) record the tested scope. The import audit supplies pinned local and HTTP fixtures to the resolver in memory. Separate CLI tests run a real local HTTP server and verify raw imports, headers, redirects, offline reads and semantic cache files.
