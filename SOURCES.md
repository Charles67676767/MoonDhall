# Sources and attribution

MoonDhall's current implementation and regression tests are written independently for this project.

## Dhall specification

- Project: https://github.com/dhall-lang/dhall-lang
- Specification: https://github.com/dhall-lang/dhall-lang/tree/master/standard
- Upstream tests: https://github.com/dhall-lang/dhall-lang/tree/master/tests
- Upstream license: https://github.com/dhall-lang/dhall-lang/blob/master/LICENSE

The current reference scope is syntax, non-dependent typing behavior, named variable indices, lexical binding, primitive operator behavior and configuration examples. No upstream implementation source or test fixtures are vendored in this milestone. Reading the specification does not imply full conformance; docs/compatibility.md records the implemented profile.

Before importing upstream source code or fixtures, retain their applicable license and attribution and record their exact revision.

## Runtime

The implementation uses MoonBit core, distributed with the MoonBit toolchain under Apache-2.0. Text escape handling and JSON string escaping use the core JSON library. Numeric output is generated directly to preserve exact decimal digits.

## Project license

Apache License 2.0. Copyright 2026 Charles67676767.
