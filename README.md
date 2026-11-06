# MoonDhall

用 MoonBit 实现的 Dhall 配置语言解释器。面向需要类型检查、函数复用和确定性配置输出的 MoonBit 应用。

当前为 **0.1.0 开发阶段的自包含语言核心**：源码解析 → 类型检查 → 求值 → JSON 输出。它已经能运行下面的配置，但尚未达到完整 Dhall 标准兼容，也未发布到 Mooncakes。

```dhall
let service = \(port : Natural) ->
  { host = "127.0.0.1", port = port, enabled = True }

in { api = service 8080, admin = service 9090 }
```

输出的 JSON 按字段名字典序排列：

```json
{"admin":{"enabled":true,"host":"127.0.0.1","port":9090},"api":{"enabled":true,"host":"127.0.0.1","port":8080}}
```

## 构建与运行

需要 MoonBit 工具链，`moonc >= 0.10.16`。当前已验证 `moonc 0.10.18+6c83a7f62`；其他版本需自行验证。JavaScript 目标需要 Node.js；native 目标需要 C 工具链。库只依赖 MoonBit 标准库。

```sh
git clone https://github.com/Charles67676767/MoonDhall.git
cd MoonDhall
moon check --deny-warn
moon build --deny-warn
moon test --deny-warn
moon run examples/services
```

命令行接受一个源码参数：

```sh
moon run cmd/main -- json 'let port = 8080 in { port = port }'
moon run cmd/main -- check '[1, 2, 3]'
moon run cmd/main -- --help
```

`json` 输出 JSON；`check` 输出类型。解析、类型、求值或命令错误以非零退出状态结束。源码作为一个参数传入；当前 CLI 不直接打开文件或读取标准输入。调用方可自行读取文件后调用库 API。

## 作为库使用

当前从源码使用；此阶段不提供尚未发布的 `moon add` 安装指令。

```mbt
let source = "let port = 8080 in { port = port }"
let config_type = @dhall.check(source)
let json = @dhall.to_json(source)
```

使用上述代码的包在 `moon.pkg` 中声明：

```text
import {
  "Charles67676767/MoonDhall" @dhall,
}
```

公共 API：

| API | 行为 |
| --- | --- |
| `parse(source)` | 返回支持范围内的表达式语法树 |
| `type_of(expr)` | 检查闭合语法树，返回类型 |
| `check(source)` | 解析并检查源码，返回类型 |
| `to_json(source)` | 完整检查后求值，生成确定性 JSON |
| `Type.display()` | 将类型转换为可读文本 |

## 当前能力

- `Bool`、`Natural`、`Text`、同质列表、记录和非依赖函数类型。
- `let`、显式类型标注、lambda、函数应用、高阶函数。
- 闭包捕获定义环境；支持变量遮蔽及 `x@1` 一类索引引用。
- `if/then/else`、自然数加乘、布尔运算、文本拼接、记录右偏合并及字段选择。
- `Natural/isZero`、`Natural/even`、`Natural/odd`、`Natural/show`。
- 嵌套块注释、行注释、Unicode 文本，以及 λ / → 写法。
- 类型检查覆盖两个条件分支；求值仅执行选中的分支。
- JSON 序列化保留 64 位自然数十进制精度，不通过浮点数转换。

详细语法范围、资源限制及后续工作见 [兼容性说明](docs/compatibility.md) 和 [路线图](docs/roadmap.md)。

## 验证

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/check_cli.py
moon info
moon fmt --check
```

测试覆盖配置复用、词法作用域、变量索引、高阶函数、记录类型、列表、Unicode、错误路径、整数溢出和嵌套限制。四个后端为 wasm、wasm-gc、js、native。CLI 集成检查另外验证 JSON、类型输出和失败退出状态。

GitHub Actions 执行检查、构建、测试和示例。此处描述检查内容，实际远端结果以 [Actions](https://github.com/Charles67676767/MoonDhall/actions) 对应提交为准。当前没有声称通过上游完整一致性测试集。

## 项目结构

```text
lexer.mbt          词法、注释与文本处理
parser.mbt         表达式与类型解析
types.mbt          公共 AST、类型和错误
typecheck.mbt     静态类型检查
evaluate.mbt       闭包求值与 JSON 序列化
core_test.mbt      公共 API 回归测试
cmd/main/          命令行入口
examples/services/ 可运行的多服务配置示例
docs/              兼容范围、架构、路线图与来源
```

## 来源与许可证

项目采用 Apache-2.0，Copyright 2026 Charles67676767。按 [Dhall 语言规范](https://github.com/dhall-lang/dhall-lang/tree/master/standard)独立实现当前语言子集，参考范围见 [SOURCES.md](SOURCES.md)。MoonDhall 与上游 Dhall 项目无隶属关系。
