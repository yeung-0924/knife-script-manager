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

## 九、常见坑（避坑清单）

- **不要把 PowerShell 只读/自动变量当普通变量赋值**，否则直接抛 `Cannot overwrite variable XXX because it is read-only or constant`、脚本中断。曾踩：`$home`（用户主目录，自动变量）被误用作局部变量名 → 安装 PowerShell 7 的脚本崩溃。同理规避这些保留名：
  - `$HOME`、`$PWD`、`$PSHOME`、`$HOST`（PowerShell 7+）、`$PID`、`$PROFILE`、`$PSVERSIONTABLE`、`$EXECUTIONCONTEXT`、`$MYINVOCATION`、`$ARGS`、`$INPUT`、`$MATCHES`、`$NULL`、`$TRUE`、`$FALSE`、`$ERROR`、`$LASTEXITCODE`、`$FOREACH`。
  - PowerShell 变量名不区分大小写，`$home` 与 `$HOME` 是同一个变量——小写也中招。
  - 安全做法：局部变量用更具描述性的名字（如 `$pwshHome`、`$installDir`），避开上述保留名。
- **占位符 `_p{NAME}` 与语言自身变量不冲突**：程序只识别 `_p{}`，不会误伤 `${}`、Python f-string、`$Env:XXX` 等原生语法。
- **PowerShell 里改文件/目录属性、操作受限路径时，优先 `try/catch + ErrorActionPreference='Stop'`**，避免单步失败被静默吞掉。


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
- 必要的语言收参/包结构注释。

**用法**：复制对应模板 → 按第三节重命名 → 改写逻辑 → 在 `index.json` 注册。完整多段范例见 `../demo/hello-world/`。
