---
name: script-writer
description: 当用户（或使用本技能的 AI）需要为 ScriptManager 编写、修改、新增脚本时触发。涵盖 9 种语言（powershell/pwsh/cmd/bash/node/python/java/go/rust）的脚本编写规范、index.json 注册方式、参数占位符约定、命名/编码/颜色约定与最小模板。适用于不熟悉脚本语言的用户，借助本技能即可生成可直接被 ScriptManager 加载运行的脚本。
---

# ScriptManager 脚本编写指南（AI 辅助编写用）

本技能帮助**不熟悉脚本语言的用户**通过 AI 生成能被 ScriptManager 正确加载、运行的脚本。
ScriptManager 是一个 Windows 脚本管理器：读取 `script/index.json` 列出脚本，用户点「执行」即可运行，右侧实时显示日志。

> 本文件随 `script/` 目录一起分发给最终用户。你的 AI 只需照此规范生成脚本，并把条目写进对应的 `index.json` 即可。

---

## 一、脚本如何被加载（必须懂）

ScriptManager **只**加载 `script/index.json`（嵌套数组，用 `children` 表达目录层级）里登记过的脚本。新增脚本必须两步：

1. 把脚本文件放到 `script/` 下合适子目录（命名见第三节）。
2. 在 `index.json` 里把它作为「脚本节点」加进目标目录节点的 `children`。

### 脚本节点字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 是 | 界面显示名 |
| `path` | 是 | 相对 `script/` 根目录的路径，如 `./hyper/Set-StaticIP.ps1`（支持 `./` 前缀） |
| `lang` | 是 | 语言标识，决定用哪个运行时：`powershell` / `pwsh` / `cmd` / `bash` / `node` / `python` / `java` / `go` / `rust` |
| `admin` | 否 | `true` 时以管理员身份运行 |
| `hide` | 否 | `true` 时不在界面显示 |
| `params` | 否 | 参数数组，见下文 |

### 完整示例（加到某目录节点的 `children` 里）

```json
{
  "name": "我的脚本",
  "path": "./my-scripts/Do-Something.ps1",
  "lang": "powershell",
  "admin": false,
  "params": [
    { "name": "TARGET", "label": "目标地址", "default": "127.0.0.1", "required": true, "placeholder": "如 192.168.1.1" }
  ]
}
```

---

## 二、参数传递约定（统一，所有语言一致）

GUI 根据 `params[].name` 把用户输入代入脚本内的**占位符**，原始脚本文件不被修改。

- **占位符形式：`_p{参数名}`**——前缀 `_p` + 花括号内写参数名，如 `_p{TARGET}`、`_p{NAME}`。
- **参数名约定：全大写 + 下划线（UPPER_SNAKE_CASE）**，如 `NAME`、`TARGET_IP`。
- 运行时程序把 `_p{NAME}` **原地替换**为用户输入（未填用 `default`，仍空则用空串）。
- 硬性要求：脚本内 `_p{...}` 的名字必须与 `params[].name` **字面完全一致（含大小写）**。
- `_p{NAME}` 与脚本自身的 `${}` 语法（Bash/PowerShell 变量、Python f-string 等）**不会冲突**——程序只识别 `_p{}` 这一种形式。

示例（各语言统一写法）：

```powershell
# PowerShell / pwsh
Write-Host "Hello, _p{NAME}!"
```

```bat
@echo off
echo Hello, _p{NAME}!
```

```bash
echo "Hello, _p{NAME}!"
```

```python
print(f"Hello, _p{NAME}!")
```

```javascript
console.log(`Hello, _p{NAME}!`);
```

```java
// 单文件 Java 11+，类名须与文件名一致（见第三节）
System.out.println("Hello, _p{NAME}!");
```

```go
package main
import "fmt"
func main() { fmt.Println("Hello, _p{NAME}!") }
```

```rust
fn main() { println!("Hello, _p{NAME}!"); }
```

---

