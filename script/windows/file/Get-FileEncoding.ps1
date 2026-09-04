# 更新时间: 2026-09-04 15:58:45
# Get-FileEncoding.ps1 - 获取文件编码：递归扫描目录下的所有文件，检测并显示其字符编码
# 参数（由程序代入，占位符 _p{XXX}）：
#   PATH - 文件或目录路径（必填）
#   NAME - 文件名称关键字（可选）。模糊匹配【文件名（含后缀）】，如输入 py1 可匹配 aaa.py1；
#          忽略大小写；留空不过滤。若自行输入通配符（* / ?）则按通配符匹配。
#   ENCODING - 字符编码（可选）。下拉选择，只显示该编码的文件；留空显示全部。
#              ⚠️ 'UTF-8' 与 'ASCII / UTF-8' 视为同一族（ASCII 是 UTF-8 的子集，
#              这两种编码解读结果完全相同），选中任一项时两者都命中。
#   BOM - BOM（可选）。下拉选择「有」/「无」，只显示对应文件；留空显示全部。
#
# 说明（健壮性处理）：
#   1) 统一用 Write-Output 输出（success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 编码判定顺序：BOM → 二进制（NUL 字节）→ ASCII / UTF-8 → UTF-8 → GBK → 其他 ANSI。
#      无 BOM 时"UTF-8 还是 GBK"只能靠字节合法性推断：用宽松 UTF-8 解码，
#      非法序列会被替换成 U+FFFD，故"解码结果不含 U+FFFD"即判为合法 UTF-8；
#      再按"字符数 == 字节数"区分：全单字节标为 'ASCII / UTF-8'（ASCII 是 UTF-8 的子集，
#      该文件两种编码都兼容、解读结果一致），含多字节则标为 'UTF-8'。
#      均失败才回退 GBK（中文 Windows 本地编码），仍失败则标记为其他 ANSI。
#   3) 不涉及编码的文件（exe/dll/图片/音视频/压缩包等）不显示。
#      采用【扩展名黑名单 + 内容 NUL 字节检测】双保险：
#      前者不打开文件即可跳过已知二进制类型（避免读取上 GB 的大文件），
#      后者兜底未知/无扩展名的二进制文件。
#   4) 每个文件只读取开头最多 256KB，大文件不会拖慢扫描。
#   5) 大目录（数万文件）每 5 秒汇报一次进度，两个阶段都有：
#      阶段 1 收集文件列表（栈式递归，边收集边汇报，避免 Get-ChildItem -Recurse
#      一次性枚举完才返回导致的"无输出像卡死"）；
#      阶段 2 逐个检测（已完成/总数/百分比/已用时间/预计剩余时间）。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
# 包 try/catch：输出被重定向、无控制台时该赋值可能抛异常，不能让它中断脚本
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

function Say { param([string]$Text = '') Write-Output $Text }

# 颜色辅助（ANSI SGR）：入参亮绿(92)，信息亮青(96)，异常亮红(91)，提示灰(90)
$ESC = [char]27
$GREEN = "$ESC[92m"; $CYAN = "$ESC[96m"; $RED = "$ESC[91m"; $GRAY = "$ESC[90m"; $RESET = "$ESC[0m"
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# 入参（工具在执行前把 _p{PATH} 占位符替换为用户的输入值）
$target = "_p{PATH}"
# 占位符未被替换（直接运行脚本）或留空 → 报错
if ($target -match '_p\{' -or [string]::IsNullOrWhiteSpace($target)) {
    SayC $RED '异常' '未指定路径：参数 PATH 为必填，请选择一个文件或目录。'
    exit 1
}
$target = $target.Trim().Trim('"').Trim("'")

if (-not (Test-Path -LiteralPath $target)) {
    SayC $RED '异常' ("路径不存在：{0}" -f $target)
    exit 1
}

