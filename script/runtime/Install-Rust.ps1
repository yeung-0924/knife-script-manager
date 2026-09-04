# 更新时间: 2026-09-04 14:59:35
# Install-Rust.ps1 - 从 static.rust-lang.org 下载并安装 Rust（官方 toolchain zip，解压即用）
# 说明（与 Install-Java.ps1 / Install-Python.ps1 同一套约定）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），避免重定向场景下日志丢失。
#   2) 下载用 HttpWebRequest 流式读取，在主线程每 20% 打印一次进度。
#   3) zip 用系统 ZipFile 解压。
#   4) 通道（channel）：stable / beta / nightly。
#      - stable 版本号从 channel-rust-stable.toml 的 [pkg.rust] version 字段读取。
#        注意 [pkg.rust] 段在文件深处（文件头几 KB 是 [pkg.cargo] 等段落），必须完整下载 manifest
#        （约 900KB）后再解析，取完即删；下载 rust-{版本}-{target}.zip。
#      - beta / nightly 官方提供固定名 zip：rust-{channel}-{target}.zip，无需版本号。
#   5) zip 内 rustc/ cargo/ 两个组件各带 bin，两个 bin 目录都会写入 SCRIPT_MANAGER_ENV。
#   6) 覆盖原文件=否（默认）：安装目录已有同通道 rust 目录时跳过下载解压直接复用；=是 则先删再装。
#   7) 依赖提示：MSVC 版 rustc 需要 VC++ 运行库，若本机从未装过 VS 或 vc_redist，rustc 可能无法运行。
#   8) PATH 通过 SCRIPT_MANAGER_ENV 聚合变量统一管理：Path 写入实际路径（CMD 不展开自定义 %VAR% 引用），
#      SCRIPT_MANAGER_ENV 单独保留作为聚合记录。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

$ErrorActionPreference = 'Stop'

# ---- 颜色（ANSI SGR）：入参/结果亮绿(92)、信息亮黄(93)、异常亮红(91) ----
$ESC = [char]27
$GREEN = "$ESC[92m"; $YELLOW = "$ESC[93m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function Say { param([string]$Text = '') Write-Output $Text }
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# ---- 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）----
$InstallDir = "_p{INSTALL_DIR}"
$Channel    = "_p{CHANNEL}"
$Overwrite  = "_p{OVERWRITE}"
$AddToPath  = "_p{SET_PATH}"

# 缺省兜底
if ([string]::IsNullOrWhiteSpace($Channel))   { $Channel = 'stable' }
if ([string]::IsNullOrWhiteSpace($Overwrite)) { $Overwrite = '否' }
if ([string]::IsNullOrWhiteSpace($AddToPath)) { $AddToPath = '是' }

Say '=========================================='
Say ' 自动安装 Rust（官方 toolchain 解压即用包）'
Say '=========================================='
SayC $GREEN '入参' "安装目录: $InstallDir"
SayC $GREEN '入参' "通道: $Channel"
SayC $GREEN '入参' "覆盖原文件: $Overwrite"
SayC $GREEN '入参' "追加到 PATH: $AddToPath"

# ---- 参数校验 ----
# 安装目录留空时回退到默认：exe 同级 runtime 目录（由执行器注入 SCRIPT_MANAGER_RUNTIME）。
# 不依赖进程工作目录——提权执行时 ShellExecute 会把工作目录强制改为 System32。
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = $env:SCRIPT_MANAGER_RUNTIME
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        SayC $RED '异常' '安装目录为空，且未获取到默认安装目录（SCRIPT_MANAGER_RUNTIME），请手动选择目标目录'
        exit 1
    }
    SayC $YELLOW '信息' "安装目录留空，使用默认目录: $InstallDir"
}
if ($Channel -notin @('stable', 'beta', 'nightly')) {
    SayC $RED '异常' "通道取值无效「$Channel」，应为 stable / beta / nightly"
    exit 1
}
if ($Overwrite -ne '是' -and $Overwrite -ne '否') {
    SayC $RED '异常' "覆盖原文件取值无效「$Overwrite」，应为 是/否"
    exit 1
}

