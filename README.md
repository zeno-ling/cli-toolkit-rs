# cli-toolkit-rs

cli-toolkit 的 Rust 单二进制 multicall 重写，架构照 [uutils/coreutils](https://github.com/uutils/coreutils)：一个二进制内含 16 个 applet，靠 `argv[0]` 或显式子命令分发。

## One-line install（Windows）

```powershell
irm https://v6.gh-proxy.org/https://raw.githubusercontent.com/zeno-ling/cli-toolkit-rs/main/cli-toolkit-rs/install.ps1 | iex
```

默认装到 `$env:LOCALAPPDATA\cli-toolkit-rs` 并加入用户 PATH；重开终端后可用 `cli-toolkit --list`、`tb-hash <file>`。离线 / 指定版本 / 卸载见 [`cli-toolkit-rs/install.ps1`](cli-toolkit-rs/install.ps1)。

## 构建

```powershell
cd D:\Desktop\dsh\cli-toolkit-rs
cargo build --release
# 产物：target\release\cli-toolkit.exe（约 2.6 MB，LTO + strip；含 sysinfo）
```

## 两种调用方式（uutils 风格）

```powershell
# 1. 显式子命令：cli-toolkit <applet> [args]
cli-toolkit hash Cargo.toml
cli-toolkit toolcheck rg fd nu

# 2. argv[0] 模式：给每个 applet 建 tb-<applet> 链接
cli-toolkit install D:\bin     # Windows 优先硬链接，失败退符号链接
tb-hash Cargo.toml             # 由 argv[0]=tb-hash 分发到 hash applet
tb-fg -e toml .                # 透传给 fd

# 3. 元命令
cli-toolkit --list             # 列出全部 applet
cli-toolkit --help             # 帮助
```

## Applet 清单（16 个）

| Applet | 说明 | 实现状态 |
|---|---|---|
| `hash` | SHA-256（内置 sha2，不依赖外部命令） | 内置 |
| `toolcheck` | 清点工具可用性 + 版本 | 内置 |
| `install` | 安装 tb-\<applet\> 链接 | 内置 |
| `fg` | 递归列文件（内置 fd 风格，可选 fzf 交互） | 内置 |
| `fgr` | 递归搜内容（内置 rg -n 风格，可选 fzf 交互） | 内置 |
| `fcd` | 常用目录（自建 JSON frecency，`--add` 增权，兼容 zoxide query） | 内置 |
| `dupes` | 按内容 SHA-256 找重复文件 | 内置（含 `--json` / `--hidden` / `--min-bytes`） |
| `big` | 目录/文件体积排行（内置递归统计，兼容 dust 风格） | 内置 |
| `disk` | 磁盘占用（内置 sysinfo，`--json`） | 内置 |
| `ps` | 进程列表（内置 sysinfo，`[pattern]` + `--top N`） | 内置 |
| `json` | 查询 JSON（内置 serde_json + jq 风格路径子集） | 内置 |
| `yaml` | 查询 YAML（内置 serde_yaml，先转 Value 再走路径） | 内置 |
| `replace` | 安全替换：默认预览命中行，`--apply` 才真替换（内置正则 + 字面量模式） | 内置 |
| `bench` | 基准测试（内置 Instant 计时，兼容 `--warmup` / `--runs`） | 内置 |
| `tree` | 目录树（内置递归渲染，非 TUI，支持 `--depth`） | 内置 |
| `nu` | 执行结构化管道（透传 `nu -c`，脚本运行时无法内置） | 透传 |

## json / yaml 用法（内置实现）

兼容原 `tb-json [file, filter="."]` / `tb-yaml [file, filter="."]`：文件在前、filter 在后，默认 `"."`，`file` 传 `-` 表 stdin。内置实现不依赖外部 jq/yq，支持 jq 风格路径子集：`.` / `.foo` / `.foo.bar` / `.[0]` / `.foo[0]` / `.[\"a b\"]` / `.x[]` / `.[]`，缺键返回 `null`。用 `-c/--compact` 单行紧凑输出。

```powershell
cli-toolkit json data.json .nested.a -c        # → 1
cli-toolkit json data.json ".items[]" -c       # 迭代数组，每项一行
Get-Content data.json -Raw | cli-toolkit json - -c
cli-toolkit yaml cfg.yaml .server.port -c
tb-yaml cfg.yaml ".list[]"                     # argv[0] 模式
```

## fg / fgr 用法（内置实现）

兼容原 `tb-fg [pattern?=".", --list]`（toolbox.nu:19-24）与 `tb-fgr [pattern, --list]`（toolbox.nu:27-31），**不依赖外部 fd/rg**：`fg` 递归列文件（默认含隐藏项、排除 `.git`/`target`/`node_modules`，`-e` 按扩展名过滤），`fgr` 递归搜内容（`路径:行号:行` 输出，支持正则、`-i` 忽略大小写、`-g '*.rs'` glob 过滤、`--files-with-matches` 仅列文件）。两者缺省走 `--list` 输出；若检测到 fzf 且未加 `--list`，则透传 fzf 交互选择（预览交给 fzf 自身配置）。

```powershell
cli-toolkit fg D:\proj --list            # 列文件（含隐藏、排除 .git）
cli-toolkit fg D:\proj --list -e rs      # 只看 .rs
cli-toolkit fgr TODO D:\proj --list      # rg -n 风格匹配行
cli-toolkit fgr todo D:\proj --list -i -g "*.rs"
cli-toolkit fgr TODO D:\proj --list --files-with-matches   # 仅列文件名
tb-fgr TODO --list                       # argv[0] 模式
```

## dupes 用法（内置实现）

兼容原 `tb-dupes [path]`：按文件内容 SHA-256 分组，只输出重复组（count>1），默认跳过隐藏文件、`target/`、`node_modules/` 与空文件。

```powershell
cli-toolkit dupes D:\proj                  # 表格输出
cli-toolkit dupes D:\proj --json           # JSON（scanned/skipped/groups）
cli-toolkit dupes . --hidden --min-bytes 100
tb-dupes D:\proj                           # argv[0] 模式
```

## replace 用法（内置实现）

兼容原 `tb-replace [pattern, replacement, path=".", --apply]`（toolbox.nu:79-80）：**默认只预览**（`rg -n` 风格 `路径:行号:行内容`），加 `--apply` 才真替换。默认正则匹配（对齐 rg/sd），`-s/--string-mode` 切字面量（PATTERN 与 REPLACEMENT 都按普通字符串，保留 `$1` 等符号）。正则模式支持 `$1` 捕获组。目录遍历默认跳过隐藏项、`target/`、`node_modules/`，`--hidden` 可包含；只写 UTF-8 文件，无匹配不写盘（保留 mtime）。

```powershell
cli-toolkit replace "foo (\d+)" 'hit:$1' D:\proj        # 预览命中行
cli-toolkit replace "foo (\d+)" 'hit:$1' D:\proj --apply # 捕获组替换
cli-toolkit replace "a.b" 'price $1' file.txt -s --apply # 字面量：$1 原样保留
tb-replace old new . --apply                            # argv[0] 模式
```

## fcd / bench / tree / big / disk / ps 用法（内置实现）

本轮把最后一批透传 applet 全部内置，只保留 `nu`（脚本运行时本身）：

```powershell
# fcd：常用目录，自建 JSON 库（默认 $HOME/.cli-toolkit/frecency.json，
#      可用 $env:CLI_TOOLKIT_HOME 改到隔离目录，便于沙箱/CI）
cli-toolkit fcd --add D:\proj           # 访问并加权（上限 1000）
cli-toolkit fcd proj                    # 子串过滤
cli-toolkit fcd --list                  # 按权重降序，带分数

# bench：反复执行命令并统计耗时（内置 Instant，不再依赖 hyperfine）
cli-toolkit bench cmd /c echo hi --warmup 2 --runs 10

# tree：静态缩进目录树（非 TUI；跳过 .git/target/node_modules）
cli-toolkit tree . --depth 2

# big：体积排行（不再依赖 dust）
cli-toolkit big D:\proj 10              # 只看一级
cli-toolkit big D:\proj 10 --recursive  # 递归所有层

# disk / ps（内置 sysinfo）
cli-toolkit disk                        # 表格；--json 出结构化
cli-toolkit ps node --top 5             # 名称过滤 + CPU 排序
```

## 架构

```
src/
  main.rs             入口：process::exit(dispatch::run())
  applet.rs           Applet 注册表（函数指针表：command + run）
  dispatch.rs         argv[0] 归一化 + 显式子命令双模式分发
  applets/
    mod.rs            applet 模块汇总；macro_rules! external_applet! 薄包装
    external.rs       spawn 外部工具 + 退出码透传
    hash.rs           内置 SHA-256（sha2 crate）
    toolcheck.rs      内置工具清点
    install.rs        内置链接安装（Windows 硬链接 → 符号链接回退）
    json.rs           JSON 查询（薄包装 value_query + serde_json 解析）
    yaml.rs           YAML 查询（薄包装 value_query + serde_yaml 解析）
    value_query.rs    json/yaml 共享：jq 风格路径解析 + RFC 6901 转义 + 读取/查询
    dupes.rs          内置内容 SHA-256 重复文件分组
    replace.rs        内置安全替换（预览 + --apply 替换，正则/字面量）
    fg.rs             内置列文件（fd 风格过滤，可选 fzf）
    fgr.rs            内置内容搜索（rg -n 风格，glob/忽略大小写，可选 fzf）
    fcd.rs            内置常用目录（JSON frecency，CLI_TOOLKIT_HOME 覆盖库路径）
    format.rs         共享：human_bytes + stats（均值/min/max/标准差）
    big.rs            内置体积排行（递归目录大小）
    ps.rs / disk.rs   内置进程/磁盘（sysinfo）
    bench.rs          内置计时基准（Instant）
    tree.rs           内置静态目录树
    nu.rs             透传 nu -c（保留）
```

参考了 [clap multicall-busybox 示例](https://github.com/clap-rs/clap/blob/master/examples/multicall-busybox.rs) 与 [uutils multicall 文档](https://uutils.org/coreutils/docs/multicall.html)。

## 测试

```powershell
cargo test   # 47 passed
```

覆盖：SHA-256 NIST 向量（字节 + 文件）、注册表唯一性、Command 构造、argv[0] 归一化、分发错误码、install 参数解析、dupes 内容分组/隐藏文件/最小字节/参数兼容、json/yaml 参数兼容与查询（路径/迭代/RFC 6901 转义/缺键/stdin）、value_query 路径解析与迭代器形态、replace 参数兼容/预览行号/捕获组/字面量 `$` 保留/目录遍历过滤、fg 扩展名过滤与 .git 排除、fgr glob/忽略大小写/目录排除、format 字节换算与统计、fcd/bench/tree/big/disk/ps 参数兼容与纯逻辑（目录大小累加/忽略目录判定）。

## 已知边界

- `nu` 仍是薄包装透传（脚本运行时本身无法内置）。其余 applet 全部内置，不再依赖外部工具。
- Windows 硬链接要求同一卷；跨卷时自动回退符号链接（可能需要开发者模式/管理员）。
- 二进制更新后旧硬链接仍指向旧 inode，需重跑 `cli-toolkit install <dir> --force`。
- `fcd` 默认库在 `$HOME/.cli-toolkit/frecency.json`；沙箱/CI 下 HOME 不可写时用 `$env:CLI_TOOLKIT_HOME` 指到可写目录。
- `ps`/`disk` 用 sysinfo，CPU% 是两次采样（间隔 120ms）的差值，短命进程可能显示 0。
- `tree`/`big` 跳过 `.git`/`target`/`node_modules`，不是完整文件树。
