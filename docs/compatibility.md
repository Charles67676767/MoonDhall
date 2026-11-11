# Compatibility

MoonDhall implements a growing Dhall subset, not a complete standard-conforming implementation. APIs can change before a registry release.

## Implemented profile

- Bool; decimal arbitrary-precision Natural and Integer; IEEE-754 Double; double-quoted and multiline Text, interpolation, escapes and indentation removal.
- Let, annotations, lambda/application, named variable indices, first-class types, aliases, Type / Kind / Sort and dependent Pi types.
- Records/types, dotted field sugar, field selection, label projection, right-biased preference and recursive record-value merge.
- Record completion, record and Optional updates with with, and homogeneous record conversion with toMap.
- Homogeneous lists and annotated empty lists; Optional; unions/constructors and exhaustive merge; equivalence assertions.
- Boolean conditionals/operators, Natural arithmetic, text/list concatenation.
- Natural: isZero, even, odd, show, toInteger, subtract, fold, build.
- Integer: abs, clamp, negate, show, toDouble. Double: show. Text: show, replace.
- List: length, head, last, reverse, indexed, fold, build.
- Alpha/beta normalization, equivalence, supported-core CBOR and semantic SHA-256.
- Host-supplied local/environment/HTTP(S) imports, text imports, relative chains, cycle detection, unavailable-resource fallback, integrity checks and caches.

Empty record values are {=}; {} is a record type. Boolean == and != are Bool-only; === forms an equivalence type used by assert. Exact integer JSON output does not prevent downstream IEEE-754 consumers losing digits.

## Remaining standard gaps

Known gaps include Bytes/Date/Time/TimeZone, binary/hex numbers, recursive record-type merge, projection by type, grammar/escape/normalization edge cases and some typing rules. Unsupported builtin names may parse as free variables before type checking rejects them.

CBOR covers the implemented expression profile, excluding unresolved imports, Bytes/date/time forms and other extensions. Standalone untyped empty lists cannot be encoded. Decoding does not imply a well-typed term: call type_of or normalize_expr before evaluation.

Location imports, raw Bytes imports, custom HTTP headers, redirects and the standard semantic-cache layout are not implemented. CLI caching stores raw resources by URL and validates declared hashes after every resolution, including hits. Offline mode uses local resources and cached remote text. CORS and remote-to-local checks are host responsibilities for library embedders.

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

[Manifest](../tests/upstream.json), [regression cases](../tests/conformance-profile.json), and [complete audit snapshot](upstream-audit.json) record exact scope. The default profile freezes currently passing cases; full audit results measure compatibility. Official import tests remain unrun until their custom HTTP/CORS/header/cache fixture environment is integrated. Separate CLI tests exercise real local/HTTP I/O.