# 入参（可选）：文件名称关键字，模糊匹配文件名（含后缀），如 py1 可匹配 aaa.py1
$nameFilter = "_p{NAME}"
# 占位符未被替换（直接运行脚本）或留空 → 不过滤
if ($nameFilter -match '_p\{' -or [string]::IsNullOrWhiteSpace($nameFilter)) {
    $nameFilter = ''
} else {
    $nameFilter = $nameFilter.Trim()
}

# 匹配模式：用户若自己写了通配符（* / ?）则按其意图做通配匹配；
# 否则视为"子串关键字"，用 IndexOf 做忽略大小写的包含匹配（比 -like 快，大目录更划算）。
# 匹配对象是【文件名（含后缀）】而非完整路径，故 aaa.py1 输入 py1 可命中。
$nameHasWildcard = $false
if ($nameFilter -and ($nameFilter.IndexOf('*') -ge 0 -or $nameFilter.IndexOf('?') -ge 0)) {
    $nameHasWildcard = $true
}

# 入参（可选）：字符编码，只显示该编码的文件；留空显示全部
$encodingFilter = "_p{ENCODING}"
if ($encodingFilter -match '_p\{' -or [string]::IsNullOrWhiteSpace($encodingFilter)) {
    $encodingFilter = ''
} else {
    $encodingFilter = $encodingFilter.Trim()
}

# 入参（可选）：BOM，只显示「有」/「无」BOM 的文件；留空显示全部
$bomFilter = "_p{BOM}"
if ($bomFilter -match '_p\{' -or [string]::IsNullOrWhiteSpace($bomFilter)) {
    $bomFilter = ''
} else {
    $bomFilter = $bomFilter.Trim()
}

# 取值校验：下拉选择的正常路径不会触发。但若 index.json 的 options 与下面的取值集合不同步
# （改了一处忘了另一处），静默返回 0 结果会让用户误以为"目录里没有这类文件"，故显式报错。
$knownEncodings = @('UTF-8', 'ASCII / UTF-8', 'UTF-16 LE', 'UTF-16 BE', 'UTF-32 LE', 'UTF-32 BE', 'GBK / GB2312', '其他 ANSI（非 UTF-8）')
if ($encodingFilter -and $knownEncodings -notcontains $encodingFilter) {
    SayC $RED '异常' ("字符编码取值无效「{0}」，应为 {1}" -f $encodingFilter, ($knownEncodings -join ' / '))
    exit 1
}
if ($bomFilter -and $bomFilter -ne '有' -and $bomFilter -ne '无') {
    SayC $RED '异常' ("BOM 取值无效「{0}」，应为 有/无" -f $bomFilter)
    exit 1
}

# UTF-8 族：'UTF-8' 与 'ASCII / UTF-8' 视为同一种编码。
# ASCII 是 UTF-8 的子集（0x00-0x7F 的编码逐字节一致），这类文件用两种编码打开结果完全相同，
# 用户眼里就是"UTF-8 文件"。故选中任一项时两者都命中——
# 否则选 UTF-8 会漏掉纯英文的 UTF-8 文件，选 ASCII / UTF-8 又会漏掉含中文的 UTF-8 文件。
$utf8Family = @('UTF-8', 'ASCII / UTF-8')

# 编码是否命中筛选：留空恒命中；UTF-8 族互相命中；其余精确匹配
function Test-EncodingMatch {
    param([string]$Encoding)
    if (-not $encodingFilter) { return $true }
    if ($utf8Family -contains $encodingFilter) { return ($utf8Family -contains $Encoding) }
    return ($Encoding -eq $encodingFilter)
}

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

