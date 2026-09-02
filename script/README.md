# ScriptManager 脚本说明

本目录包含两类脚本：

- **`internal/`**：内置脚本，编译时嵌入 `ScriptManager.exe` 内部，随程序版本发布，普通用户无需修改。
- **`external/`**：自定义脚本，会显示在程序左侧「自定义脚本」分类下。程序首次启动时会解包到 `ScriptManager.exe` 同级 `Script/external/` 目录；你也可以直接在解包后的目录里增删改，**点界面上的「刷新」按钮即可重新加载，无需重启程序**。

> 本 README 会随打包复制到交付目录 `Script/README.md`。

---

## 一、使用方式

1. 启动 `ScriptManager.exe`，左侧树展开「自定义脚本」。
2. 点击某个脚本 → 右侧出现参数面板（若脚本有 `params`）和预览。
3. 填写/确认参数，点击左上角「执行」运行；运行时按钮变为红色「停止」，可强制终止进程。
4. 需要调整脚本内容或新增脚本：直接在 `Script/external/` 下编辑或新增文件，然后点「刷新」即可看到更新。
5. 点「导出」会把当前 `Script/external/` 打包成 `Script_yyyyMMddHHmmss.zip`（`Script/external/...` 结构），便于分发。

### 参数传递规则（重要，统一约定）

GUI 根据 `index.json` 中 `params` 的 `name` 字段，把用户在界面输入的值代入脚本内的**占位符**后再运行，**原始脚本文件不会被修改**。所有语言使用同一套约定：

- **占位符形式：`_p{参数名}`**——前缀 `_p` + 花括号内写参数名，如 **`_p{NAME}`**、**`_p{IP_ADDRESS}`**、**`_p{PORT_NUMBER}`**。
  - 这样设计是为了避免与脚本里真实出现的 `${...}` 字符串（如 Bash 变量、PowerShell 变量、Python f-string、模板占位符等）发生碰撞：`_p{}` 这个专属前缀把"程序参数占位符"和普通代码里的 `${}` 彻底区分开，**脚本自身的 `${}` 语法完全不再受干扰**。
  - 迁移说明：早期版本使用 `${_NAME}` 形式，现已全面改为 `_p{NAME}`（参数名不再需要下划线开头）。
- **参数名约定：全大写 + 下划线分词（UPPER_SNAKE_CASE）**，如 `NAME`、`IP_ADDRESS`、`PORT_NUMBER`。
- 脚本内用 **`_p{参数名}`** 表示参数（与 `index.json` 的 `params[].name` 对应，**大小写敏感**，但允许 `_p{ NAME }` 含空格）。
- 运行时程序会把 `_p{NAME}` 等占位符**原地替换**为用户输入值，生成临时脚本执行。未填写的参数使用 `default` 值（仍为空则用空串）。
- 支持多语言一致写法，例如 `Hello, _p{NAME}!` 在 PowerShell / CMD / Bash / Python / Node / Java 中都能正确代入。

> **关于命名规范的强制性（重要）**：上述命名规范**仅为人可读的约定，程序不做任何校验**。匹配逻辑是拿 `params[].name` 的值直接做纯文本正则匹配 `_p{...}`，因此参数名写作 `IP_ADDRESS`、`ipAddress`、甚至其它任意形式，**只要写在 `_p{}` 内**，程序都能正常代入、不影响执行。
> 唯一的硬性要求是：**`params[].name` 与脚本内 `_p{...}` 中的名字必须字面完全一致（含大小写）**。例如 `params[].name` 为 `NAME` 时，脚本里写 `_p{NAME}` 才会被替换，写 `_p{name}` 或 `_p{Name}` 则**不会**——该占位符会原样保留在脚本中交给运行时处理。

示例（各语言统一风格）：

```powershell
# PowerShell (test/powershell.ps1)
Write-Host "Hello, _p{NAME}!"
```

```powershell
# PowerShell 7 (pwsh) — 语法与 Windows PowerShell 一致，lang 用 "pwsh"
# pwsh.ps1
Write-Host "Hello, _p{NAME}!"
```

```bat
@echo off
echo Hello, _p{NAME}!
```

```bash
#!/usr/bin/env bash
echo "Hello, _p{NAME}!"
```

