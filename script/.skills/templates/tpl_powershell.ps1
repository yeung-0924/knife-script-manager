# 更新时间: 2026-09-04
# PowerShell 最小模板（ScriptManager）
# 参数用 _p{NAME} 占位符，运行前由程序替换为用户输入
# 也可用 param 块接收 -Name（二选一即可）
param( [string]$Name = "World" )

Write-Host "===== Hello, World ====="
Write-Host "Hello, _p{NAME}!"
# 若改用 param 方式收参，可写：Write-Host "Hello, $Name!"