# 已知二进制扩展名（小写）：命中即跳过，不打开文件
$binaryExts = @(
    # 可执行 / 库 / 编译产物
    '.exe', '.dll', '.pdb', '.lib', '.obj', '.sys', '.drv', '.bin', '.o', '.a', '.so', '.dylib',
    '.node', '.pyd', '.pyc', '.pyo', '.class', '.jar', '.war', '.ear', '.wasm', '.ilk', '.exp', '.res',
    '.gcno', '.gcda',
    # 压缩包 / 安装包 / 镜像
    '.zip', '.rar', '.7z', '.gz', '.tgz', '.bz2', '.xz', '.z', '.lz4', '.zst', '.cab', '.msi',
    '.iso', '.img', '.vhd', '.vhdx', '.vmdk', '.qcow2', '.wim', '.dmg', '.apk', '.ipa', '.deb', '.rpm',
    '.pak', '.crx', '.xpi', '.tar',
    # 图片
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.cur', '.tif', '.tiff', '.webp', '.heic', '.heif',
    '.psd', '.ai', '.eps', '.raw', '.cr2', '.nef', '.arw', '.svgz', '.emf', '.wmf',
    # 音频
    '.mp3', '.wav', '.flac', '.aac', '.ogg', '.wma', '.m4a', '.opus', '.mid', '.midi', '.amr',
    # 视频
    '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', '.mpeg', '.mpg', '.rmvb', '.rm', '.3gp', '.m4v', '.ts',
    # 办公文档（二进制容器，非纯文本）
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.vsdx', '.odt', '.ods', '.odp',
    # 字体
    '.ttf', '.otf', '.woff', '.woff2', '.eot', '.fon', '.pfb',
    # 数据库 / 数据文件
    '.db', '.sqlite', '.sqlite3', '.mdb', '.accdb', '.dat', '.idx', '.myd', '.myi', '.ibd', '.frm'
)
$binaryExtSet = @{}
foreach ($e in $binaryExts) { $binaryExtSet[$e] = $true }

# 取样上限：只读取文件开头部分用于判定。
# 256KB 是准确性与性能的折中：足够覆盖到文件里的非 ASCII 内容（编码特征通常在前几 KB 即出现），
# 又避免对每个文件都分配 1MB 字节数组（扫描上万个文件时 GC 压力显著）。
$SAMPLE_MAX = 256KB

# 宽松 UTF-8 解码器：非法字节序列会被替换为 U+FFFD，
# 因此"解码结果不含 U+FFFD"即可判定为合法 UTF-8（比逐字节严格校验快得多，且是 .NET 原生实现）。
$utf8 = [System.Text.Encoding]::UTF8

# U+FFFD 替换字符：出现即说明该字节序列不是合法的 UTF-8
$REPL = [char]0xFFFD

# 进度输出间隔（秒）：大目录扫描时按此节奏汇报进度，避免刷屏又不至于让用户觉得卡死
$PROGRESS_SEC = 5

# GBK 编码对象：PowerShell 7（.NET Core）需先注册 CodePages 提供程序，否则 GetEncoding(936) 抛异常
$gbk = $null
try {
    $gbk = [System.Text.Encoding]::GetEncoding(936)
} catch {
    try {
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        $gbk = [System.Text.Encoding]::GetEncoding(936)
    } catch {
        $gbk = $null
    }
}

# ---------------------------------------------------------------------------
# 函数
# ---------------------------------------------------------------------------

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return ("{0} B" -f $Bytes) }
    if ($Bytes -lt 1MB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N1} GB' -f ($Bytes / 1GB))
}

