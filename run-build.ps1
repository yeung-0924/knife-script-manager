# run-build.ps1 - 后台启动 build.ps1
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File build.ps1" -WorkingDirectory "d:\Workspace\knife\script-manager-win" -RedirectStandardOutput "d:\Workspace\knife\script-manager-win\.tmp\_build.log" -RedirectStandardError "d:\Workspace\knife\script-manager-win\.tmp\_build.err" -NoNewWindow
Write-Host "build started in background, see .tmp/_build.log"
