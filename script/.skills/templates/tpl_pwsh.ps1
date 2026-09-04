# 更新时间: 2026-09-04
# PowerShell 7 (pwsh) 最小模板（ScriptManager）
# 语法与 Windows PowerShell 一致，index.json 中 lang 用 "pwsh"
# 参数用 _p{NAME} 占位符，运行前由程序替换为用户输入
param( [string]$Name = "World" )

Write-Host "===== Hello, World ====="
Write-Host "Hello, _p{NAME}!"

