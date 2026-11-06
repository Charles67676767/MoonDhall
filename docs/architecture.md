# Architecture

The root package is a portable MoonBit library. It has no third-party runtime dependencies and does not call another Dhall interpreter.

1. The lexer produces tokens with Unicode scalar offsets and handles nested comments and text escapes.
2. The recursive-descent parser produces an Expr tree. Operator parsing uses precedence; applications and projections bind tightly.
3. The type checker walks the complete expression under a lexical type environment. Record types are canonicalized by field name.
4. The evaluator represents functions as lexical closures. Each closure captures its definition environment; application extends that captured environment. Named indices resolve shadowed variables without textual substitution.
5. The JSON writer walks evaluated values, sorts record fields, escapes Text through the standard JSON library, and writes Naturals directly as decimal integers.

The public entry points separate syntax inspection, type checking and checked JSON evaluation. Function values can be type-checked but cannot be serialized to JSON.

The command-line entry point receives one expression argument and invokes the same API used by applications. The service example exercises function reuse and nested records.

Later import resolution should be a distinct layer with an explicit host-provided resolver. Network policy and filesystem policy must remain under the embedding application's control.