## 三、文件命名约定（按语言）

| 语言 | 扩展名 | 命名风格 | 备注 |
|---|---|---|---|
| PowerShell | `.ps1` | **PascalCase**（动词-名词） | 如 `Get-LogFile.ps1`、`Do-Something.ps1` |
| PowerShell 7 (pwsh) | `.ps1` | **PascalCase** | 同 PowerShell，`lang` 用 `pwsh` |
| CMD / Batch | `.bat` / `.cmd` | `snake_case` 或 `kebab-case` | 全小写 |
| Bash / Shell | `.sh` | `snake_case` | 如 `backup_database.sh` |
| Node.js | `.js` | `kebab-case` 或 `snake_case` | 避免驼峰 |
| Python | `.py` | `snake_case` | PEP 8 强制 |
| Java | `.java` | **PascalCase** | 文件名必须与 `public class` 名完全一致 |
| Go | `.go` | `snake_case` | 官方强制，严禁驼峰 |
| Rust | `.rs` | `snake_case` | 官方强制，严禁驼峰 |

**目录命名**：一律小写、单词间用连字符 `-`（单数），如 `color-log/`、`net-tool/`。

---

## 四、各语言「接收 -Name 参数」速查

为与 demo 保持一致，脚本建议支持 `-Name <值>` 参数（默认 `World`）。写法：

```powershell
# PowerShell / pwsh
param( [string]$Name = "World" )
Write-Host "Hello, $Name!"
```

```bat
@echo off
set "NAME=World"
:parse
if "%~1"=="" goto done
if /i "%~1"=="-Name" ( set "NAME=%~2" & shift & shift & goto parse )
shift & goto parse
:done
echo Hello, %NAME%!
```

```bash
NAME="World"
while [[ $# -gt 0 ]]; do
  case "$1" in -Name) NAME="$2"; shift 2;; *) shift;; esac
done
echo "Hello, $NAME!"
```

```python
import argparse
p = argparse.ArgumentParser()
p.add_argument("-Name", default="World")
args = p.parse_args()
print(f"Hello, {args.Name}!")
```

```javascript
function parseArgs(a){const r={Name:"World"};for(let i=0;i<a.length;i++){if(a[i]==="-Name"&&i+1<a.length){r.Name=a[i+1];i++}}return r}
const args=parseArgs(process.argv.slice(2));
console.log(`Hello, ${args.Name}!`);
```

```java
// 文件名须与类名一致，如 MyScript.java → public class MyScript
public class MyScript {
    public static void main(String[] a){
        String name="_p{NAME}";
        System.out.println("Hello, "+name+"!");
    }
}
```

```go
package main
import ("fmt";"os")
func main(){
    name:="World"
    a:=os.Args[1:]
    for i:=0;i<len(a);i++{ if a[i]=="-Name"&&i+1<len(a){name=a[i+1];i++} }
    fmt.Printf("Hello, %s!\n", name)
}
```

```rust
use std::env;
fn main(){
    let a: Vec<String>=env::args().skip(1).collect();
    let mut name="World".to_string();
    let mut i=0;
    while i<a.len(){ if a[i]=="-Name"&&i+1<a.len(){name=a[i+1].clone();i+=2}else{i+=1} }
    println!("Hello, {}!", name);
}
```

---

## 五、段标题约定（推荐，便于阅读日志）

每个脚本建议按「段落」组织，每段开头用注释标明段名，并**输出到控制台**一行段标题，方便用户在日志面板区分。后续追加内容时照此格式即可：

```text
# / // 注释：===== 段名 =====
输出：===== 段名 =====
```

示例（PowerShell）：

```powershell
Write-Host "===== Hello, World ====="
Write-Host "Hello, _p{NAME}!"

Write-Host "===== 多色日志 ====="
# 此处输出彩色日志……
```

完整范例见同包 `demo/hello-world/` 下的各语言脚本（已采用此约定）。

---

