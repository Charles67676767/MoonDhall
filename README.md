# MoonDhall

用 MoonBit 实现的 Dhall 配置语言：在生成 JSON 前检查类型，用函数和类型参数复用配置，用导入拆分文件，并用语义哈希固定依赖。

当前为 **0.1.0 开发版**。语言核心、类型检查、规范化、CBOR 和 SHA-256 均由 MoonBit 实现；文件和 HTTP 命令行由 Node.js 适配器提供。项目尚未完整兼容 Dhall 标准，也尚未发布到 Mooncakes。准确范围见 [兼容性说明](docs/compatibility.md)。

```dhall
let Port = Natural
let service = \(name : Text) -> \(port : Port) ->
  { host = "127.0.0.1", name = name, port = port }
in { api = service "api" 8080, admin = service "admin" 9090 }
```

## 安装与运行

需要 MoonBit 工具链（`moonc >= 0.10.16`）和 Node.js 20 或以上。CI 固定使用 `moonc 0.10.18+6c83a7f62`，库只依赖 MoonBit 标准库。native 后端另需 C 工具链。

```sh
git clone https://github.com/Charles67676767/MoonDhall.git
cd MoonDhall
moon build --target js --deny-warn

node scripts/moondhall.mjs json examples/services/config.dhall
node scripts/moondhall.mjs json examples/imports/main.dhall -o config.json
node scripts/moondhall.mjs check examples/polymorphic/config.dhall
node scripts/moondhall.mjs normalize --expression 'let T = Natural in \(x : T) -> x + 0'
node scripts/moondhall.mjs hash --expression '{ port = 8080 }'
```

`json`、`check`、`normalize`、`format`、`hash`、`encode`、`decode` 接受文件、`-`（标准输入）或 `--expression`。`-o FILE` 指定输出。文本使用 UTF-8；`encode` 写原始 CBOR，`decode` 读原始 CBOR。错误写入标准错误并以非零状态退出，语法和类型错误包含文件、行列及源码片段。

```sh
node scripts/moondhall.mjs encode examples/services/config.dhall -o config.dhallb
node scripts/moondhall.mjs decode config.dhallb
node scripts/moondhall.mjs --help
```

`format` 保留源文件的导入，重新输出语法；求值命令先解析依赖。`hash` 输出 64 位十六进制摘要，在导入后写成 `sha256:<摘要>`。HTTP(S) 支持相对链式导入、语义完整性校验和磁盘缓存；`--cache-dir DIR`、`--offline`、`--no-cache` 控制缓存。命中原始资源缓存后仍校验声明的语义哈希。默认目录是 `~/.cache/moondhall/imports`；清理目录可刷新未固定哈希的资源。重定向和自定义请求头尚不支持。

便携的单表达式入口也保留：

```sh
moon run cmd/main -- json 'let port = 8080 in { port = port }'
moon run cmd/main -- check '[1, 2, 3]'
moon run examples/services
```

## 能力与示例

- Bool、任意精度 Natural / Integer、Double、Text、列表、记录、Optional 和联合类型。
- 一等类型、类型别名、Type / Kind / Sort、依赖函数与类型参数，支持遮蔽变量及 `x@1`。
- 文本插值、多行文本、字段投影、点分字段、记录偏好／递归合并、列表拼接。
- 常用 Natural、Integer、Double、Text、List 内建函数，包括 fold / build。
- Alpha / beta 规范化、等价性判断、断言、核心 CBOR 编解码和语义 SHA-256。
- 本地、环境变量及 HTTP(S) 导入；导入链、循环检测、缺失回退、哈希校验与缓存。

| 使用场景 | 示例 | 运行 |
| --- | --- | --- |
| 复用多服务配置，检查端口和字段类型 | [services](examples/services/config.dhall) | `node scripts/moondhall.mjs json examples/services/config.dhall` |
| 跨文件共享默认值，选择环境并导入文本 | [imports](examples/imports/main.dhall) | `node scripts/moondhall.mjs json examples/imports/main.dhall` |
| 带类型参数的配置复用，再做折叠和索引 | [polymorphic](examples/polymorphic/config.dhall) | `node scripts/moondhall.mjs json examples/polymorphic/config.dhall` |

后两个示例附有预期 JSON，集成测试逐项核对。

## 作为库使用

目前从源码使用；首次注册表发布前不提供 `moon add` 安装指令。调用包声明：

```text
import {
  "Charles67676767/MoonDhall" @dhall,
}
```

```mbt
let json = @dhall.to_json("let Port = Natural in { port = 8080 : Port }")
let inferred = @dhall.check("\\(a : Type) -> \\(x : a) -> x")
let normal_form = @dhall.normalize("let x = 1 in x + 2")
let digest = @dhall.semantic_hash("{ port = 8080 }")
```

| API | 行为 |
| --- | --- |
| `parse` / `format` / `format_expr` | 语法树与 Dhall 文本 |
| `type_of` / `check` / `Type.display` | 类型检查与显示 |
| `normalize` / `normalize_expr` / `equivalent` | 检查闭合表达式后规范化或比较 |
| `to_json` / `json_expr` | 检查并输出 JSON，整数保留十进制精度 |
| `resolve(source, origin, sources)` | 使用宿主提供的 ImportSource 解析依赖，缺少资源时返回 MissingImport 请求 |
| `encode` / `encode_expr` / `decode` | 支持范围内的 Dhall CBOR |
| `semantic_hash` / `sha256` | 语义哈希与字节摘要 |
| `diagnostic` | Unicode 行列、源码和错误信息 |

库本身不访问网络或文件系统。宿主负责规范化资源位置、读取资源和 HTTP 策略，参见 [架构](docs/architecture.md)。低层 `alpha_normalize`、`beta_normalize` 面向规范测试和开放项处理，后者不负责类型检查。

## 测试与标准对照

```sh
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
python scripts/check_cli.py
python scripts/conformance.py
moon info
moon fmt --check
```

四个后端为 JS、native、wasm、wasm-gc。官方规范固定到 [56b0997](https://github.com/dhall-lang/dhall-lang/tree/56b0997a4800bfc815ea221529a6bb2bfd6723dc)。一致性脚本首次运行会下载该版本，需要 git 和网络。默认检查 [冻结回归清单](tests/conformance-profile.json)；完整审计使用：

```sh
python scripts/conformance.py --audit --allow-failures --report .local/upstream-audit.json
```

审计保留通过、失败和未运行项目；正常形式对照不会把预期结果再做 beta 规范化。官方导入套件需要专用服务器，目前明确标记未运行；文件及 HTTP 行为由本项目集成测试验证。[审计快照](docs/upstream-audit.json) 记录完整范围，回归清单的通过率不代表完整标准兼容。

GitHub Actions 覆盖检查、构建、四后端测试、示例、CLI、固定回归清单和完整审计，实际状态见 [Actions](https://github.com/Charles67676767/MoonDhall/actions)。

## 来源与许可证

Apache-2.0，Copyright 2026 Charles67676767。按 Dhall 规范独立实现，未调用其他 Dhall 解释器。来源、版本及许可证见 [SOURCES.md](SOURCES.md)。MoonDhall 与上游 Dhall 项目无隶属关系。
