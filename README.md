# MoonDhall

A Dhall configuration language implementation in MoonBit.

MoonDhall brings typed, reusable configuration to MoonBit applications. The initial development milestone implements a self-contained language core: parsing, type checking, evaluation, and deterministic JSON output. Full Dhall standard compatibility is a longer-term goal.

## Development

Requires MoonBit with `moonc >= 0.10.16`.

```sh
moon check
moon build
moon test
```

## License and references

Apache-2.0. Copyright 2026 Charles67676767.

Language behavior follows the [Dhall language specification](https://github.com/dhall-lang/dhall-lang/tree/master/standard). Reference implementations and the upstream conformance suite are maintained by the [Dhall project](https://github.com/dhall-lang/dhall-lang). MoonDhall is an independent implementation and is not affiliated with the Dhall project. Compatibility is documented against implemented features, not implied by the project name.
