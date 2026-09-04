# build.ps1 - 一键发布 knife-script-manager
# 产物进入 dist/，包含两个版本（目录结构一致，区别仅在于是否内置 .NET）：
#   dist/ScriptManagerPortable/  自包含单文件 exe（内置 .NET 运行时，开箱即用）
#   dist/ScriptManager/          依赖框架版（不内置 .NET，需用户机器已安装 .NET 运行时）
# 两个目录均含：ScriptManager.exe + script\（脚本目录）+ lib\（第三方依赖，如 jar）+ config\（用户配置文件），与 exe 同级，用户可编辑。
# 注：script/ 与 lib/ 复制时会跳过 .gitignore 命中的文件（如本地 IDE 生成的 *.iml / .idea/），确保本地 dist 与干净发布包一致。
# cache\（缓存）与 log\（日志）不预生成，运行时由程序在 exe 同级自动创建。
#
# 用法：
#   .\build.ps1                        # 自动探测 dotnet 与架构，默认构建 Both
#   .\build.ps1 -DotNet "自定义路径"    # 手动指定 dotnet
#   .\build.ps1 -InstallSdk            # 未装目标 .NET SDK 时自动下载安装（约数百 MB）
#   .\build.ps1 -Runtime win-x64       # 手动指定目标 runtime
#   .\build.ps1 -Edition Portable      # 仅构建便携版（自包含，内置 .NET）
#   .\build.ps1 -Edition Standard      # 仅构建标准版（依赖框架，需用户机器装 .NET）
#   .\build.ps1 -Edition Both          # 便携版 + 标准版都构建（默认）
#   .\build.ps1 -Launch                 # 构建完成后自动启动 exe（默认不启动）

param(
    [string]$DotNet = "",
    [string]$Runtime = "",
    [string]$Configuration = "Release",
    [switch]$InstallSdk,
    [ValidateSet("Portable", "Standard", "Both")]
    [string]$Edition = "Both",
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

# 当前正在打包的目标目录（exe 同级目录），失败时用于定位 error.log 的落盘位置
$script:CurrentOutDir = $null

# 把打包异常写入「exe 同级 error.log」（追加，含时间戳），并在屏幕红字提示。
# 失败时 exe 可能尚未生成，故优先写 $script:CurrentOutDir，其次 dist/，再退项目根。
function Write-BuildErrorLog {
    param([string]$message)
    $dir = $script:CurrentOutDir
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path $dir)) {
        if (Test-Path $distDir) { $dir = $distDir } else { $dir = $rootDir }
    }
    $logFile = Join-Path $dir "error.log"
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] $message"
    try { Add-Content -Path $logFile -Value $entry -Encoding UTF8 } catch { }
    Write-Host "==> 已记录错误到：$logFile" -ForegroundColor Red
}

# ---- 校验 dotnet SDK 版本 ----
# ⚠️ $TargetMajor 必须与 csproj 的 TargetFramework（net10.0-windows）保持一致。
$TargetMajor = 10

# 判断某个 dotnet 是否含指定主版本的 SDK
function Test-DotNetSdk {
    param([string]$exe, [int]$major)
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    if (-not (Test-Path $exe)) { return $false }
    $sdks = & $exe --list-sdks 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $sdks) { return $false }
    return [bool]($sdks | Where-Object { $_ -match "^\s*$major\." })
}