# ---- 架构检测（同 Install-Java.ps1：优先 .NET OSArchitecture，回退环境变量）----
# Rust 官方 win 目标三元组：x86_64-pc-windows-msvc / aarch64-pc-windows-msvc
$rustTarget = 'x86_64-pc-windows-msvc'
$archRaw = ''
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64 -or $osArch -eq [System.Runtime.InteropServices.Architecture]::Arm) {
        $rustTarget = 'aarch64-pc-windows-msvc'
        $archRaw = 'ARM64'
    } else {
        $rustTarget = 'x86_64-pc-windows-msvc'
        $archRaw = 'x64 (AMD64)'
    }
} catch {
    $archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($archRaw -eq 'ARM64') { $rustTarget = 'aarch64-pc-windows-msvc' } else { $rustTarget = 'x86_64-pc-windows-msvc' }
}
SayC $YELLOW '信息' "系统架构: $archRaw -> 目标三元组 = $rustTarget"

# ---- 查找安装目录中已存在的同通道 rust 目录 ----
function Find-MatchingRust {
    param([string]$Dir, [string]$Channel, [string]$Target)
    $pattern = if ($Channel -eq 'stable') {
        "^rust-\d+\.\d+\.\d+-$([regex]::Escape($Target))$"
    } else {
        "^rust-$([regex]::Escape($Channel))-$([regex]::Escape($Target))$"
    }
    Get-ChildItem -Path $Dir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.Name -notmatch $pattern) { return $false }
            if (-not (Test-Path (Join-Path $_.FullName 'rustc\bin\rustc.exe'))) { return $false }
            return $true
        } |
        Select-Object -First 1
}

# 判断一个 PATH 分段是否是 Rust 的 bin 目录（形如 ...\rust-xxx\{rustc|cargo}\bin）
function Test-IsRustBinPath {
    param([string]$Segment)
    $s = $Segment.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    if ($s -notmatch '\\bin$') { return $false }
    $parent = Split-Path -Path $s -Parent
    $parentLeaf = Split-Path -Path $parent -Leaf
    if ($parentLeaf -inotmatch '^(rustc|cargo)$') { return $false }
    $grand = Split-Path -Path $parent -Parent
    $grandLeaf = Split-Path -Path $grand -Leaf
    if ($grandLeaf -inotmatch '^rust-') { return $false }
    if (-not (Test-Path (Join-Path $parent 'rustc.exe')) -and -not (Test-Path (Join-Path $parent 'cargo.exe'))) { return $false }
    return $true
}

