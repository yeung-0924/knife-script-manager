# knife-script-manager

Windows 双击即用的脚本管理器。读取 exe 同级 `script/index.json` 列出脚本，点击「执行」即可运行，右侧实时显示日志与报错。

## 目录结构
```
knife-script-manager/
  script/                 # 脚本与配置（与 exe 同级分发，用户可直接编辑）
    index.json            # 脚本列表配置（数组）
    *.cmd / *.bat / *.ps1 / *.go / *.rs / *.js / *.py / *.java / *.sh  # 你的脚本（按语言扩展名）
  src/                    # C# 源代码（重建 exe 用）
  publish/                # 发布缓存（自动生成，可删）
  dist/                   # 交付目录（自动生成）
    ScriptManagerPortable/   # 便携版：自包含单文件 exe（内置 .NET，开箱即用）
    ScriptManager/          # 标准版：依赖框架（不内置 .NET，需用户机器装 .NET 运行时）
  .tmp/                   # 临时文件（自动生成，忽略）
  build.ps1               # 一键构建脚本（生成 dist/）
```

## 脚本来源（单一来源）

exe 启动后只加载**一处**脚本：exe 同级的 `script/` 目录（含 `index.json` 与全部脚本）。目录树只渲染这一个来源，按 `group` 分组展示，不再区分"内置/自定义"。

- `script/` 与 `ScriptManager.exe` 同级分发，**不嵌入 exe**（改脚本无需重新构建）。
- 增删脚本、改 `.ps1`、改 `index.json` 均即时生效（重新点"刷新"或重启 exe 即可）。
- 若 `script/index.json` 缺失，界面仅给出提示，不会崩溃。

**导出**（左侧"导出"按钮）：把整个 `script/` 目录原样复制到用户选择的目录（时间戳命名，重复导出不覆盖），结构保持 `script/`（含 `index.json` 与脚本），导出成功后自动打开资源管理器并选中该目录。

## 如何重新构建 exe

### 1. 需要 .NET 10 SDK
开发机 SDK 路径：**`C:\Users\PC\dotnet10\dotnet.exe`**
（若换机器，去 https://dot.net 装 .NET 10 SDK，然后用 `dotnet` 代替下面的路径）

### 2. 执行发布命令（一键脚本 build.ps1）
项目根目录已提供 `build.ps1`，自动探测 dotnet 与架构、publish 到 `publish\`，再组装两个交付目录。三条命令：

**构建便携版（自包含，内置 .NET，约 154MB，开箱即用）：**
```
powershell -ExecutionPolicy Bypass -NoProfile -File "d:\Workspace\knife\knife-script-manager\build.ps1" -Edition Portable
```

**构建标准版（依赖框架，不内置 .NET，需用户机器已装 .NET 10 运行时）：**
```
powershell -ExecutionPolicy Bypass -NoProfile -File "d:\Workspace\knife\knife-script-manager\build.ps1" -Edition Standard
```

**两者都构建（默认）：**
```
powershell -ExecutionPolicy Bypass -NoProfile -File "d:\Workspace\knife\knife-script-manager\build.ps1"
```

脚本会自动把 `ScriptManager.exe` 放入 `dist/ScriptManagerPortable/`（或 `dist/ScriptManager/`），并把 `script/` 与 `config/` 整体复制到对应目录（与 exe 同级，用户可编辑）。

换机器时（SDK 路径不同）可加 `-DotNet "新路径\dotnet.exe"`；指定架构用 `-Runtime win-x64`（或 `win-arm64`）：
```
.\build.ps1 -Edition Both -DotNet "新路径\dotnet.exe" -Runtime win-x64
```

**交付**：两个目录结构一致，均为 `ScriptManager.exe` + `script\`（脚本与 `index.json`）+ `config\`（用户配置）。把对应目录整体发给用户，**双击 `ScriptManager.exe` 即用**：
- 选 **便携版**：目标机器无需安装 .NET，文件较大。
- 选 **标准版**：目标机器需先装 .NET 10 运行时，文件较小。

**方式 B（手动命令）**：在 `src/` 目录下运行（便携版示例）：
```
C:\Users\PC\dotnet10\dotnet.exe publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish
```
标准版把 `--self-contained true` 改为 `--self-contained false` 即可。发布成功后，把 `publish\ScriptManager.exe` 复制到 `dist\ScriptManagerPortable\`（或 `dist\ScriptManager\`），并把 `script/` 与 `config/` 复制过去。

> 发布是耗时操作，前台可能被环境拦截。可改为异步执行：
> ```
> cmd /c start "" /min cmd /c "C:\Users\PC\dotnet10\dotnet.exe publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish > .tmp/_pub.log 2>&1"
> ```
> 然后看 `.tmp/_pub.log` 是否出现 `ScriptManager -> ...\publish\`，完成后再把产物放入 `dist/`。

## 参数说明
| 参数 | 作用 |
|---|---|
| `-Edition Portable` | 仅构建便携版（自包含，内置 .NET） |
| `-Edition Standard` | 仅构建标准版（依赖框架，需用户机器装 .NET） |
| `-Edition Both` | 便携版 + 标准版都构建（默认） |
| `-DotNet "路径"` | 手动指定 dotnet（SDK）路径 |
| `-Runtime win-x64` | 目标 Windows 64 位（ARM 机器用 `win-arm64`） |
| `--self-contained true` | 打包运行时，**目标机器无需安装 .NET**（对应 Portable） |
| `-p:PublishSingleFile=true` | 合并为单个 exe |
| `-p:IncludeNativeLibrariesForSelfExtract=true` | 原生库也打进单文件 |
| `-o ..\publish` | 输出目录 |

## 如何添加 / 维护脚本
1. 把 `.cmd` / `.bat` / `.ps1` / `.go` / `.rs` 等脚本放进 `script/`（命名风格见 `script/README.md` 的「文件命名约定」：PowerShell/pwsh 用 PascalCase，Go/Rust 用 snake_case）
2. 编辑 `script/index.json`（嵌套数组，用 `children` 表达目录层级）：

   目录节点只需 `name` + `children`；脚本节点无 `children`，字段如下：

```json
[
  {
    "name": "分组名",        // 目录节点：有 children 即视为目录
    "children": [
      {
        "name": "显示名",
        "path": "./xxx.ps1",   // 支持 ./ 前缀，相对 script 目录
        "hide": false,          // 布尔，true 则隐藏不显示
        "lang": "powershell",   // 脚本语言：powershell/pwsh/cmd/python/java/bash/node/go/rust，决定目录树图标
        "admin": false,          // 布尔，true 则以管理员身份运行
        "params": [             // 可选，参数声明（UI 据此生成输入控件）
          { "name": "PORT", "label": "端口号", "default": "8080", "required": true, "placeholder": "如 8080" },
          { "name": "PROTOCOL", "label": "协议", "default": "TCP", "options": ["TCP","UDP"] }
        ]
      }
    ]
  }
]
```
3. 重新构建 exe 使 `script/` 同步到 `dist/`；或直接编辑已分发的 `script/`，重新点"刷新"或重启 exe 即时生效（无需重新构建）。

> JSON 必须用双引号。

## 已知限制
- 「管理员执行」（`runas`）无法捕获实时日志，日志面板仅提示在弹窗查看。
- exe 由源码发布生成，**不纳入 git**，仓库只存 `src/` 与配置。