# 检测单个文件的编码。
# 返回对象：Encoding（编码名）、Bom（是否有 BOM）、Skip（是否跳过）、Reason（跳过原因）
function Get-EncodingInfo {
    param([string]$Path)

    $result = [pscustomobject]@{
        Encoding = '未知'
        Bom      = '无'
        Skip     = $false
        Reason   = ''
    }

    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $len = $fs.Length

        if ($len -eq 0) {
            $result.Encoding = '（空文件）'
            $result.Bom = '-'
            return $result
        }

        # 1) BOM 检测（读数越小越优先：UTF-32 4 字节 > UTF-8 3 字节 > UTF-16 2 字节）
        $headLen = [int][math]::Min(4, $len)
        $head = New-Object byte[] $headLen
        [void]$fs.Read($head, 0, $headLen)

        if ($headLen -ge 4 -and $head[0] -eq 0xFF -and $head[1] -eq 0xFE -and $head[2] -eq 0x00 -and $head[3] -eq 0x00) {
            $result.Encoding = 'UTF-32 LE'; $result.Bom = '有'; return $result
        }
        if ($headLen -ge 4 -and $head[0] -eq 0x00 -and $head[1] -eq 0x00 -and $head[2] -eq 0xFE -and $head[3] -eq 0xFF) {
            $result.Encoding = 'UTF-32 BE'; $result.Bom = '有'; return $result
        }
        if ($headLen -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) {
            $result.Encoding = 'UTF-8'; $result.Bom = '有'; return $result
        }
        if ($headLen -ge 2 -and $head[0] -eq 0xFF -and $head[1] -eq 0xFE) {
            $result.Encoding = 'UTF-16 LE'; $result.Bom = '有'; return $result
        }
        if ($headLen -ge 2 -and $head[0] -eq 0xFE -and $head[1] -eq 0xFF) {
            $result.Encoding = 'UTF-16 BE'; $result.Bom = '有'; return $result
        }

        # 2) 无 BOM：取样判断
        $sampleLen = [int][math]::Min([long]$SAMPLE_MAX, $len)
        $truncated = $len -gt $SAMPLE_MAX
        $buf = New-Object byte[] $sampleLen
        $fs.Position = 0
        $read = $fs.Read($buf, 0, $sampleLen)
        if ($read -ne $sampleLen) {
            $tmp = New-Object byte[] $read
            [Array]::Copy($buf, $tmp, $read)
            $buf = $tmp
        }

        # NUL 字节 → 二进制（注：UTF-16/32 已由 BOM 分支处理，此处无 BOM 却有 NUL 即二进制）
        if ([Array]::IndexOf($buf, [byte]0) -ge 0) {
            $result.Skip = $true
            $result.Reason = '二进制（含 NUL 字节）'
            return $result
        }

        # 截断处理：文件大于取样上限时，末尾可能正好切断一个多字节字符，
        # 会产生 U+FFFD 导致误判。UTF-8 最长 4 字节，故判定用的缓冲去掉末尾 3 字节即可。
        $u8buf = $buf
        if ($truncated -and $buf.Length -gt 3) {
            $n = $buf.Length - 3
            $tmp = New-Object byte[] $n
            [Array]::Copy($buf, $tmp, $n)
            $u8buf = $tmp
        }

        # UTF-8 判定：宽松解码后不含替换字符 ⇒ 合法 UTF-8。
        # 再按"字符数 == 字节数"区分：
        #   - 字符数 == 字节数  ⇒ 全是单字节字符（0x00-0x7F），标为 'ASCII / UTF-8'：
        #     ASCII 是 UTF-8 的子集（UTF-8 对 0x00-0x7F 的编码与 ASCII 逐字节一致），
        #     故这类文件两种编码都兼容、解读结果完全相同，用哪种打开都不会乱码。
        #   - 字符数 <  字节数  ⇒ 含中文等多字节字符，只能是 UTF-8。
        # 注：判定基于开头 256KB 取样，理论上存在极小的概率（取样段恰好未出现多字节字符）
        #     把 UTF-8 文件判成 ASCII / UTF-8；要 100% 准确需读完整个文件，大目录下不现实。
        # （全程 .NET 原生方法，避免用 PowerShell 循环逐字节扫描大数组）
        $s8 = $utf8.GetString($u8buf)
        if ($s8.IndexOf($REPL) -lt 0) {
            if ($s8.Length -eq $u8buf.Length) {
                $result.Encoding = 'ASCII / UTF-8'
            } else {
                $result.Encoding = 'UTF-8'
            }
            return $result
        }

        # 非 UTF-8：回退 GBK / GB2312（中文 Windows 本地编码）
        if ($null -ne $gbk) {
            try {
                $s = $gbk.GetString($u8buf)
                if ($s.IndexOf($REPL) -lt 0) {
                    $result.Encoding = 'GBK / GB2312'
                    return $result
                }
            } catch { }
        }

        $result.Encoding = '其他 ANSI（非 UTF-8）'
        return $result
    }
    catch {
        $result.Skip = $true
        $result.Reason = '读取失败（' + $_.Exception.Message + '）'
        return $result
    }
    finally {
        if ($null -ne $fs) { $fs.Dispose() }
    }
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