## 六、ANSI 颜色约定（可选，做状态提示时用）

日志面板支持 ANSI 转义。约定配色：

- **入参**：亮绿 `\x1b[92m`
- **信息**：亮黄 `\x1b[93m`
- **异常**：亮红 `\x1b[91m`
- 重置：`\x1b[0m`

示例（Go）：

```go
const ( esc="\x1b"; green=esc+"[92m"; yellow=esc+"[93m"; red=esc+"[91m"; reset=esc+"[0m" )
fmt.Printf("%s[入参]%s name = %s%s\n", green, reset, name, reset)
```

---

## 七、编码约定（编写侧无需特殊处理）

- 脚本**源文件**：UTF-8 无 BOM（统一规范，照此写即可）。
- 执行临时文件：PowerShell / pwsh 由程序自动转 **UTF-8 带 BOM**；其余语言保持 UTF-8 无 BOM。源文件永远不被修改。
- CMD 的中文乱码由程序运行前自动改写处理，编写侧照常用 UTF-8 无 BOM 写、中文随意写即可。

---

## 八、最小模板（直接复制改）

以 PowerShell 为例，一个可被 ScriptManager 运行的完整脚本：

```powershell
# 我的脚本
param( [string]$Name = "World" )

Write-Host "===== Hello, World ====="
Write-Host "Hello, $Name!"
Write-Host "接收参数 Name = $Name"
```

对应 `index.json` 条目：

```json
{
  "name": "我的脚本",
  "path": "./my-scripts/My-Script.ps1",
  "lang": "powershell",
  "params": [ { "name": "NAME", "label": "问候对象", "default": "World", "required": false } ]
}
```

> 更完整的多语言范例在本包 `demo/hello-world/` 目录下，可直接参考其结构编写其他语言的脚本。

---

## 九、新增脚本步骤（检查清单）

1. 决定语言 → 按第三节命名文件，放到 `script/` 下合适子目录。
2. 按第二节 / 第四节写好脚本（支持 `_p{参数名}` 占位符；可选加第五节段标题）。
3. 在对应 `index.json` 的目录节点 `children` 里加脚本节点（`name`/`path`/`lang`/`params`）。
4. 用户在程序里点「刷新」即可看到新脚本，无需重新构建。

---

## 十、随包模板（直接复制改）

本目录下的 `templates/` 已提供 9 种语言的**最小骨架**，文件名 `tpl_<语言>.<扩展名>`：

| 文件 | 语言 |
|---|---|
| `templates/tpl_powershell.ps1` | PowerShell |
| `templates/tpl_pwsh.ps1` | PowerShell 7 |
| `templates/tpl_cmd.bat` | CMD / Batch |
| `templates/tpl_bash.sh` | Bash |
| `templates/tpl_node.js` | Node.js |
| `templates/tpl_python.py` | Python |
| `templates/tpl_java.java` | Java |
| `templates/tpl_go.go` | Go |
| `templates/tpl_rust.rs` | Rust |

每个模板均包含：
- 一个 `===== Hello, World =====` 段标题（控制台可见，遵循第五节约定）；
- 一行用 `_p{NAME}` 占位符的问候（运行前由程序替换）；
- 一行 `# 更新时间: YYYY-MM-DD HH:MM:SS`（位于文件头部，见第十一节；**从模板生成新脚本时把时间改为当前时刻**）；
- 必要的语言收参/包结构注释。

**用法**：复制对应模板 → 按第三节重命名 → 改写逻辑 → 在 `index.json` 注册。完整多段范例见 `../demo/hello-world/`。

---

## 十一、脚本头部必须标注「更新时间」（强制）

每个脚本文件头部**必须**包含一行「更新时间」注释，格式：`<注释符> 更新时间: YYYY-MM-DD HH:MM:SS`（如 `# 更新时间: 2026-09-04 14:59:35`）。时间用 24 小时制、本地时间（中国时区）、精确到秒，以便精确定位脚本版本新旧。

