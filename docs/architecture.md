# Architecture

The root package is a portable MoonBit library with only core-library dependencies. No operation delegates language processing to another interpreter.

1. The lexer records Unicode scalar offsets. Recursive-descent parsing produces one Expr tree for terms and types, retaining source spans.
2. Named variables and indices become canonical de Bruijn indices. Capture-avoiding shifting and substitution implement lexical binding and dependent type substitution.
3. Type inference uses a context of expressions. Function types are Pi expressions; application substitutes the argument into the output type. Normal forms determine type equivalence.
4. A bounded reducer performs beta normalization, builtin reductions and record/list operations. JSON consumes a checked normal form and writes integer digits directly.
5. The CBOR codec implements the supported Dhall binary forms, preferred integer/float encodings, UTF-8 validation and bounded decoding. Portable SHA-256 hashes alpha/beta-normal-form CBOR.
6. Import traversal is pure. Host-provided ImportSource entries are keyed by origin + newline + written path. MissingImport requests another entry; retries are deterministic. Canonical locations identify cycles and cached values. Imported code is checked in an empty context, preventing capture of importing-file variables. Integrity is checked on the normalized imported value.
7. cmd/bridge accepts structured stdin requests. Its single JS FFI reads stdin; language operations call the MoonBit library. scripts/moondhall.mjs supplies I/O, canonical URL resolution, raw-resource caching and output files. Remote code cannot import local resources; cross-origin requests check CORS, including cache hits. Redirects are rejected.

Application APIs check closed expressions. Low-level alpha_normalize and beta_normalize support open terms for standard testing; the latter does not infer a type. Resource limits are implementation bounds, not a process memory sandbox.

The upstream runner compares normalization output against an unnormalized expected syntax tree. Parser output uses exact CBOR; hashes use upstream digests. Binary decoding compares decoded syntax with B, accepting oversized input floats. Fixtures are downloaded with their license to an ignored directory at a pinned revision.