# 当前进程是否具备管理员权限（决定环境变量写系统级 Machine 还是用户级 User）
function Test-IsAdministrator {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# ---- SCRIPT_MANAGER_ENV 聚合变量（与 Install-Java.ps1 同一套机制）----
# 读取聚合变量（Machine + User 两个作用域合并去重，保证切换过作用域后不丢条目）
function Get-ScriptManagerEnv {
    $items = @()
    foreach ($s in @('Machine', 'User')) {
        $raw = [Environment]::GetEnvironmentVariable('SCRIPT_MANAGER_ENV', $s)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $items += $raw -split ';'
        }
    }
    $items = $items | ForEach-Object { $_.TrimEnd('\') } |
        Where-Object { $_ } |
        Select-Object -Unique
    return ($items -join ';')
}

# 读取指定作用域的 SCRIPT_MANAGER_ENV 条目（返回数组，用于写 Path 时避免跨作用域污染）
function Get-ScriptManagerEnvForScope {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('SCRIPT_MANAGER_ENV', $Scope)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return @($raw -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ } | Select-Object -Unique)
}

# 把新 bin 目录前置进 SCRIPT_MANAGER_ENV；$IsOldEntry 脚本块用于判定应移除的旧条目（按运行时特征）
function Add-ScriptManagerEnvEntry {
    param([string]$BinDir, [string]$Scope, [scriptblock]$IsOldEntry)
    $binNorm = $BinDir.TrimEnd('\')
    $current = Get-ScriptManagerEnv
    if ([string]::IsNullOrWhiteSpace($current)) {
        $newVal = $binNorm
    } else {
        # 注意：ForEach-Object 中 return $null 会在数组里留下 null 元素，必须用 Where-Object 过滤后再 join
        $items = @($current -split ';' | ForEach-Object {
            $s = $_.TrimEnd('\')
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            if ($s -ieq $binNorm) { return $null }
            if (& $IsOldEntry $s) { return $null }
            return $s
        } | Where-Object { $_ } | Select-Object -Unique)
        $newVal = ($binNorm + ';' + ($items -join ';')).Trim(';')
    }
    [Environment]::SetEnvironmentVariable('SCRIPT_MANAGER_ENV', $newVal, $Scope)
}

# 确保指定作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（去重后写回）
function Ensure-PathHasScriptManagerEnv {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('Path', $Scope)
    $envPaths = Get-ScriptManagerEnvForScope -Scope $Scope
    if ($envPaths.Count -eq 0) { return }
    $envValue = $envPaths -join ';'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $newPath = $envValue
    } else {
        $segments = @($raw -split ';' | ForEach-Object {
            $s = $_.TrimEnd('\')
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            # 移除旧版遗留的 %SCRIPT_MANAGER_ENV% 字面量（兼容旧数据）
            if ($s -ieq '%SCRIPT_MANAGER_ENV%') { return $null }
            # 移除已经存在于 SCRIPT_MANAGER_ENV 中的路径，避免重复
            if ($envPaths -contains $s) { return $null }
            return $s
        } | Where-Object { $_ } | Select-Object -Unique)
        $newPath = $envValue + ';' + ($segments -join ';')
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
}

# ---- 主流程：已有同通道 rust 目录且不覆盖 -> 直接复用；否则重新安装 ----
$existingRust = $null
if ($Overwrite -eq '否') {
    $existingRust = Find-MatchingRust -Dir $InstallDir -Channel $Channel -Target $rustTarget
}

$rustHome = $null
if ($existingRust) {
    SayC $YELLOW '信息' "检测到已安装 Rust（$Channel）: $($existingRust.FullName)，跳过下载与解压"
    $rustHome = $existingRust.FullName
} else {
    # 覆盖模式：先删除同通道的旧 rust 目录
    if ($Overwrite -eq '是') {
        $oldRust = Find-MatchingRust -Dir $InstallDir -Channel $Channel -Target $rustTarget
        if ($oldRust) {
            SayC $YELLOW '信息' "覆盖模式：删除旧目录 $($oldRust.FullName)"
            try {
                Remove-Item -Path $oldRust.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
                SayC $RED '异常' '请先关闭占用该目录的程序（如正在运行的 Rust 进程），或手动删除后重试'
                exit 1
            }
        }
    }

    # ---- 解析通道对应的下载 URL ----
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmpDir = Join-Path $env:TEMP 'script-manager-rust'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $rustVer = $null
    if ($Channel -eq 'stable') {
        # 从 channel-rust-stable.toml 解析 [pkg.rust] version。
        # 注意：文件头几 KB 是 [pkg.cargo] 等段落，[pkg.rust] 在文件更深处（整个文件约 900KB），
        # 必须完整下载后再解析；manifest 只用于取版本号，取完即删
        SayC $YELLOW '信息' '从 static.rust-lang.org 查询 stable 最新版本（下载 channel manifest 中）...'
        $tomlPath = Join-Path $tmpDir 'channel-rust-stable.toml'
        $fs = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create('https://static.rust-lang.org/dist/channel-rust-stable.toml')
            $req.Timeout = 60000
            $req.UserAgent = 'knife-script-manager'
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $fs = New-Object System.IO.FileStream($tomlPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            $buffer = New-Object byte[] (1024 * 256)
            while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $n)
            }
            $fs.Close(); $fs = $null
            $stream.Close()
            $resp.Close()
        } catch {
            if ($fs) { $fs.Close() }
            SayC $RED '异常' "查询 Rust stable 版本失败: $($_.Exception.Message)"
            SayC $RED '异常' '请检查网络连接后重试'
            exit 1
        }
        $tomlText = [System.IO.File]::ReadAllText($tomlPath)
        try { Remove-Item $tomlPath -Force -ErrorAction SilentlyContinue } catch { }
        # 主正则：匹配 [pkg.rust] 段下的 version（manifest 标准布局中 [pkg.rust] 紧跟 version 键）
        $vm = [regex]::Match($tomlText, '\[pkg\.rust\]\s*\r?\n\s*version\s*=\s*"([^"]+)"')
        # 备用：段首有其他字段/空行时，段内找第一个 version
        if (-not $vm.Success) {
            $vm = [regex]::Match($tomlText, '\[pkg\.rust\]\s*\r?\n(?:[^\r\n]*\r?\n)*?\s*version\s*=\s*"([^"]+)"')
        }
        if ($vm.Success) { $rustVer = $vm.Groups[1].Value }
        if (-not $rustVer) {
            SayC $RED '异常' '解析 channel-rust-stable.toml 失败，无法获取版本号'
            SayC $RED '异常' '可稍后重试；或先改用 beta / nightly 通道'
            exit 1
        }
        $downloadUrl = "https://static.rust-lang.org/dist/rust-$rustVer-$rustTarget.zip"
        $pkgName = "rust-$rustVer-$rustTarget.zip"
    } else {
        # beta / nightly：官方提供固定名 zip，直接下载
        $downloadUrl = "https://static.rust-lang.org/dist/rust-$Channel-$rustTarget.zip"
        $pkgName = "rust-$Channel-$rustTarget.zip"
    }
    SayC $YELLOW '信息' "下载链接: $downloadUrl"

    # ---- 下载（流式 + 进度）----
    # （$tmpDir 已在解析通道 URL 时创建）

    $fs = $null
    $zipPath = Join-Path $tmpDir $pkgName
    try {
        $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
        $req.Timeout = 60000
        $req.UserAgent = 'knife-script-manager'
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] (1024 * 256)
        $read = 0
        $nextReport = [DateTime]::Now.AddSeconds(5)
        SayC $YELLOW '信息' "开始下载: $pkgName（约 $([math]::Round($total / 1MB, 1)) MB）"
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $n)
            $read += $n
            # 按时间节流（每 5 秒一次）：小文件不会刷屏，大文件也不会半天不报
            # 用 [DateTime]::Now 而非 Get-Date —— 循环每 256KB 调用一次，cmdlet 开销明显
            if ([DateTime]::Now -ge $nextReport) {
                if ($total -gt 0) {
                    $pct = [int](($read * 100) / $total)
                    SayC $YELLOW '信息' "下载进度: $pct%（$([math]::Round($read / 1MB, 1)) / $([math]::Round($total / 1MB, 1)) MB）"
                } else {
                    SayC $YELLOW '信息' "下载进度: 已下载 $([math]::Round($read / 1MB, 1)) MB"
                }
                $nextReport = [DateTime]::Now.AddSeconds(5)
            }
        }
        $fs.Close(); $fs = $null
        $stream.Close()
        $resp.Close()
    } catch {
        if ($fs) { $fs.Close() }
        SayC $RED '异常' "下载失败: $($_.Exception.Message)"
        SayC $RED '异常' '请检查网络，或稍后重试'
        exit 1
    }
    SayC $GREEN '结果' "下载完成: $zipPath"

    # ---- 解压（ZipFile）----
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    SayC $YELLOW '信息' "解压到: $InstallDir（请稍候）"
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $InstallDir)
    } catch {
        SayC $RED '异常' "解压失败: $($_.Exception.Message)"
        SayC $RED '异常' '若目标位于 Program Files 等受保护目录，请换一个目录，或以管理员身份运行'
        exit 1
    }
    SayC $GREEN '结果' '解压完成'

    # 清理临时压缩包（失败不影响结果）
    try { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue } catch { }

    # ---- 定位本次解压出的 rust 目录 ----
    $found = Find-MatchingRust -Dir $InstallDir -Channel $Channel -Target $rustTarget
    if (-not $found) {
        SayC $RED '异常' "解压后未找到 rust 目录（含 rustc.exe），请检查目录: $InstallDir"
        exit 1
    }
    $rustHome = $found.FullName
}

