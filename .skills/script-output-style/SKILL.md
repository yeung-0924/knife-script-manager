---
name: script-output-style
description: 脚本执行日志输出规范（颜色 + 标识），适用于 script-manager-win 的正式脚本。编写/修改 script/ 下任何脚本的标准输出日志时，优先按本技能约束——本规范优于模型的泛化经验。
agent_created: true
---

# 脚本执行日志输出规范（颜色 + 标识）

适用于 `script-manager-win` 的**正式脚本**（`script/` 下除 `demo/` 与 `test/` 之外的所有 `.ps1`/`.bat`/`.cmd`/`.py`/`.java`/`.sh`）。
当你编写、修改脚本里"打印给用户看的运行日志"时，优先按本规范，而不是依赖通用习惯。

## 何时使用

- 新增/修改脚本中由脚本自身 `print`/`echo`/`Write-Host`/`Write-Output` 等打印的"运行信息日志"
- 决定日志该用什么颜色、带什么前缀标识
- 用户要求 "统一日志颜色/标识"、"入参出参用绿色" 等

## 核心规则（强制）

日志颜色统一用 **ANSI SGR 转义码**（前景色）：

| 类别 | 颜色 | ANSI 前景码 | 必需标识前缀 |
|---|---|---|---|
| 入参（脚本收到的参数/输入） | 亮绿 | `92` | `[入参]` |
| 结果（执行结论/返回值/成功信息） | 亮绿 | `92` | `[结果]` |
| 信息（脚本自身打印的提示/进度/说明） | 亮黄 | `93` | `[信息]` |
| 异常（脚本自身捕获/打印的错误） | 亮红 | `91` | `[异常]` |

- **脚本自身 stdout 的真实业务输出**（如命令原样转发的结果、ping 输出等）**保持原色**，不要套颜色、也不要强加标识。
- **自打印日志必须有标识**：凡是脚本自己打印的日志行，一律带上面对应的 `[入参]`/`[信息]`/`[异常]`/`[结果]` 标签之一；不要无标识地裸打印。

## 文本排版规则（强制，与日志标识同等优先）

写日志文案、注释、提示语等一切用户可见文本时，遵循「盘古之白」：

- **中文与拉丁字母（A-Z a-z）、阿拉伯数字（0-9）相邻处，中间加一个半角空格**。
  例：`默认安装至程序runtime目录` → `默认安装至程序 runtime 目录`；`连接TCP端口8080失败` → `连接 TCP 端口 8080 失败`。
- **例外（不要加空格）**：
  - **ANSI 转义序列 / 颜色码**：`\e[30m这是`、`$esc[${code}m这是`、`{}m这是`（Rust）、`%s这是`（Go）等，转义码与中文之间不可加空格。
  - **格式化占位符紧贴**：`{0}`、`%s`、`$(var)`、f-string 等占位符与紧邻中文之间不加（如 `"共 {0} 个"` 由格式串决定空拍）。
  - **缩写 / 单位 / 版本号惯例**：`IPv4`、`x64`、`UTF-8` 连写保留；但中英文混排主体仍加空格（如 `使用 JDK 21 安装`）。
- **契约值同步**：若字符串同时出现在 `index.json` 的 `options`/`default` 与脚本内比较逻辑（如 `"GitHub 官方"` ↔ `$x -ne 'GitHub 官方'`），加空格时**两处必须同步**，否则字面值不匹配导致脚本误判。
- 本项目已于 2026-09-02 对 `script/` 全量脚本与 `index.json` 按此规则统一排版。

## ANSI 用法示例

### PowerShell (`.ps1`)
```powershell
$ESC = [char]27
$GREEN = "$ESC[92m"   # 亮绿：入参 / 结果
$YELLOW = "$ESC[93m"  # 亮黄：信息
$RED = "$ESC[91m"     # 亮红：异常
$RESET = "$ESC[0m"

Write-Host "${GREEN}[入参]${RESET} 目标主机: $Target"
Write-Host "${YELLOW}[信息]${RESET} 正在解析域名..."
try {
    # 业务逻辑
    Write-Host "${GREEN}[结果]${RESET} 连通正常，解析 IP: $ip"
} catch {
    Write-Host "${RED}[异常]${RESET} 解析失败: $_"
}
```
（也可用 `Write-Host -ForegroundColor Green` 等原生参数；但若要带 `[入参]` 标签并统一风格，推荐上式拼接。）

### cmd/batch (`.bat`/`.cmd`)
```bat
REM 生成 ESC 字符（与 test_cmd_colors.bat 同款可靠写法，避免 for /f 在重定向环境下抓不到）
for /F "delims=" %%L in ('"prompt $E & echo on & for %%i in (1) do rem"') do set "RAW=%%L"
set "ESC=%RAW:~0,1%"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

echo %GREEN%[入参]%RESET% 目标: %TARGET%
echo %YELLOW%[信息]%RESET% 正在检测...
echo %RED%[异常]%RESET% 连接失败
```
> **必做**：任何带颜色的 bat 都必须先生成 `ESC`（上面的两行），否则 `%ESC%` 为空，输出裸 `[92m` 不上色。
> 注意：本项目禁止用 `for /f` 捕获外部命令输出（会破坏批处理文件指针、导致 goto 失败），但**仅用 `for /f` 生成 ESC 这两行是允许的**，因为它不读取脚本内部结果、也不依赖后续 goto。
> 注意：cmd 注释禁用半角 `>`/`<`/`|`/`&`（用全角 `→`）；不要在 `for /f ... in ('命令')` 里捕获进程输出（会破坏 goto 且本项目已禁用该写法）。详见 script-manager-win 记忆文件。

### Python (`.py`)
```python
ESC = "\033"
GREEN, YELLOW, RED, RESET = f"{ESC}[92m", f"{ESC}[93m", f"{ESC}[91m", f"{ESC}[0m"
print(f"{GREEN}[入参]{RESET} 端口: {port}")
print(f"{YELLOW}[信息]{RESET} 开始扫描")
print(f"{RED}[异常]{RESET} 超时")
```

### Java (`.java`)
```java
String ESC="\033", GREEN=ESC+"[92m", YELLOW=ESC+"[93m", RED=ESC+"[91m", RESET=ESC+"[0m";
System.out.println(GREEN+"[入参]"+RESET+" 名称: "+name);
System.out.println(YELLOW+"[信息]"+RESET+" 处理中");
System.err.println(RED+"[异常]"+RESET+" 出错");
```
（脚本原生业务输出仍走 `System.out`/`System.err` 原色即可。）

## 范围与例外

- **适用范围**：正式脚本（网络/系统/工具等分类下的脚本）。
- **排除**：`demo/`（演示多色用，可自由发挥）、`test/`（测试脚本，可不带标识）。
- **不强制**：外部子命令的原生输出（如 `ping`、`Resolve-DnsName` 的结果）保持原样，不套本规范颜色/标识。

## 与生产环境的配合

- 日志面板（WPF `RichTextBox` + `AnsiParser`）已支持 ANSI 前景色内联着色；同时执行器也会按 stdout/stderr 流着色（stdout→灰、stderr→红）。
- 本规范的 ANSI 颜色会被日志面板正确解析显示；若日志被重定向到 `log/` 文件，ANSI 码原样落盘（终端查看仍带色）。

## 反思提示

修改/新增脚本日志后，若发现颜色或标识不符合上表（如无标识裸打印、入参用了黄色），回来修正本技能或样本。
