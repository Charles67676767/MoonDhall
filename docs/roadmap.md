# Roadmap

## Current milestone: self-contained configuration core

Parsing, a non-dependent type checker, lexical closures, deterministic JSON, a CLI, runnable examples and regression tests. See compatibility.md for exact boundaries.

## Standard alignment

- Pin a Dhall standard revision and add a reproducible conformance test runner.
- Expand syntax and builtins based on that test manifest.
- Add first-class types, dependent function types and normalization/equivalence.
- Add Integer, Double, Optional, unions and interpolation.
- Publish the current supported profile and registry package only after release checks.

## Imports and distribution

- Host-provided local and remote import resolvers with explicit policies.
- Import caching, integrity checks and standard import semantics.
- CBOR encoding, alpha-normalization and semantic hashing.
- File/stdin CLI interfaces and improved source diagnostics.

## Embedding and usability

- Typed conversion helpers for MoonBit applications.
- Larger application configuration examples.
- Measured performance and resource-use reporting.

These items describe planned work, not functionality available in the current version.