$isDir = Test-Path -LiteralPath $target -PathType Container
$rootItem = Get-Item -LiteralPath $target
$rootFullName = $rootItem.FullName

Say '=========================================='
Say ' 获取文件编码'
Say '=========================================='
# ---- 控制台同步打印「更新时间」：从脚本头部注释读取，便于用户贴错误日志时直接看到脚本版本时间 ----
$updateTime = ''
try {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $hdrLine = Get-Content -LiteralPath $scriptPath -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdrLine -match '更新时间:\s*([\d\-: ]+)\s*$') { $updateTime = $Matches[1].Trim() }
    }
} catch { }
if (-not [string]::IsNullOrWhiteSpace($updateTime)) {
    SayC $YELLOW '脚本' "更新时间: $updateTime"
}
SayC $GREEN '入参' ("路径: {0}" -f $rootFullName)
SayC $GREEN '入参' ("文件名: {0}" -f $(if ($nameFilter) { $nameFilter } else { '(空，不筛选)' }))
SayC $GREEN '入参' ("字符编码: {0}" -f $(if ($encodingFilter) { $encodingFilter } else { '(空，不筛选)' }))
SayC $GREEN '入参' ("BOM: {0}" -f $(if ($bomFilter) { $bomFilter } else { '(空，不筛选)' }))
Say ''

# --- 阶段 1：收集文件列表 ---------------------------------------------------
# 不用 Get-ChildItem -Recurse：它会先一次性枚举完整个目录树才返回，
# 大目录（数万文件）下这期间一行输出都没有，用户会以为卡死。
# 改用栈式递归：边收集边按 PROGRESS_SEC 节奏输出进度，顺带解决两个问题：
#   - 无权访问的目录：Get-ChildItem 只能 -ErrorAction 静默丢弃，这里可精确捕获并计数。
#   - 符号链接 / 目录联接（ReparsePoint）：如 C:\Users\x\Application Data 是 junction，
#     跟随会无限递归，必须显式跳过（Get-ChildItem -Recurse 默认也不进入）。
# 存 FileInfo 而非路径字符串：后续取 Length/Extension 无需再 stat 一次。
$files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
$dirDenied = 0

