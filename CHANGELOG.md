# 更新日志（Changelog）

## [Unreleased]

### 界面与交互
- 顶部新增工具栏：`文件`（打开 / 导出，从脚本列表移入并保留图标）、`设置 ▸ 编辑配置...`（调出 config.ini 编辑弹窗）。
- 配置编辑弹窗重构：
  - 目录/文件项改为只读浏览式选择框（只能浏览、不可手输）；未自定义时显示默认相对路径占位符（script\index.json / lib / runtime / cache / log），由 AppConfig 在读取时回落。
  - 每项右侧「×」可清除当前选择、恢复默认相对路径；「默认值」一键全部还原。
  - 加回「默认执行超时(秒)」可编辑数字框（弹窗内唯一允许手输项），占位符「0（不限制）」，仅允许数字输入。
  - 标题去掉「 - config.ini」后缀；移除原「默认：…」说明行。
- 参数下拉框：切换其他窗口不再置顶屏幕；点击输入框或选项之外任意位置即收起。

### 配置（config.ini）
- 脚本索引由双键（`default_script_file` + `user_script_file`）合并为单一 `script_index_file`：移除 `default_script_file`；原 `user_script_file` 重命名为 `script_index_file`（旧值自动迁移）。默认值仍为 `script\setminus.json`。
- 「文件▸打开」与「设置▸编辑配置▸脚本索引文件」现在写同一个键、效果完全一致；配置编辑器首行 label 改为「脚本索引文件」。

### 脚本运行时
- 运行时环境检测改为逐项流式输出（不再憋约 10 秒后一次性刷出）。
- 安装脚本（PS7 / Java / Node / Python / Go / Rust）标题对齐 index.json 名称；PS7 下载源尊重用户所选、失败如实提示原因与建议（不再回退 GitHub 源）。

## [1.0.0] - 2026-09-03
首个公开版本（以当前代码为基准重新起步，整合此前实验性 1.0.0 / 1.1.0 的全部能力）。

### 脚本管理
- 读取 exe 同级 `script/index.json` 管理多语言脚本（PowerShell / Bat / Python / Java / Node 等），按 `group` 分组展示，配套实时日志与报错面板。
- 脚本执行超时自动终止：超过设定时长仍未结束则强杀进程树（含子进程）。单脚本可在 `index.json` 设 `timeout`（秒）单独控制；全局 `config.ini` 的 `default_timeout` 兜底；两者皆未设或值为 0/负数时**不限制**（兼容既有长时脚本）。

### 目录树工具条
- 新增「打开」按钮（folder-open 图标）：直接选择脚本索引文件 `index.json` 加载任意脚本目录（结构同内置 `script` 目录）；文件不存在/解析为空时目录树不渲染，且不弹窗报错。
- 选中有效 `index.json` 后写 `config.ini` 的 `[script] user_script_file`（绝对路径），重启自动加载该文件（文件失效则回退 `default_script_file`），无需每次手动重新选择。
- 已移除「刷新」按钮（启动即按配置加载，无需手动刷新）。

### 配置（config.ini，[script] 节）
- `default_script_file`：默认脚本索引文件，默认 `script\index.json`。
- `user_script_file`：记忆「打开」选择的索引文件（绝对路径），优先于 `default_script_file`。
- `lib_dir` / `runtime_dir` / `cache_dir` / `log_dir`：第三方依赖、运行时安装、缓存、日志目录（相对路径相对 exe 目录，绝对/UNC 路径直接使用）。
- `default_timeout`：脚本默认执行超时（秒），0 表示不限制。

### 交付与开源合规
- 便携版（自包含 .NET）与标准版双交付：便携版内置运行时、开箱即用；标准版依赖本机已装 .NET 10。
- README 去除私人路径、补充「配置文件」章节；新增 `config.ini.example` 模板（缺配置时自动复制）、`THIRD-PARTY.md`（登记 Hutool Apache-2.0 许可证与来源）；新增 `.gitattributes`（Windows 脚本统一 CRLF）、补全 `.gitignore`。
