using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace ScriptManager.ViewModels;

/// <summary>
/// 封装脚本执行细节：拼装参数、启动进程、实时捕获 stdout/stderr、支持管理员提权（runas）。
/// 通过回调把日志与退出码推给 MainViewModel，避免 ViewModel 直接持有进程细节。
/// 替代原 Form1 中的 RunSelected + OutputHandler + 跨线程 Invoke 逻辑。
/// </summary>
public class ScriptRunner
{
    public record RunResult(int ExitCode);

    // 当前正在运行的进程句柄，供 Stop 终止（单次仅一个，应用为串行执行）。
    private static readonly object _currentLock = new();
    private static Process? _current;

    /// <summary>终止当前正在运行的脚本进程（含子进程）。无运行中进程时为空操作。</summary>
    public static void Stop()
    {
        Process? p;
        lock (_currentLock) { p = _current; }
        if (p == null) return;
        try { if (!p.HasExited) p.Kill(true); }
        catch { }
    }

    /// <summary>
    /// 执行指定脚本。workingDir 为脚本所在目录；args 为已拼装好的参数字符串；admin 为是否提权。
    /// onLog 回调：(level, text)。返回退出码。
    /// </summary>
    /// <param name="injectedVars">cmd 专用：ASCII 化改写抽出的中文真值，注入子进程环境块（UTF-16，无损）。</param>
    public static RunResult Run(
        ScriptItem script,
        string combinedArgs,
        string workingDir,
        bool admin,
        Action<LogEntry.Level, string> onLog,
        string? scriptOverridePath = null,
        IReadOnlyDictionary<string, string>? injectedVars = null)
    {
        var scriptPath = scriptOverridePath ?? script.ResolvedPath;
        var startInfo = RuntimeResolver.Build(script.Lang, scriptPath, combinedArgs, workingDir, injectedVars);
        if (startInfo == null)
        {
            onLog(LogEntry.Level.Error, string.Format(Strings.LogRuntimeUnresolvedFormat, script.Lang));
            return new RunResult(-1);
        }

        try
        {
            using var proc = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            if (admin)
            {
                // 管理员提权：需 UseShellExecute=true 才能触发 UAC；此时无法重定向输出，改为临时落盘并轮询读回
                return RunElevated(script, combinedArgs, workingDir, onLog, scriptPath, injectedVars);
            }

            proc.Start();
            lock (_currentLock) { _current = proc; }
            proc.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                onLog(LogEntry.Level.Output, e.Data);
            };
            proc.ErrorDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                onLog(LogEntry.Level.Error, e.Data);
            };
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            proc.WaitForExit();
            var code = proc.ExitCode;
            lock (_currentLock) { _current = null; }
            onLog(LogEntry.Level.Exit, string.Format(Strings.LogProcessExitFormat, code));
            return new RunResult(code);
        }
        catch (Exception ex)
        {
            lock (_currentLock) { _current = null; }
            onLog(LogEntry.Level.Error, string.Format(Strings.LogExecExceptionFormat, ex.Message));
            return new RunResult(-1);
        }
    }

    /// <summary>
    /// 管理员提权执行：UseShellExecute=true + Verb=runas 无法重定向输出，故写入临时 .bat 落盘执行，
    /// 通过轮询日志文件实现接近实时的日志推送（脚本每 5 秒的下载进度等输出都能及时显示）。
    /// 临时文件执行后清理。
    /// </summary>
    private static RunResult RunElevated(
        ScriptItem script, string combinedArgs, string workingDir, Action<LogEntry.Level, string> onLog,
        string? scriptOverridePath = null, IReadOnlyDictionary<string, string>? injectedVars = null)
    {
        var scriptPath = scriptOverridePath ?? script.ResolvedPath;
        var tempBat = Path.Combine(Path.GetTempPath(), $"se_admin_{Guid.NewGuid():N}.bat");
        var logFile = Path.Combine(Path.GetTempPath(), $"se_admin_{Guid.NewGuid():N}.log");
        try
        {
            // 构造与原 RuntimeResolver 一致的命令行（复用其拼装逻辑）
            var psi = RuntimeResolver.Build(script.Lang, scriptPath, combinedArgs, workingDir)!;
            // 提权走 ShellExecute，进程环境块传不进去，改写抽出的中文只能以 set 行落进 bat。
            // 这些行必须排在 chcp 65001 之后：此时代码页已切 UTF-8，bat 里的中文字节才会被正确解码。
            var body = new StringBuilder();
            body.Append("@echo off\r\nchcp 65001 >nul\r\n");
            // 脚本管理器提供的目录环境变量：ShellExecute 不支持 lpEnvironment，
            // 非提权路径由 RuntimeResolver.Build 注入环境块，提权路径只能在此以 set 行补齐，
            // 否则 admin:true 的脚本（如 Install-*.ps1）拿不到 SCRIPT_MANAGER_RUNTIME 等目录信息。
            foreach (var setLine in RuntimeResolver.BuildScriptEnvSetLines())
                body.Append(setLine).Append("\r\n");
            foreach (var setLine in RuntimeResolver.BuildSetLines(injectedVars))
                body.Append(setLine).Append("\r\n");
            body.Append($"\"{psi.FileName}\" {psi.Arguments} > \"{logFile}\" 2>&1\r\necho {string.Format(Strings.LogProcessExitFormat, "%ERRORLEVEL%")} >> \"{logFile}\"");
            File.WriteAllText(tempBat, body.ToString(), new UTF8Encoding(false));

            var startInfo = new ProcessStartInfo
            {
                FileName = tempBat,
                WorkingDirectory = workingDir,
                UseShellExecute = true,
                Verb = "runas",
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            using var proc = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            proc.Start();
            lock (_currentLock) { _current = proc; }

            // 提权路径无法重定向输出，改为轮询读取临时日志文件，边执行边推送日志（接近实时）。
            // 写入端持续持有文件句柄，读取端用 FileShare.ReadWrite 容忍并发写；
            // 读到 EOF 且进程已退出时结束。
            using (var logStream = new FileStream(logFile, FileMode.OpenOrCreate, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var logReader = new StreamReader(logStream, Encoding.UTF8))
            {
                while (!proc.HasExited || logReader.Peek() != -1)
                {
                    var line = logReader.ReadLine();
                    if (line == null)
                    {
                        if (proc.HasExited) break;
                        Thread.Sleep(250);
                        continue;
                    }
                    onLog(line.Contains("结束执行（退出码") ? LogEntry.Level.Exit : LogEntry.Level.Output, line);
                }
            }
            lock (_currentLock) { _current = null; }
            return new RunResult(proc.ExitCode);
        }
        catch (Exception ex)
        {
            onLog(LogEntry.Level.Error, string.Format(Strings.LogElevatedFailFormat, ex.Message));
            return new RunResult(-1);
        }
        finally
        {
            try { if (File.Exists(tempBat)) File.Delete(tempBat); } catch { }
            try { if (File.Exists(logFile)) File.Delete(logFile); } catch { }
        }
    }
}