# 文件名筛选判定（供收集阶段调用）：无关键字时恒为 true
function Test-NameMatch {
    param([string]$Name)
    if (-not $nameFilter) { return $true }
    if ($nameHasWildcard) { return ($Name -like $nameFilter) }
    return ($Name.IndexOf($nameFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

if ($isDir) {
    SayC $CYAN '信息' '正在递归收集文件列表...'
    $collectSw = [System.Diagnostics.Stopwatch]::StartNew()
    $tickSw = [System.Diagnostics.Stopwatch]::StartNew()
    $dirStack = New-Object 'System.Collections.Generic.Stack[string]'
    $dirStack.Push($rootFullName)
    $dirScanned = 0

    while ($dirStack.Count -gt 0) {
        $dir = $dirStack.Pop()
        $dirScanned++
        try {
            # EnumerateFileSystemInfos 是惰性枚举：不预先全量 stat，内存占用可控
            foreach ($info in ([System.IO.DirectoryInfo]::new($dir)).EnumerateFileSystemInfos()) {
                $attr = $info.Attributes
                if (($attr -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if (($attr -band [System.IO.FileAttributes]::Directory) -ne 0) {
                    $dirStack.Push($info.FullName)
                } elseif (Test-NameMatch -Name $info.Name) {
                    # 筛选在收集阶段完成：不匹配的文件不进列表，
                    # 后续阶段 2 的进度分母与检测量都直接是有效文件数。
                    $files.Add($info)
                }
            }
        } catch {
            # 无权访问 / 路径过长等：跳过该目录，继续其余部分
            $dirDenied++
        }

        if ($tickSw.Elapsed.TotalSeconds -ge $PROGRESS_SEC) {
            SayC $CYAN '进度' ("收集文件列表... 已发现 {0} 个文件，已扫描 {1} 个目录" -f $files.Count, $dirScanned)
            $tickSw.Restart()
        }
    }
    $collectSec = $collectSw.Elapsed.TotalSeconds
    $collectSw.Stop()
    $tickSw.Stop()
    if ($dirDenied -gt 0) {
        SayC $GRAY '提示' ("{0} 个目录无权访问或无法枚举，已跳过" -f $dirDenied)
    }
    SayC $CYAN '信息' ("收集完成：共 {0} 个文件（扫描 {1} 个目录，耗时 {2:N1}s）" -f $files.Count, $dirScanned, $collectSec)
} else {
    # 单文件模式：同样套用文件名筛选，不匹配则结果为 0
    if (Test-NameMatch -Name $rootItem.Name) {
        $files.Add($rootItem)
    }
    SayC $CYAN '信息' '检测单个文件...'
}

if ($files.Count -eq 0) {
    # 提示需区分场景：筛选导致的空结果，用户该改关键字，而非以为目录是空的
    if ($nameFilter) {
        if ($isDir) {
            SayC $RED '异常' ("没有文件名匹配「{0}」的文件，请调整关键字后重试。" -f $nameFilter)
        } else {
            SayC $RED '异常' ("该文件名称不匹配关键字「{0}」。" -f $nameFilter)
        }
    } else {
        SayC $RED '异常' '该目录下没有任何文件。'
    }
    exit 1
}
Say ''

# --- 阶段 2：逐个检测编码 ---------------------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
$skipByExt = 0
$skipByContent = 0
$skipByError = 0
$skipByFilter = 0

$total = $files.Count
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()
$tickSw = [System.Diagnostics.Stopwatch]::StartNew()

for ($i = 0; $i -lt $total; $i++) {
    $f = $files[$i]

    # 扩展名黑名单：不打开文件直接跳过
    $ext = $f.Extension.ToLowerInvariant()
    if ($ext -and $binaryExtSet.ContainsKey($ext)) {
        $skipByExt++
    } else {
        $info = Get-EncodingInfo -Path $f.FullName
        if ($info.Skip) {
            if ($info.Reason -like '读取失败*') { $skipByError++ } else { $skipByContent++ }
        } elseif (-not (Test-EncodingMatch -Encoding $info.Encoding)) {
            # 编码不匹配：文件本身是文本，只是不符合筛选条件
            $skipByFilter++
        } elseif ($bomFilter -and $info.Bom -ne $bomFilter) {
            # BOM 不匹配：空文件的 Bom 为 '-'，不会命中 有/无 任一筛选
            $skipByFilter++
        } else {
            # 展示路径：目录下用相对路径，单文件用完整路径
            $display = $f.FullName
            if ($isDir) {
                $display = $f.FullName.Substring($rootFullName.Length).TrimStart('\', '/')
                if (-not $display) { $display = $f.Name }
            }

            $rows.Add([pscustomobject]@{
                Display  = $display
                Encoding = $info.Encoding
                Bom      = $info.Bom
                Size     = $f.Length
            })
        }
    }

    # 每 PROGRESS_SEC 秒汇报一次进度：大目录（数万文件）让用户能看到在推进。
    # 已完成数 / 总数 / 百分比 / 累计耗时 / 按当前速率外推的预计剩余时间。
    if ($tickSw.Elapsed.TotalSeconds -ge $PROGRESS_SEC) {
        $done = $i + 1
        $pct = [math]::Min(100, $done / $total * 100)
        $usedSec = $totalSw.Elapsed.TotalSeconds
        # 预计剩余：按当前平均速率外推（前几次因速率未稳定会有偏差，属正常）
        $remainSec = if ($pct -gt 0) { $usedSec / $pct * (100 - $pct) } else { 0 }
        SayC $CYAN '进度' ("{0:N1}%（{1}/{2}）已用 {3:N0}s，预计剩余 {4:N0}s" -f $pct, $done, $total, $usedSec, $remainSec)
        $tickSw.Restart()
    }
}
$totalSw.Stop()

# 明细：按路径排序，稳定可预期
$rows = @($rows | Sort-Object -Property Display)

if ($rows.Count -gt 0) {
    Say '------------------------------------------'
    # 列宽：编码 18 / BOM 3 / 大小 10（右对齐）/ 路径
    Say ('{0,-18} {1,-3} {2}  {3}' -f '编码', 'BOM', '大小'.PadLeft(10), '文件')
    Say '------------------------------------------'
    foreach ($r in $rows) {
        Say ('{0,-18} {1,-3} {2}  {3}' -f $r.Encoding, $r.Bom, (Format-Size $r.Size).PadLeft(10), $r.Display)
    }
} else {
    Say '------------------------------------------'
    if ($encodingFilter -or $bomFilter) {
        # 筛选导致的空结果：提示方向是"放宽条件"，而非让用户以为目录里没有文本文件
        SayC $RED '异常' '没有符合筛选条件的文本文件：请放宽「字符编码 / BOM / 文件名」条件后重试。'
    } else {
        SayC $RED '异常' '没有检测到任何文本文件（全部为二进制或不可读）。'
    }
}

# 编码分布统计
Say ''
Say '------------------------------------------'
SayC $CYAN '信息' '编码分布'
if ($rows.Count -gt 0) {
    $dist = @($rows | Group-Object -Property Encoding | Sort-Object -Property Count -Descending)
    foreach ($d in $dist) {
        Say ('  {0,-18} {1,5} 个' -f $d.Name, $d.Count)
    }
} else {
    Say '  （无）'
}

# 跳过统计：只列出非零项，避免"扩展名已知二进制 0 个"这类无意义的行
$totalSkip = $skipByExt + $skipByContent + $skipByError + $skipByFilter
if ($totalSkip -gt 0) {
    $skipParts = New-Object System.Collections.Generic.List[string]
    if ($skipByFilter -gt 0) { $skipParts.Add(('不符合筛选条件 {0} 个' -f $skipByFilter)) }
    if ($skipByExt -gt 0) { $skipParts.Add(('扩展名已知二进制 {0} 个' -f $skipByExt)) }
    if ($skipByContent -gt 0) { $skipParts.Add(('内容含 NUL 字节 {0} 个' -f $skipByContent)) }
    if ($skipByError -gt 0) { $skipParts.Add(('无法读取 {0} 个' -f $skipByError)) }
    Say ''
    SayC $GRAY '提示' ('已跳过 {0} 个文件：{1}' -f $totalSkip, ($skipParts -join '，'))
}

Say ''
Say '=========================================='
# 有筛选时 rows 已是筛选后的子集，说"文本文件"会与实际不符，故按场景切换措辞
$resultWord = if ($encodingFilter -or $bomFilter) { '符合条件' } else { '文本文件' }
if ($isDir) {
    SayC $GREEN '结果' ("完成：扫描 {0} 个文件，{1} {2} 个（检测耗时 {3:N1}s）" -f $total, $resultWord, $rows.Count, $totalSw.Elapsed.TotalSeconds)
} else {
    SayC $GREEN '结果' ("完成：{0} {1} 个" -f $resultWord, $rows.Count)
}
Say '=========================================='