# 找不到目标版本 SDK 时：打印可操作的诊断信息并终止。
# 不继续构建——否则用户只会看到晦涩的 NETSDK1045。
function Show-SdkError {
    param([string]$exe, [int]$major)
    Write-Host ""
    Write-Host "==> 错误：未找到 .NET $major SDK，无法构建 net$major.0-windows 项目。" -ForegroundColor Red
    if ($exe -and (Test-Path $exe)) {
        $list = & $exe --list-sdks 2>$null
        if ($list) {
            Write-Host "    $exe 当前安装的 SDK：" -ForegroundColor Yellow
            $list | ForEach-Object { Write-Host "      $_" }
        }
    }
    Write-Host ""
    Write-Host "    方式一（推荐）：让脚本自动下载安装，加 -InstallSdk：" -ForegroundColor Cyan
    Write-Host "            .\build.ps1 -InstallSdk" -ForegroundColor Cyan
    Write-Host "    方式二：自行安装 -> https://dotnet.microsoft.com/download" -ForegroundColor Cyan
    Write-Host "            装在非默认目录时用 -DotNet 指定：" -ForegroundColor Cyan
    Write-Host "            .\build.ps1 -DotNet `"$env:USERPROFILE\dotnet$major\dotnet.exe`"" -ForegroundColor Cyan
    Write-Host ""
    Write-BuildErrorLog "未找到 .NET $major SDK，无法构建 net$major.0-windows 项目。请运行 .\build.ps1 -InstallSdk 自动安装，或自行安装 .NET $major SDK。"
    exit 1
}

# 自动下载安装 .NET SDK（用官方 dotnet-install.ps1；它是纯 PowerShell，不依赖已有 .NET）
function Install-DotNetSdk {
    param([string]$installDir, [int]$major)

    $exe = Join-Path $installDir "dotnet.exe"
    if (Test-DotNetSdk -exe $exe -major $major) { return $exe }

    Write-Host "==> 自动安装 .NET $major SDK 到：$installDir" -ForegroundColor Cyan
    Write-Host "    （SDK 约数百 MB，视网络情况需数分钟）" -ForegroundColor Yellow

    # PowerShell 5.1 默认可能仍用 TLS 1.0/1.1，而 dot.net 已只接受 TLS 1.2+
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $installer = Join-Path $env:TEMP "dotnet-install.ps1"
    try {
        if (-not (Test-Path $installer)) {
            Write-Host "    下载安装脚本 dotnet-install.ps1 ..."
            Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $installer -UseBasicParsing
        }
        Write-Host "    安装 .NET $major SDK ..."
        & $installer -Channel "$major.0" -InstallDir $installDir -NoPath
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    安装脚本返回非零退出码：$LASTEXITCODE" -ForegroundColor Red
            return $null
        }
    }
    catch {
        Write-Host "    自动安装失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    （多为网络问题；可挂代理后重试，或用方式二自行安装）" -ForegroundColor Yellow
        return $null
    }

    if (Test-DotNetSdk -exe $exe -major $major) {
        Write-Host "==> .NET $major SDK 安装完成" -ForegroundColor Green
        return $exe
    }
    Write-Host "    安装完成但未检测到 .NET $major SDK，请检查安装输出。" -ForegroundColor Red
    return $null
}

# ---- 自动探测 dotnet 路径 ----
# 策略：优先选“能列出 SDK、且含目标主版本 SDK”的 dotnet；找不到则直接终止并给出安装指引。
# 这样 Windows 物理机（C:\Program Files\dotnet 仅运行时）与 Mac 虚拟机（PATH 或 /usr/local/share/dotnet 等）都能自适应。
#
# ⚠️ 为什么必须校验主版本：只检查“能列出 SDK”是不够的——若选中 .NET 8 的 dotnet 去构建 net10.0，
#    会报 NETSDK1045「当前 .NET SDK 不支持面向 .NET 10.0」，错误信息与实际原因相距甚远。
if ([string]::IsNullOrWhiteSpace($DotNet)) {
    # 用 $env:USERPROFILE 而非硬编码 C:\Users\PC，保证换机器/换用户名同样可用
    $candidates = @(
        "C:\Program Files\dotnet\dotnet.exe",
        "$env:USERPROFILE\dotnet$TargetMajor\dotnet.exe",
        "$env:USERPROFILE\dotnet8\dotnet.exe",
        "C:\Program Files (x86)\dotnet\dotnet.exe",
        "/usr/local/share/dotnet/dotnet",
        "/opt/homebrew/dotnet/dotnet",
        "$env:HOME/.dotnet/dotnet"
    )
    $fallback = $null
    # 逐候选检查：存在且能列出 SDK 才采用；优先采用含目标主版本的
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        if (Test-Path $c) {
            $sdks = & $c --list-sdks 2>$null
            if ($LASTEXITCODE -eq 0 -and $sdks) {
                if ($null -eq $fallback) { $fallback = $c }   # 记住第一个可用的，供兜底
                if ($sdks | Where-Object { $_ -match "^\s*$TargetMajor\." }) {
                    $DotNet = $c
                    break
                }
            }
        }
    }
    # 都没装目标版本则回退到任意可用的（构建会报原始错误，但至少有明确警告）
    if ([string]::IsNullOrWhiteSpace($DotNet)) {
        # 带了 -InstallSdk：先自动下载安装到用户目录，再探测一次
        if ($InstallSdk) {
            $autoDir = Join-Path $env:USERPROFILE "dotnet$TargetMajor"
            $autoExe = Install-DotNetSdk -installDir $autoDir -major $TargetMajor
            if ($autoExe -and (Test-DotNetSdk -exe $autoExe -major $TargetMajor)) {
                $DotNet = $autoExe
            }
        }
        # 仍未就位：用错版本构建只会报晦涩的 NETSDK1045，远不如直接终止并给出可操作指引。
        if ([string]::IsNullOrWhiteSpace($DotNet)) {
            Show-SdkError -exe $fallback -major $TargetMajor
        }
    }
} elseif (-not (Test-DotNetSdk -exe $DotNet -major $TargetMajor)) {
    # 用户用 -DotNet 手动指定，但版本不对：若带了 -InstallSdk 则改用自动安装版
    if ($InstallSdk) {
        $autoDir = Join-Path $env:USERPROFILE "dotnet$TargetMajor"
        $autoExe = Install-DotNetSdk -installDir $autoDir -major $TargetMajor
        if ($autoExe -and (Test-DotNetSdk -exe $autoExe -major $TargetMajor)) {
            $DotNet = $autoExe
        }
    }
    # 仍未就位：构建注定失败，终止并给出明确指引
    if (-not (Test-DotNetSdk -exe $DotNet -major $TargetMajor)) {
        # 注：elseif/else 换行在多数 PowerShell 版本下可用，但与 } 同行是官方推荐写法，避免解析差异
        Show-SdkError -exe $DotNet -major $TargetMajor
    }
}

# ---- 自动探测目标架构 ----
if ([string]::IsNullOrWhiteSpace($Runtime)) {
    $arch = $env:PROCESSOR_ARCHITECTURE
    $Runtime = if ($arch -eq "ARM64") { "win-arm64" } else { "win-x64" }
}

# 脚本位于项目根目录
$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$srcDir = Join-Path $rootDir "src"
$publishDir = Join-Path $rootDir "publish"
$distDir = Join-Path $rootDir "dist"

if (-not (Test-Path $srcDir)) {
    Write-Error "未找到 src 目录: $srcDir"
    exit 1
}

try {
# 关闭已打开的 exe，避免文件被占用导致覆盖失败
$running = Get-Process -Name "ScriptManager" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "==> 正在关闭已打开的 ScriptManager.exe ..."
    $running | Stop-Process -Force
    Start-Sleep -Seconds 1
}

Write-Host "==> 使用 dotnet: $DotNet"
Write-Host "==> 目标 runtime: $Runtime"
Write-Host "==> 源码目录: $srcDir"

# ---- 发布函数 ----
# $selfContained: true=自包含（内置 .NET，便携版）；false=依赖框架（需用户机器装 .NET）
function Publish-Exe {
    param([bool]$selfContained)
    $sc = if ($selfContained) { "true" } else { "false" }
    Write-Host ""
    Write-Host "==> 发布（$sc 内置 .NET）-> $publishDir"
    # 用 cmd /c 包装执行，避免 PowerShell 把 dotnet 的 stderr 输出误报为 NativeCommandError/RemoteException，
    # 从而掩盖真实编译结果（成功/失败）。cmd 内部 2>&1 让 stdout/stderr 原样透出，退出码由 $LASTEXITCODE 捕获。
    cmd /c "`"$DotNet`" publish `"$srcDir`" -c $Configuration -r $Runtime --self-contained $sc -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o `"$publishDir`" 2>&1"
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "==> 发布失败（self-contained=$sc），退出码 $exitCode。以上 dotnet 输出中的错误（error CSxxxx / NETSDKxxxx）即为根因。" -ForegroundColor Red
        Write-BuildErrorLog "发布失败（self-contained=$sc），退出码 $exitCode。详见上方 dotnet 输出中的 error CSxxxx / NETSDKxxxx。"
        exit $exitCode
    }
}

# ---- 干净复制：跳过 .gitignore 命中的文件/目录 ----
# 组装 dist 时，script/ 与 lib/ 可能含有本地 IDE 生成的垃圾（如 *.iml、.idea/），它们已被仓库
# .gitignore 忽略、不进版本库，但本地磁盘上存在；若直接 Copy-Item 整目录会连同打进发布包，
# 导致本地 dist 与 CI / GitHub Release 的干净包不一致（曾出现本地 dist 混入 3 个 .iml、比发布包多 21KB）。
# 这里改为对每个文件用 `git check-ignore` 判定，命中则跳过，使 dist 与“干净源码树”完全一致。
# git 不可用（如非仓库环境）时退化为跳过已知 IDE 垃圾模式（*.iml / .idea / .vs / bin / obj 等）。
function Copy-CleanTree {
    param([string]$src, [string]$dst)

    # 是否在 git 工作树内（决定用 .gitignore 还是退化规则）
    $useGit = $false
    try {
        & git -C $rootDir rev-parse --is-inside-work-tree 2>$null | Out-Null
        $useGit = ($LASTEXITCODE -eq 0)
    } catch { $useGit = $false }

    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }

    $files = Get-ChildItem -LiteralPath $src -Recurse -Force | Where-Object { -not $_.PSIsContainer }
    foreach ($f in $files) {
        # 源目录下的相对路径（保留子目录结构）
        $rel = $f.FullName.Substring($src.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $skip = $false
        if ($useGit) {
            # git check-ignore 对“被忽略”的文件/目录返回退出码 0（含其祖先目录被忽略的情况）
            $relGit = $rel -replace '\\', '/'
            & git -C $rootDir check-ignore -q -- $relGit 2>$null
            $skip = ($LASTEXITCODE -eq 0)
        } else {
            # 退化规则：跳过已知 IDE / 编译垃圾
            if ($rel -match '\.iml$' `
                -or $rel -match '[/\\]\.idea($|[/\\])' -or $rel -match '[/\\]\.vs($|[/\\])' `
                -or $rel -match '[/\\]bin($|[/\\])' -or $rel -match '[/\\]obj($|[/\\])' `
                -or $rel -match '\.user$' -or $rel -match '\.suo$' `
                -or $f.Name -eq 'Thumbs.db' -or $f.Name -eq 'Desktop.ini') {
                $skip = $true
            }
        }
        if ($skip) { continue }

        $target = Join-Path $dst $rel
        $td = Split-Path $target -Parent
        if (-not (Test-Path $td)) { New-Item -ItemType Directory -Path $td -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName $target -Force
    }
}

# ---- 组装交付目录 ----
# $outDir: 目标子目录（如 dist/ScriptManagerPortable）
function Assemble-Dist {
    param([string]$outDir, [bool]$selfContained)

    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    else {
        # 清空目标目录。部分子项（如正被其他进程占用的 script/）可能暂时无法删除，
        # 此时跳过该项错误继续，后续 Copy-Item -Force 会覆盖其余内容，不影响产物正确性。
        Remove-Item "$outDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 1) 主程序 exe
    $publishedExe = Join-Path $publishDir "ScriptManager.exe"
    if (-not (Test-Path $publishedExe)) {
        Write-Error "未找到发布产物: $publishedExe"
        Write-BuildErrorLog "未找到发布产物: $publishedExe（发布步骤可能未成功完成）"
        exit 1
    }
    Copy-Item $publishedExe (Join-Path $outDir "ScriptManager.exe") -Force
    $sizeMB = [math]::Round((Get-Item $publishedExe).Length / 1MB, 1)
    Write-Host "==> 已复制主程序 -> $(Join-Path $outDir 'ScriptManager.exe') ($sizeMB MB)"

    # 2) 脚本目录：script/ -> outDir/script/
    $scriptSrc = Join-Path $rootDir "script"
    $scriptDst = Join-Path $outDir "script"
    if (Test-Path $scriptSrc) {
        # 先尝试删除旧目标目录；若被占用导致删除失败，也不影响后续复制内容。
        if (Test-Path $scriptDst) { Remove-Item $scriptDst -Recurse -Force -ErrorAction SilentlyContinue }
        # 确保目标目录存在，然后复制“源目录下的内容”而不是目录本身，避免残留目标目录时变成 script/script。
        if (-not (Test-Path $scriptDst)) { New-Item -ItemType Directory -Path $scriptDst -Force | Out-Null }
        # 干净复制：跳过 .gitignore 命中的 IDE 垃圾（如 *.iml），使 dist 与发布包一致
        Copy-CleanTree -src $scriptSrc -dst $scriptDst
        Write-Host "==> 已复制脚本目录 -> $scriptDst"
    }

    # 2.5) 第三方依赖目录：lib/ -> outDir/lib/（与 exe 同级，供脚本通过 SCRIPT_MANAGER_LIB 引用 jar 等）
    $libSrc = Join-Path $rootDir "lib"
    $libDst = Join-Path $outDir "lib"
    if (-not (Test-Path $libDst)) { New-Item -ItemType Directory -Path $libDst -Force | Out-Null }
    if (Test-Path $libSrc) {
        # 先尝试删除旧目标目录；若被占用导致删除失败，也不影响后续复制内容。
        if (Test-Path $libDst) { Remove-Item $libDst -Recurse -Force -ErrorAction SilentlyContinue }
        # 重新创建目标目录，再复制内容，避免残留目标目录时变成 lib/lib。
        if (-not (Test-Path $libDst)) { New-Item -ItemType Directory -Path $libDst -Force | Out-Null }
        # 干净复制：跳过 .gitignore 命中的文件，使 dist 与发布包一致（原 .gitkeep 占位本就不进交付包）
        Copy-CleanTree -src $libSrc -dst $libDst
        Write-Host "==> 已复制依赖目录 -> $libDst"
    }

    # 2.55) 图标资源（assets/images）已全部内嵌进 exe（csproj 的 EmbeddedResource/Resource），
    #       运行期通过 GetManifestResourceStream / pack URI 从程序集加载，无需磁盘目录，故不复制。

    # 2.6) 确保 lib 下各语言约定子目录存在（缺失则自动创建）。
    # 约定子目录名固定，放错名称（如 java1/nodejs）不生效；此处仅兜底创建标准约定目录。
    # python 的编译扩展（如 Pillow 的 .pyd）分架构，故额外在其下创建 arm / amd 子目录，
    # 即便当前依赖为空也一并创建，便于后续按架构放入原生包。
    $libLangDirs = @("java", "python", "node")
    foreach ($lang in $libLangDirs) {
        $langDir = Join-Path $libDst $lang
        if (-not (Test-Path $langDir)) {
            New-Item -ItemType Directory -Path $langDir -Force | Out-Null
            Write-Host "==> 已自动创建约定依赖子目录 -> $langDir"
        }
        if ($lang -eq "python") {
            foreach ($arch in @("arm", "amd")) {
                $archDir = Join-Path $langDir $arch
                if (-not (Test-Path $archDir)) {
                    New-Item -ItemType Directory -Path $archDir -Force | Out-Null
                    Write-Host "==> 已自动创建约定依赖子目录 -> $archDir"
                }
            }
        }
    }

    # 3) 用户配置文件：config.ini -> outDir/config/config.ini
    #    优先用仓库根 config.ini；缺失时退化用 config.ini.example（含默认注释，确保交付包自带配置范本）
    $configDir = Join-Path $outDir "config"
    $configDst = Join-Path $configDir "config.ini"
    $configSrc = $null
    if (Test-Path (Join-Path $rootDir "config.ini")) {
        $configSrc = Join-Path $rootDir "config.ini"
    } elseif (Test-Path (Join-Path $rootDir "config.ini.example")) {
        $configSrc = Join-Path $rootDir "config.ini.example"
    }
    if ($configSrc) {
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        Copy-Item $configSrc $configDst -Force
        Write-Host "==> 已复制用户配置文件 -> $configDst (来源: $(Split-Path $configSrc -Leaf))"
    }

    # 2.7) 文件夹变色资源：assets/fColors.icl + assets/folder-icons/*.ini
    #      -> outDir/config/（exe 同级，与 config.ini 同处程序自管目录），并设为 Hidden：
    #         交付目录不再额外留一个 assets\；隐藏后也不干扰用户查看 config\config.ini。
    #      运行期由 src/FolderCustomizer.cs 从 ExeDir\config\ 读取并生成各目录 desktop.ini
    #      （其它目录指向 ..\config\fColors.icl；config 自身指向 .\fColors.icl）。
    $assetsSrc = Join-Path $rootDir "assets"
    if (Test-Path $assetsSrc) {
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        # 仅复制文件夹变色相关文件：fColors.icl + folder-icons/ 下的模板；
        # 其余 assets（images 等）已内嵌进 exe，不复制。
        $iconLib = Join-Path $assetsSrc "fColors.icl"
        if (Test-Path $iconLib) {
            $dst = Join-Path $configDir "fColors.icl"
            Copy-Item $iconLib $dst -Force
            $a = [IO.File]::GetAttributes($dst)
            [IO.File]::SetAttributes($dst, $a -bor [IO.FileAttributes]::Hidden)
            Write-Host "==> 已复制文件夹图标库（Hidden）-> $dst"
        } else {
            Write-Host "==> 警告：未找到 assets\fColors.icl，文件夹变色功能将不可用" -ForegroundColor Yellow
        }
        $tplSrc = Join-Path $assetsSrc "folder-icons"
        if (Test-Path $tplSrc) {
            $tplDst = Join-Path $configDir "folder-icons"
            if (-not (Test-Path $tplDst)) { New-Item -ItemType Directory -Path $tplDst -Force | Out-Null }
            Copy-Item (Join-Path $tplSrc "*.ini") $tplDst -Force
            Get-ChildItem -LiteralPath $tplDst -Filter *.ini | ForEach-Object {
                $t = [IO.File]::GetAttributes($_.FullName)
                [IO.File]::SetAttributes($_.FullName, $t -bor [IO.FileAttributes]::Hidden)
            }
            Write-Host "==> 已复制 desktop.ini 模板（Hidden）-> $tplDst"
        }
    } else {
        Write-Host "==> 警告：未找到 assets/，文件夹变色功能将不可用" -ForegroundColor Yellow
    }

}

# ---- 按所选版本构建 ----
$portableDir = Join-Path $distDir "ScriptManagerPortable"
$simpleDir   = Join-Path $distDir "ScriptManager"

if ($Edition -eq "Portable" -or $Edition -eq "Both") {
    Write-Host ""
    Write-Host "########## 构建便携版（自包含 / 内置 .NET）##########"
    $script:CurrentOutDir = $portableDir
    Publish-Exe -selfContained $true
    Assemble-Dist -outDir $portableDir -selfContained $true
}

if ($Edition -eq "Standard" -or $Edition -eq "Both") {
    Write-Host ""
    Write-Host "########## 构建标准版（依赖框架 / 不内置 .NET）##########"
    $script:CurrentOutDir = $simpleDir
    Publish-Exe -selfContained $false
    Assemble-Dist -outDir $simpleDir -selfContained $false
}

# 清理根目录可能残留的旧 exe（确保只存在于 dist/）
$rootExe = Join-Path $rootDir "launcher.exe"
if (Test-Path $rootExe) { Remove-Item $rootExe -Force }
$rootExe2 = Join-Path $rootDir "ScriptManager.exe"
if (Test-Path $rootExe2) { Remove-Item $rootExe2 -Force }

Write-Host ""
Write-Host "==> 完成。交付目录: $distDir"
if ($Edition -eq "Portable" -or $Edition -eq "Both") {
    Write-Host "    - $portableDir  （自包含，内置 .NET，开箱即用）"
}
if ($Edition -eq "Standard" -or $Edition -eq "Both") {
    Write-Host "    - $simpleDir    （依赖框架，需用户机器安装 .NET 运行时）"
}
Write-Host "    目录结构一致：ScriptManager.exe + script\ + lib\ + config\，与 exe 同级，用户可编辑。"
Write-Host "    （cache\ 与 log\ 不打包，运行时由程序自动创建；文件夹变色资源 fColors.icl 与模板随构建放入 config\ 并设为 Hidden）"

# 打包成功，清理可能残留的 error.log（若有），避免误导用户以为上次失败
foreach ($d in @($portableDir, $simpleDir)) {
    $el = Join-Path $d "error.log"
    if (Test-Path $el) { Remove-Item $el -Force -ErrorAction SilentlyContinue }
}

} catch {
    # 任何未预期异常：记录到 exe 同级 error.log 并终止，exit code 非 0
    Write-BuildErrorLog "打包过程中发生未预期异常：$($_.Exception.Message)`n$($_.ScriptStackTrace)"
    Write-Host "==> 打包失败，详见 error.log" -ForegroundColor Red
    exit 1
}

# 打包成功后按需自动启动（由 -Launch 控制；Both 时默认启动标准版）
if ($Launch) {
    $launchDir = if ($Edition -eq "Portable") { $portableDir } else { $simpleDir }
    $launchExe = Join-Path $launchDir "ScriptManager.exe"
    Write-Host "==> 正在启动 $launchExe ..."
    Start-Process -FilePath $launchExe
}