- **作用**：用户贴错误日志时，AI 可通过脚本头部更新时间判断其运行的脚本是否为最新版本，快速区分「脚本太旧、没更新」还是「真有 bug」——避免反复在旧脚本上排错。
- **位置规则（关键，避免破坏首行约束）**：
  - 无首行特殊要求的语言（PowerShell / pwsh / 无 shebang 的 Python / 普通脚本）：放在**文件第一行**（即第一个注释行）。
  - 有 shebang 的脚本（`#!/usr/bin/env bash`、`#!/usr/bin/env python3`、`#!/usr/bin/env node` 等以 `#!` 开头）：`#!` 必须留第一行，更新时间放**第二行**（第一个注释行），注释符用 `#`。
  - CMD / Batch（`@echo off` 起手）：`@echo off` 留第一行，更新时间放第二行，注释符用 `rem`。
  - Go（`package main` 起手）：`package` 行之后（第二行）加 `// 更新时间: ...`。
  - Java / Rust / Node / C 等以 `//` 注释或 `fn` / `public class` 起手（非 shebang）：更新时间作为**第一个注释行**（通常即文件第一行），注释符用 `//`。
- **更新纪律**：每次修改脚本逻辑后，**必须**把这行时间戳改为当前时刻（精确到秒）；仅改注释/文案也建议顺手更新。
- **只标日期、不写改动内容（重要）**：头部只保留「更新时间: 时间戳（到秒）」这一行，**严禁**在脚本里追加「本次改了什么 / 改动说明 / changelog」之类的注释。理由：发版后用户能看到脚本，日期戳已足够让 AI 判断版本新旧，而改动说明会暴露你改过什么。需要沉淀的是「坑」（见第十二节，属内部 AI 文档），不是「本次改了啥」。
- **模板已内置**：`templates/tpl_*.xx` 已带该行，从模板生成新脚本时把日期改为当天即可。
- 该规则对 9 种语言一致执行，不得遗漏。
- **控制台也须打印更新时间（强制）**：除头部注释外，脚本运行时必须在标题横幅（如 `Say '====...'` / `echo` 横幅）**之后、入参打印之前**，用一行把更新时间打到 stdout。示例（PowerShell）：
  ```powershell
  # 从脚本自身首行注释解析「更新时间」并打印（不硬编码，避免与注释脱节）
  $updateTime = ''
  try {
      $sp = $PSCommandPath; if ([string]::IsNullOrWhiteSpace($sp)) { $sp = $MyInvocation.MyCommand.Path }
      if (-not [string]::IsNullOrWhiteSpace($sp)) {
          $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
          if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { $updateTime = $Matches[1].Trim() }
      }
  } catch { }
  if (-not [string]::IsNullOrWhiteSpace($updateTime)) { SayC $YELLOW '信息' "更新时间: $updateTime" }
  ```
  其它语言同理：用各自方式读取首行注释里的 `更新时间:` 并原样输出一行。**目的**：用户贴错误日志时，AI 无需对照文件、直接从日志里就能读到脚本版本时间，立刻判断其运行的脚本是否为最新。模板 `templates/tpl_*.xx`（含 cmd/bash/node/python/go/rust 等非 PowerShell 语言）均已内置等价打印段，新脚本直接复用：解释型语言从 `$0` / `__file__` 等读自身源码解析；编译型语言（Go / Rust）运行时源码已被写成随机临时文件（ScriptManager 用 `se_script_*.go` / `se_script_*.rs` 经 `go run` / `rustc` 执行），故不能用固定文件名 `//go:embed` / `include_str!`，改为 Go 用 `runtime.Caller(0)` 取自身源码路径、Rust 用 `std::env::current_exe()` 定位同目录同名 `.rs` 源码来解析「更新时间」。两者均不依赖文件真实名字，改名或随机名都照常工作。

---

## 十二、常见坑（踩坑沉淀 —— 编写 / 调试脚本时务必持续补充）