```python
#!/usr/bin/env python3
# 普通字符串直接写即可；f-string 里若要保留字面花括号需写成 _p{{NAME}}（{{ }} 转义）
print("Hello, _p{NAME}!")
```

```javascript
#!/usr/bin/env node
console.log(`Hello, _p{NAME}!`);
```

```java
// 需 Java 11+ 单文件启动
public class java {
    public static void main(String[] args) {
        System.out.println("Hello, _p{NAME}!");
    }
}
```

```go
// Go 文件名须 snake_case（如 hello_world.go）；由 go run 直接执行
package main

import "fmt"

func main() {
    fmt.Println("Hello, _p{NAME}!")
}
```

```rust
// Rust 文件名须 snake_case（如 hello_world.rs）；先 rustc 编译为临时 exe 再执行
fn main() {
    println!("Hello, _p{NAME}!");
}
```

> 注意：占位符 `_p{NAME}` 与脚本自身的普通 `${}` 语法（如 Bash 变量、Python f-string）**完全不会冲突**——程序只识别 `_p{...}` 这一种形式，脚本里写 `${var}`、`${code}` 等原生语法会原样保留交运行时处理，无需再靠下划线前缀做区分。

---

## 二、external 目录结构

```
external/
├── index.json          # 脚本清单（必需），描述每个脚本的元数据
├── hyper/              # 按功能分子目录，自由组织
│   └── Set-StaticIP.ps1
├── network/
│   └── show-ip.ps1
├── demo/               # 各语言示例
│   ├── powershell.ps1
│   ├── cmd.bat
│   ├── bash.sh
│   ├── node.js
│   ├── python.py
│   └── java.java
├── openfirewall.ps1
└── restart.bat
```

- 子目录仅用于归类，不影响运行；最终都靠 `index.json` 的 `path` 定位。
- **目录树的层级完全由 `index.json` 的嵌套结构决定**：用 `children` 表达父子关系，可无限层级嵌套。物理子目录与树层级无关。

---

## 三、脚本编写规范

### 1. `index.json` 结构说明

`index.json` 是一个**嵌套数组**，用 `children` 表达目录层级。节点分两类：

- **目录节点**：只需 `name` + `children`（有 `children` 即视为目录），可选 `hide`
- **脚本节点**：`name` + `path` + `lang` 等（无 `children`）

> **`hide` 对两类节点都生效**：
> - 目录节点 `hide: true` → 该目录**及其全部下级**都不显示（整棵子树隐藏，无需逐个标记子节点）
> - 脚本节点 `hide: true` → 仅该脚本不显示

```json
[
  {
    "name": "网络",
    "children": [
      {
        "name": "网络详情",
        "path": "./network/Get-IPInfo.ps1",
        "lang": "powershell",
        "hide": false
      },
      {
        "name": "防火墙",
        "hide": false,
        "children": [
          {
            "name": "启用防火墙",
            "path": "./network/firewall/Enable-Firewall.ps1",
            "lang": "powershell",
            "admin": true
          }
        ]
      }
    ]
  }
]
```

上面会渲染成：

```
网络
├── 网络详情          （脚本）
└── 防火墙            （目录）
    └── 启用防火墙     （脚本）
```

#### 脚本节点字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 显示名称（树节点/列表）。**建议简洁明确，避免超长文本** |
| `path` | 是 | 脚本相对脚本根目录的路径，如 `./hyper/Set-StaticIP.ps1` |
| `lang` | 是 | 语言标识，决定可执行文件，如 `powershell` / `pwsh` / `cmd` / `bash` / `node` / `python` / `java` / `go` / `rust`（`pwsh` 指 PowerShell 7+，与 `powershell`（Windows PowerShell 5.1）区分，运行时不回退） |
| `admin` | 否 | `true` 时以管理员身份运行（有提权需求的脚本务必设置） |
| `hide` | 否 | `true` 时不在界面显示 |
| `params` | 否 | 参数数组，见下表 |

#### 目录节点字段

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 目录显示名称 |
| `children` | 是 | 子节点数组（目录或脚本），非空即视为目录节点 |
| `hide` | 否 | `true` 时**该目录及其全部下级**都不显示（整棵子树隐藏） |