$rustcExe = Join-Path $rustHome 'rustc\bin\rustc.exe'
if (-not (Test-Path $rustcExe)) {
    SayC $RED '异常' "未找到 rustc.exe，请检查目录: $rustHome"
    exit 1
}

# ---- 验证（rustc --version 输出 2>&1 合并后原色输出）----
SayC $YELLOW '信息' '验证 rustc --version:'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verOut = (& $rustcExe --version 2>&1 | Out-String)
} finally {
    $ErrorActionPreference = $oldEap
}
$verOut.TrimEnd()

# ---- 写环境变量 ----
# 管理员（工具已配 admin=true 提权）-> 写系统级 Machine；拒绝提权（非管理员）-> 回退用户级 User
$isAdmin = Test-IsAdministrator
$scope = if ($isAdmin) { 'Machine' } else { 'User' }
if (-not $isAdmin) {
    SayC $YELLOW '信息' '当前未以管理员运行，环境变量写入【用户级】。若系统 PATH 里还有其他 Rust，可能仍优先于本版本。'
}

if ($AddToPath -eq '是') {
    try {
        # Rust 有两个 bin 目录：{rustHome}\rustc\bin 与 {rustHome}\cargo\bin，都要写入
        $binDirs = @(
            (Join-Path $rustHome 'rustc\bin'),
            (Join-Path $rustHome 'cargo\bin')
        )

        # 顺序很重要（同 Install-Java.ps1）：先建好新条目（SCRIPT_MANAGER_ENV + PATH 前置），
        # 再清理旧 Rust 绝对路径。避免「旧路径删了、新条目没建成」导致 rustc/cargo 彻底找不到。
        # 1) 依次把两个 bin 目录前置进 SCRIPT_MANAGER_ENV，同时移除聚合变量里旧的 rust 条目
        #    （脚本块匹配 rustc\bin / cargo\bin 特征；java/python/node/go 等其他运行时条目保留不动）
        foreach ($binDir in $binDirs) {
            $binDirNorm = $binDir.TrimEnd('\')
            Add-ScriptManagerEnvEntry -BinDir $binDir -Scope $scope -IsOldEntry {
                param([string]$s)
                Test-IsRustBinPath $s
            }
            SayC $GREEN '结果' "已把 Rust bin 目录写入 SCRIPT_MANAGER_ENV（$scope）: $binDir"
        }

        # 2) 确保主作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（CMD 不会展开 %VAR% 引用）
        Ensure-PathHasScriptManagerEnv -Scope $scope
        SayC $GREEN '结果' "已把 SCRIPT_MANAGER_ENV 中的实际路径前置到 $scope PATH"

        # 3) 最后清理：从 Machine + User 两级 PATH 移除旧的 Rust bin 绝对路径（rustc\bin / cargo\bin 特征）
        #    此时新路径已就位，删旧路径不会造成 rustc/cargo 缺失。
        #    保护当前 SCRIPT_MANAGER_ENV 中的路径，避免把刚写进去的新 Rust 误删。
        $protectedPaths = @((Get-ScriptManagerEnvForScope -Scope 'Machine') + (Get-ScriptManagerEnvForScope -Scope 'User') | Select-Object -Unique)
        foreach ($oldScope in @('Machine', 'User')) {
            $rawOld = [Environment]::GetEnvironmentVariable('Path', $oldScope)
            if ([string]::IsNullOrWhiteSpace($rawOld)) { continue }
            $removed = @()
            $segmentsOld = @($rawOld -split ';' | ForEach-Object {
                $s = $_.TrimEnd('\')
                if ([string]::IsNullOrWhiteSpace($s)) { return $null }
                if ((Test-IsRustBinPath $s) -and -not ($protectedPaths -contains $s)) {
                    $script:removed += $s
                    return $null
                }
                return $s
            } | Where-Object { $_ } | Select-Object -Unique)
            $newRaw = $segmentsOld -join ';'
            # 防御：过滤后为空（该作用域 PATH 只剩 rust 项）时跳过写入，避免把 PATH 清空
            if (-not [string]::IsNullOrWhiteSpace($newRaw) -and $newRaw -ne $rawOld) {
                [Environment]::SetEnvironmentVariable('Path', $newRaw, $oldScope)
                foreach ($r in $removed) {
                    SayC $YELLOW '信息' "已从 $oldScope PATH 移除旧 Rust 路径: $r"
                }
            }
        }
    } catch {
        SayC $RED '异常' "更新 PATH 失败: $($_.Exception.Message)"
    }
}

Say ''
Say '=========================================='
if ($Channel -eq 'stable') {
    SayC $GREEN '结果' "Rust stable（$rustVer）安装完成"
} else {
    SayC $GREEN '结果' "Rust $Channel 安装完成"
}
SayC $GREEN '结果' "Rust 目录: $rustHome"
if ($AddToPath -eq '是') {
    SayC $GREEN '结果' "已加入 SCRIPT_MANAGER_ENV: $(Join-Path $rustHome 'rustc\bin') 和 $(Join-Path $rustHome 'cargo\bin')"
    SayC $YELLOW '信息' '工具管理的所有运行时 bin 统一记录在 SCRIPT_MANAGER_ENV，PATH 中写入实际路径'
    SayC $YELLOW '信息' "查看当前内容（新终端）: echo %SCRIPT_MANAGER_ENV%"
    SayC $YELLOW '信息' "切换 Rust 通道: 更新 SCRIPT_MANAGER_ENV 后，重新运行安装脚本同步 PATH"
    SayC $YELLOW '信息' "环境变量已写入【$scope 级】，新打开的终端才会生效"
}
SayC $YELLOW '提示' 'MSVC 版 rustc 依赖 VC++ 运行库；若本机未装过 Visual Studio 或 vc_redist，编译时可能提示缺少 dll'
Say '=========================================='

