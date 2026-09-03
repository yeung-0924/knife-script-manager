# 更新日志（Changelog）

## [1.1.0]
- 脚本执行超时自动终止：超过设定时长仍未结束则强杀进程树（RunResult.TimedOut）。
  - 单脚本可在 `index.json` 设 `timeout`（秒）单独控制；全局 `config.ini` 的 `default_timeout` 兜底。
  - 两者皆未设或值为 0/负数时**不限制**（无限等待），兼容既有长时脚本。

## [1.0.0]
- 首个公开版本：便携版（自包含 .NET）与标准版双交付，读取 exe 同级 `script/index.json` 管理多语言脚本，实时日志与报错面板。
- 开源合规与文档整理：
  - README 去除私人路径，构建命令改为走 PATH 的 `dotnet` / `.\build.ps1`；补充「配置文件」章节。
  - 新增 `config.ini.example` 配置模板；`build.ps1` 缺 `config.ini` 时退化复制该范本，确保交付包自带配置。
  - 新增 `.gitattributes`（Windows 脚本统一 CRLF）。
  - 新增 `THIRD-PARTY.md`（登记 Hutool Apache-2.0 许可证与来源）。
  - `.gitignore` 补充 `*.iml` / `*.user`，避免 IDE 文件误提交。