> 目录被隐藏后，其子节点的 `hide` 无需再逐个设置——整棵子树都会跳过，也不会因下级脚本文件缺失而产生告警。

#### `params` 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 参数名，**约定全大写 + 下划线分词（UPPER_SNAKE_CASE）**（如 `NAME`、`IP_ADDRESS`），与脚本内占位符 `_p{NAME}` 对应。**不再需要 `_` 下划线开头**——区分程序参数与脚本自身 `${}` 语法靠的是 `_p{}` 这个专属前缀。此命名为约定而非强制，程序不做校验，但需与脚本内占位符**字面完全一致（含大小写）** |
| `label` | 否 | 界面上的输入框标签，缺省用 `name` |
| `default` | 否 | 默认值；有默认值时输入框预填该值 |
| `required` | 否 | `true` 时该参数为必填 |
| `placeholder` | 否 | 输入框为空时显示的灰字提示（如 `如 192.168.128`）；同时作为该输入框的 ToolTip |
| `options` | 否 | 可选项数组，提供后界面变为下拉选择（如 `["TCP","UDP"]`） |

### 2. 编写约定

- **幂等与可重入**：脚本应避免破坏性副作用；需要管理员权限的务必设 `admin: true`。
- **参数命名**：`index.json` 中 `params[].name` 约定全大写 + 下划线分词（如 `NAME`、`IP_ADDRESS`），脚本内对应写成 `_p{NAME}`。占位符统一用 `_p{}` 前缀，因此不会与脚本自身的 `${}` 语法（Bash/PowerShell 变量、Python f-string 等）发生碰撞。（约定非强制，但需与脚本内占位符字面一致）
- **清晰注释**：脚本顶部用注释说明用途与参数，便于他人维护。
- **`echo %VAR% | findstr` 前不要留空格**：`echo` 会**原样输出** `%VAR%` 与 `|` 之间的空格，导致 findstr 收到的字符串末尾多一个空格；若正则以 `$` 结尾就会匹配失败。写成 `echo %VAR%|findstr /R "..."`。
- **`findstr /R` 不支持 `\` 转义**：写 `\.` 不会被理解为"字面点号"，而是"反斜杠 + 任意字符"。匹配点号请用字符类 **`[.]`**。例（同时规避上述两点）：
  ```bat
  echo %TARGET%|findstr /R "^[0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[ ]*$" >nul
  ```
- **⚠️ 禁止用 `for /f` 捕获外部命令输出**：`for /f ... in ('命令')` 启动子进程，会破坏 cmd 的批处理文件读取位置，
  导致**此后所有 `goto` 都找不到标签**，报 `The system cannot find the batch label specified - <标签>`，脚本在收尾前中断
  （**退出码 1 是 cmd 错误码，不代表脚本的业务结论**）。
  注意：把 `goto` 移到括号块外**无效**——破坏发生在 `for /f` 执行时，与 `goto` 位置无关。**改用以下方案**：

  1. **只需判断成败** → 让子进程直接返回退出码（首选，零副作用）：
     ```bat
     powershell -NoProfile -Command "try { $c=New-Object System.Net.Sockets.TcpClient; $c.Connect('%TARGET%',%PORT%); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
     if errorlevel 1 (set "TEST_OK=0") else (set "TEST_OK=1")
     ```
  2. **需要文本内容** → 临时文件 + `set /p`，且 PowerShell 侧必须显式 `-Encoding ASCII`
     （默认 UTF-16LE 会让 cmd 读出乱码）：
     ```bat
     powershell -NoProfile -Command "(Resolve-DnsName -Name '%TARGET%' ...).IPAddress | Out-File -Encoding ASCII -FilePath '%TMPF%'" >nul 2>&1
     if exist "%TMPF%" ( set /p RESOLVED_IP=< "%TMPF%" & del "%TMPF%" 2>nul )
     ```
  3. 分割已有字符串用 `for /f "tokens=..." in ("字符串字面量")`——不启动进程，安全。

- **判断成败统一用 `if errorlevel 1`**：该语法直接读当前 errorlevel，不受变量展开时机影响；
  不要用 `if %errorlevel% equ 0`（在括号块内会取到进入块之前的旧值）。

- **尽量不用 `goto`**：改用 `if/else` 嵌套，避免依赖批处理文件指针跳转。
  参考实现见 `windows/network/network_connectivity_test.bat`。
- **编码**：脚本文件统一使用 **UTF-8 无 BOM**（2026-08-29 用户裁定：全部脚本与 C# 项目代码一致，不再按语言区分带/不带 BOM）。代码文件（`.cs`/`.xaml`）同样 UTF-8 无 BOM。程序读取源文件按实际编码探测（`EncodingHelper.DetectFromFile`），写出临时文件时按语言固定：**PowerShell 强制 UTF-8 带 BOM**（Windows PowerShell 5.1 读无 BOM 的 `.ps1` 会按系统 ANSI 代码页解码导致中文乱码），**其余语言 UTF-8 无 BOM**（与源文件一致）。源文件从不修改，无编码选择框。
  - ⚠️ **bat 注释里的 cmd 特殊字符坑（脚本编写规范，与编码无关）**：`REM` 注释行 cmd 在解析阶段仍会处理特殊字符，`>` 是输出重定向符、`|` 是管道、`&` 是命令连接。注释里写 `->`（半角）会让 cmd 把 `>` 当重定向、把后面 `（` `）` 片段当命令 → 报 `'Test-Connection）' is not recognized` 等（不致命但日志脏）。规范：bat 注释禁用半角 `>`/`<`/`|`/`&`，箭头用全角 `→`（U+2192）。
- **中英文 / 数字间加空格（盘古之白，适用于一切用户可见文本）**：所有**日志文案、注释、提示语、UI 文案**里，中文与拉丁字母（A-Z a-z）、阿拉伯数字（0-9）相邻时，中间插入一个半角空格。例：`默认安装至程序runtime目录` → `默认安装至程序 runtime 目录`；`连接TCP端口8080失败` → `连接 TCP 端口 8080 失败`。
  - **例外（不要加空格）**：
    - **ANSI 转义序列 / 颜色码**：`\e[30m这是`、`$esc[${code}m这是`、`{}m这是`（Rust）、`%s这是`（Go）等，转义码与中文之间不可加空格，否则颜色输出前会被多插入一个空格。
    - **格式化占位符紧贴**：`{0}`、`%s`、`$(var)`、f-string 等占位符与其紧邻的固定中文字符之间不加空格（如 `"共 {0} 个"` 中空格由格式串自身决定，不要额外在 `共` 与 `{` 间加）。
    - **英文缩写连写、单位、版本号等惯例**：`IPv4`、`x64`、`UTF-8`（连字符保留）、`JDK 21`（此处 JDK 与数字间仍按规则加空格）、`v2.0` 本身不加；但中英文混排主体仍遵循加空格（如 `使用 JDK 21 安装`）。
  - **契约值同步**：若某字符串同时出现在 `index.json` 的 `options`/`default` 与脚本内的比较/判断逻辑中（如选项 `"GitHub 官方"` 与脚本里 `$x -ne 'GitHub 官方'`），加空格时**两处必须同步改写**，否则脚本会因字面值不匹配而误判/报错。
  - 本项目已对 `script/` 全量脚本与 `index.json` 按此规则统一排版（2026-09-02）。
- **路径处理**：脚本内尽量使用相对自身路径或接收的参数，不要硬编码绝对路径。
- **输出**：通过标准输出打印进度/结果，程序会实时回显到日志区。

### 3. 文件命名约定

脚本文件名按语言遵循对应的行业规范，便于跨平台与他人维护：

| 语言 | 扩展名 | 命名风格 | 备注 |
| --- | --- | --- | --- |
| CMD / Batch | `.bat` / `.cmd` | `snake_case` 或 `kebab-case` | 全小写 + 下划线或连字符；业界约定俗成 |
| PowerShell | `.ps1` / `.psm1` / `.psd1` | **PascalCase**（动词-名词） | 官方强制：每个单词首字母大写，如 `Get-LogFile.ps1`、`Remove-StaleData.ps1` |
| PowerShell 7 (pwsh) | `.ps1` | **PascalCase**（动词-名词） | 与 PowerShell 同规范（lang 用 `pwsh` 区分运行时；语法一致，可用 `param(...)` 块收参） |
| Node.js / JavaScript | `.js` / `.mjs` / `.cjs` | `kebab-case`（主流）或 `snake_case` | 社区主流 kebab-case；npm 包等场景允许 snake_case；避免驼峰（历史原因 + Windows/Linux 大小写敏感问题） |
| Java | `.java` | **PascalCase** | 语言强制：文件名必须与 `public class` 名完全一致，如 `UserService.java` |
| Bash / Shell | `.sh` / `.bash` | `snake_case` | 全小写 + 下划线；POSIX 兼容、业界通用 |
| Python | `.py` / `.pyw` | `snake_case` | **PEP 8 强制**：模块名全小写 + 下划线分隔（严禁驼峰） |
| Go | `.go` | `snake_case` | **官方强制**：`go build` 忽略以 `_` 或 `.` 开头的文件；文件名一律小写 + 下划线（严禁驼峰） |
| Rust | `.rs` | `snake_case` | **官方强制**：模块/文件名小写 + 下划线，驼峰文件名会触发 `non_snake_case` 警告 |

**示例**（对照上表）：
- `backup_files.bat`、`install-app.cmd`
- `Get-LogFile.ps1`、`Remove-StaleData.ps1`
- `user-service.js`、`test_runner.js`
- `UserService.java`、`HttpConnectionHandler.java`
- `backup_database.sh`、`install_deps.bash`
- `user_service.py`、`db_connection.py`
- `svg_to_ico.go`、`check_port.go`
- `svg_to_ico.rs`、`check_port.rs`

**目录（子文件夹）命名约定**：
- 一律 **小写**（lower-case）。
- 单词间用连字符 `-`（kebab-case），**不使用下划线** `_` 或驼峰。
- 采用 **单数**（如 `color-log/`，而非 `color-logs/` 或 `ColorLogs/`）。
- 示例：`color-log/`、`external-dep/`、`net-tool/`。

### 3. 新增脚本步骤

1. 在合适子目录创建脚本文件（如 `hyper/MyScript.ps1`）。
2. 在 `index.json` 中，把新脚本作为**脚本节点**加到目标目录节点的 `children` 里（填 `name`/`path`/`lang` 等）；若要新建分组，加一个 `name` + `children` 的目录节点。
3. 回到程序界面点「刷新」，新脚本即出现。

---

## 三-B、外部依赖（lib 约定目录）

第三方依赖统一放在 `lib/`（由 `config.ini` 的 `lib_path` 配置，默认 exe 同级 `lib`）。运行时程序会注入环境变量 `SCRIPT_MANAGER_LIB` 指向该目录根路径，供脚本引用。

**约定：依赖必须按语言放入约定子目录，放错目录名（如 `lib/java1`）不生效**：

| 语言 | 子目录 | 用法 |
| --- | --- | --- |
| Java | `lib/java/` | 放 `*.jar`；程序自动把该目录所有 jar 拼成 `--class-path`，脚本内直接 `import` 即可 |
| Python | `lib/python/` | 放包/模块；脚本内 `sys.path.insert(0, os.path.join(os.environ['SCRIPT_MANAGER_LIB'], 'python'))` 后 `import` |
| Node | `lib/node/` | 放 npm 包；脚本内 `module.paths.unshift(require('path').join(process.env.SCRIPT_MANAGER_LIB, 'node'))` 后 `require` |
| Go | `lib/go/` | Go 为编译型，**不能像解释型那样直接 `import` 随附包**；约定目录用于放源码包/模块缓存等资源，脚本内按 `SCRIPT_MANAGER_LIB` 自行拼路径读取 |
| Rust | `lib/rust/` | 同为编译型，`rustc` 单文件编译不读该目录；用于放脚本所需的辅助资源，脚本内按 `SCRIPT_MANAGER_LIB` 拼路径读取 |
| 其他 | `lib/<语言标识>/` | 子目录名必须等于语言标识 |

- `lib/` 根目录本身**不**自动被任何语言加载，依赖必须进对应子目录。
- 打包（`build.ps1`）会整目录复制 `lib/`，含所有约定子目录，无需额外配置。

---

## 四、分发与维护

- **给最终用户**：用程序内「导出」按钮生成 `Script_yyyyMMddHHmmss.zip`，或直接把 `Script/external/` 目录交给对方放到 exe 同级即可。
- **更新脚本**：修改后让对方覆盖 `Script/external/` 对应文件，刷新即可生效。
- 内置脚本（`internal/`）随程序版本发布，普通用户不要在 `external/` 里放同名文件去覆盖它们（external 与 internal 由界面分组区分，互不干扰）。

---

## 五、文件编码规范（重要）

脚本文件统一 UTF-8 无 BOM（2026-08-29 用户裁定：全部脚本与 C# 项目代码一致，不再按语言区分带/不带 BOM）。程序读取源文件按实际编码探测（`EncodingHelper.DetectFromFile`），写出临时文件时按语言固定编码（源文件从不修改，无编码选择框）：

| 类别 | 扩展名 | 编码 | 原因 |
| --- | --- | --- | --- |
| 代码文件 | `.cs` / `.xaml` / `.csproj` | **UTF-8 无 BOM** | Roslyn / MSBuild / Visual Studio 原生按无 BOM 处理，带 BOM 反被 linter 视为多余 |
| 脚本源码 | `.bat` / `.cmd` / `.ps1` / `.sh` / `.js` / `.java` / `.py` / `.go` / `.rs` | **UTF-8 无 BOM** | 与项目代码统一；源文件永远保持无 BOM |
| PowerShell / pwsh 临时文件 | `.ps1`（执行时） | **UTF-8 带 BOM** | Windows PowerShell 5.1 读无 BOM 的 `.ps1` 按系统 ANSI 代码页（GBK）解码 → 中文乱码；带 BOM 才按 UTF-8 解码（PowerShell 7 / pwsh 亦兼容） |
| 其余语言临时文件 | 执行时 | **UTF-8 无 BOM** | 与源文件一致；Java 单文件源码（`java x.java`）不支持源文件带 BOM（报「非法字符 \ufeff」），内容正确性由 `JDK_JAVA_OPTIONS` 的 `-Dfile.encoding=UTF-8` 保证 |

**macOS 上去 BOM（统一无 BOM 用）**：

```bash
# 去 BOM（去掉文件头 3 字节）
tail -c +4 文件 > tmp && mv tmp 文件
```

### cmd / bat 的中文处理（程序自动改写，编写侧无需特殊处理）

cmd.exe **没有"文件编码"概念**——它按当前控制台代码页（中文 Windows 默认 936/GBK）逐字节解码 bat 文件，所以 UTF-8 无 BOM 的中文必然被解成乱码字。（补一句：给 bat **加 UTF-8 BOM 也无效**，`EF BB BF` 会被解成 `ï»¿` 拼到首行开头，反而让 `@echo off` 的 `@` 失效。）

因此程序对 `lang: "cmd"` 的脚本做了**运行前自动改写**（源码文件始终不被修改）：

1. 把脚本里所有中文等非 ASCII 片段抽出来，替换为 `%SM_TXT_001%` 形式的占位符，脚本在**字节层面降为纯 ASCII** → 任何代码页下都能被正确解析；
2. 中文真值经**进程环境块（UTF-16）**注入子进程，cmd 展开 `%SM_TXT_001%` 取回 Unicode 原文 → 无损、不受代码页影响；
3. 改写**逐行全覆盖**，包括 `REM` / `::` 注释行——因为 cmd 按"解码后的字符数"计算下一行的文件偏移，而中文占 3 字节只算 1 字符，**残留任何一个多字节字符都会让偏移逐行累积漂移**，后续行被从中间读起、刷出大量 `'xxx' is not recognized as an internal or external command`。所以注释里的中文同样会被抽走。

**编写侧约束**（遵守即可，无需任何编码技巧）：

- 照常用 **UTF-8 无 BOM** 写 bat，中文随意写；
- 中文**不要**用在标签名和 `goto` 目标上：cmd 匹配标签时不做变量展开，`goto :中文标签` 改写后会跳转失败；
- 未写 `@echo off` 的脚本，回显注释时会看到 `%SM_TXT_001%` 占位符而非中文（cmd 对 `REM` 后内容不展开变量）。加了 `@echo off` 即不可见，不影响执行。

> 提示：预览区显示的是**原始脚本**（你写的样子），改写只发生在执行瞬间，且不落回源文件。
