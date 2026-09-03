# 参与贡献（Contributing）

感谢你关注 knife-script-manager！这是一个个人维护的便携脚本管理器，欢迎提 Issue 与 PR。

## 提 Issue

- **Bug**：请说明系统版本（Windows 10/11）、.NET 运行时是否安装、复现步骤、错误日志（`log/error.log`）。
- **功能建议**：说明使用场景，越具体越好。

## 提交 PR

1. Fork 后从 `main` 切分支开发。
2. 保持提交小而聚焦，信息用中文或英文均可。
3. 若改动构建脚本 `build.ps1`，请在本地跑通 `.\build.ps1 -Edition Both` 再提交。
4. 不要提交 `dist/`、`publish/`、本地 `config.ini`、IDE 文件（`.iml`/`.user`/`.idea`）——这些已在 `.gitignore` 中。

## 代码约定

- C# 端遵循项目 `.skills/` 下的通用编码规范（如有）。
- 脚本命名：`script/README.md` 的「文件命名约定」——PowerShell/pwsh 用 PascalCase，Go/Rust 用 snake_case。
- 新增第三方二进制依赖（如 jar）时，须在 `THIRD-PARTY.md` 登记许可证与来源。