> 本节能帮**用户自己的 AI**（以及后续会话）直接避开已踩过的雷。每当你在编写或排查脚本时遇到新坑，立刻补一条到这里，格式：`现象 → 原因 → 正确写法`。

1. **PowerShell 自动变量只读，不能赋值**：`$HOME`、`$PWD`、`$PSHOME`、`$HOST`、`$PID` 等为只读/常量，赋值会抛 `Cannot overwrite variable X because it is read-only or constant`。需要自定义变量时改用其它名字（如用 `$pwshHome` 而非 `$home`）。
2. **函数内 `exit 1` 会终止整个脚本进程**：PowerShell 中，以 `$x = Func` 方式调用函数时，函数体里的 `exit 1` 不只是退出函数，而是**直接终止整个脚本进程**（已实测验证）。错误分支应改用 `return $null` / `return` 把控制权交回调用处，由主流程统一判空收口，**不要拿 `exit` 当 return 用**。
3. **PowerShell 7 经 WinGet 安装：`winget.exe` 在管理员提权 / 非交互环境常不在 PATH**：它是 App Execution Alias，定位除 `Get-Command winget.exe` 外，需回退到 `$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe`；更稳妥可回退到 `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64*\winget.exe` 真实二进制。安装用 `--scope machine` 才会落入 `C:\Program Files\PowerShell`；每用户安装则在 `LocalAppData\Microsoft\PowerShell`，查找 `pwsh.exe` 时两者都要覆盖。
4. **「null 守卫」里直接 `Join-Path $null` 会自爆**：判空之前，不要在同一个 `if` 条件里对可能为空的值调用 `Join-Path` / `Test-Path` 之类带参数绑定的命令。正确写法：先 `if ([string]::IsNullOrWhiteSpace($x)) { 报错收口 }`，通过后再 `Join-Path $x ...`。否则 `$x` 为 `$null` 时 `Join-Path $x` 抛 `Cannot bind argument to parameter 'Path' because it is null`，反而成了新的崩溃点。
5. **国内网络：GitHub API / raw.githubusercontent 易墙**：原 GitHub 源先调 `api.github.com` 查版本会卡死 / 超时。改为直接用「大版本.0」（如 7.5 → 7.5.0）拼下载链接，并加 `ghproxy` 镜像（`https://mirror.ghproxy.com/https://...`）回退；下载失败给出「github.com 可达性」诊断，而非含糊的空值崩溃。
6. **编码：脚本源文件一律 UTF-8 无 BOM**（与 IDEA 统一）；程序侧 `EncodingHelper` 检测 + `.NET File.ReadAllText` 已兼容无 BOM 与带 BOM 两种，脚本侧无需特殊处理。注意 AI 生成文件也要保持无 BOM，否则中文 Windows + GBK 解析会误报语法错误。
7. **（来自 `src/CmdScriptRewriter.cs` 的实机坑）CMD 中文重写必须逐行全覆盖**：程序对 CMD 中文做编码重写时要逐行处理、不能跳过注释行，否则会漏改导致乱码。
8. **Go / Rust 模板不能用固定文件名 `//go:embed` / `include_str!` 内嵌自身源码来打印「更新时间」**：ScriptManager 运行时会把脚本写成随机临时文件 `se_script_{Guid}.go` / `se_script_{Guid}.rs`（见 `MainViewModel.cs` 的 `Path.GetTempPath()` + `LangToTempExt`），再 `go run` / `rustc` 执行。embed/include_str! 的文件名在编译期就必须存在，而临时文件名是随机 GUID，必然报「no matching files / cannot find file」。正确写法：Go 用 `runtime.Caller(0)` 取自身源码路径再解析；Rust 用 `std::env::current_exe().with_extension("rs")` 定位同目录同名 `.rs` 源码（并兜底扫描 exe 所在目录所有 `.rs`）。两者均不依赖文件真实名字，改名 / 随机名都照常工作。

