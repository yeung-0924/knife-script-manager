# 更新日志（Changelog）

## [1.1.0]
- 文档与开源合规整理：
  - README 去除私人路径，构建命令改为走 PATH 的 `dotnet` / `.\build.ps1`。
  - 新增 `config.ini.example` 配置模板，并在 README 补充「配置文件」章节。
  - `build.ps1` 在缺 `config.ini` 时退化复制 `config.ini.example`，确保交付包自带配置范本。
  - 新增 `.gitattributes`（Windows 脚本统一 CRLF）。
  - 新增 `THIRD-PARTY.md`（登记 Hutool Apache-2.0 许可证与来源）。
  - `.gitignore` 补充 `*.iml` / `*.user`，避免 IDE 文件误提交。

## [1.0.0]
- 首个公开版本：便携版（自包含 .NET）与标准版双交付，读取 exe 同级 `script/index.json` 管理多语言脚本，实时日志与报错面板。
