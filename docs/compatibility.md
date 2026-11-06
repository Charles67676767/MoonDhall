# Compatibility

MoonDhall currently implements a self-contained subset of Dhall, not a conforming complete implementation. The public API may change before a first registry release.

## Implemented syntax

- Bool literals, decimal Naturals, double-quoted Text with JSON-compatible escapes.
- let bindings, optional let annotations, expression annotations.
- Typed lambda parameters and function application, including higher-order functions.
- Non-dependent function types, record types, and List types.
- Record literals, field selection, and right-biased record preference.
- Homogeneous lists; empty lists require an annotation.
- if / then / else; both branches are type-checked.
- Operators: ||, ++, +, &&, //, *, ==, !=. Equality and inequality are Bool-only.
- Four Natural builtins: isZero, even, odd, show.
- Named variable indices, line comments, and nested block comments.

An empty record value is written {=}; {} is a record type, not a record value. Types are accepted in annotations and lambda parameters, but are not first-class expression values in this milestone. Record type fields and JSON fields use lexical name order.

## Explicitly outside this milestone

- Local, environment, HTTP(S), hashed, or fallback imports.
- Type / Kind / Sort universes, dependent functions, polymorphic type arguments, and type aliases.
- Integer, Double, Bytes, Date, Time, TimeZone, Optional, unions, merge, and assertions.
- Text interpolation, multiline Text, backtick labels, dotted field sugar, and duplicate field merging.
- Record projection, recursive record merge, list concatenation and most standard builtins.
- Public expression normalization, alpha-normalization, CBOR, and semantic hashing.
- Arbitrary-precision Naturals: the supported range is 0 through 9223372036854775807.

Unsupported features raise an error or are treated as unbound identifiers; they are never delegated to an external interpreter. There is no network or filesystem access in the evaluator.

## Resource and representation limits

- Source: at most 262144 UTF-16 code units.
- Tokens: at most 20000, excluding the final end marker.
- Parser, type checker, evaluation and JSON traversal have depth limits of 128 (the parser counts its nested expression/type entry points).
- Evaluation and JSON traversal share a 100000-step budget.
- Concatenated Text and each serialized JSON subtree are capped at 1048576 UTF-16 code units.
- Natural literal and arithmetic overflow produces an explicit error.

These are implementation limits, not part of the Dhall specification and not a general memory-isolation guarantee. Syntax error offsets count Unicode scalar values from the beginning of the source.

JSON emits exact Natural decimal digits. Consumers that parse numbers through IEEE-754 doubles may still lose precision above 2^53.

## Verification status

The current tests are independently written regression examples and negative cases. They do not constitute the upstream Dhall conformance suite. Full compatibility claims will require a pinned standard revision, a published upstream test manifest and explicit pass/fail/unsupported results.
