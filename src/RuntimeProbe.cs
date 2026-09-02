using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;

namespace ScriptManager;

/// <summary>
/// 可执行文件校验：用用户选择的 exe 实跑一条该语言的「获取版本号」命令，并验证输出
/// 包含该语言特有的版本号特征（不只是 ExitCode==0）。这样给 java 选 attrib/cmd 这类
/// 「能跑但不匹配」的 exe 会被正确判负，无需维护合法 exe 名白名单。
/// </summary>
public static class RuntimeProbe
{
    // 各语言的探针命令 + 期望的版本号输出特征（首行非空时做 regex 匹配）
    private static readonly Dictionary<string, (string Args, Regex VersionPattern)> Probes = new(StringComparer.OrdinalIgnoreCase)
    {
        [ScriptLangs.PowerShell] = ("-NoProfile -Command \"$PSVersionTable.PSVersion.ToString()\"", new Regex(@"\d+\.\d+", RegexOptions.Compiled)),
        [ScriptLangs.Cmd]        = ("/c ver",                                                       new Regex(@"Windows.*\d+",   RegexOptions.Compiled)),
        [ScriptLangs.Bash]       = ("--version",                                                    new Regex(@"\bGNU\b.*\b\d+\.\d+|\b\d+\.\d+.*\bbash\b", RegexOptions.Compiled | RegexOptions.IgnoreCase)),
        [ScriptLangs.Node]       = ("--version",                                                    new Regex(@"v\d+\.\d+\.\d+",  RegexOptions.Compiled)),
        [ScriptLangs.Python]     = ("--version",                                                    new Regex(@"Python\s*\d+\.\d+", RegexOptions.Compiled | RegexOptions.IgnoreCase)),
        [ScriptLangs.Java]       = ("-version",                                                     new Regex(@"openjdk",          RegexOptions.Compiled | RegexOptions.IgnoreCase)),
        [ScriptLangs.Go]         = ("version",                                                      new Regex(@"go\d+\.\d+",       RegexOptions.Compiled | RegexOptions.IgnoreCase)),
        [ScriptLangs.Rust]       = ("--version",                                                    new Regex(@"rustc\s*\d+\.\d+", RegexOptions.Compiled | RegexOptions.IgnoreCase)),
        // 必须校验主版本号 >= 6：Windows PowerShell 5.1 跑同一条命令会输出 "5.1.19041.xxx"，
        // 若沿用 powershell 的 \d+\.\d+ 正则会被误判为可用，使 pwsh 与 powershell 失去区分。
        [ScriptLangs.Pwsh]       = ("-NoProfile -Command \"$PSVersionTable.PSVersion.ToString()\"",  new Regex(@"^([6-9]|\d{2,})\.", RegexOptions.Compiled)),
    };

    /// <summary>探测结果缓存：(lang, exePath) → (ok, version)。避免每次选中脚本都实跑子进程（冷启动可达秒级，会卡 UI）。</summary>
    private static readonly Dictionary<string, (bool ok, string? version)> Cache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly object CacheLock = new();

    /// <summary>查缓存；命中返回 true 并通过 out 给出结果，未命中返回 false。</summary>
    public static bool TryGetCached(string? lang, string? exePath, out (bool ok, string? version) result)
    {
        result = (false, null);
        if (string.IsNullOrWhiteSpace(lang) || string.IsNullOrWhiteSpace(exePath))
            return false;
        lock (CacheLock)
        {
            return Cache.TryGetValue(Key(lang, exePath), out result);
        }
    }

    /// <summary>实跑一次该语言的版本探针。结果会写入缓存。供手动选 exe / 启动选中脚本时调用。</summary>
    public static (bool ok, string? version) Probe(string lang, string exePath)
    {
        var key = Key(lang, exePath);
        var (ok, version) = ProbeCore(lang, exePath);
        lock (CacheLock)
        {
            Cache[key] = (ok, version);
        }
        return (ok, version);
    }

    /// <summary>把某个 lang+exePath 的缓存条目作废（如检测到路径变更）。</summary>
    public static void Invalidate(string lang, string exePath)
    {
        lock (CacheLock)
        {
            Cache.Remove(Key(lang, exePath));
        }
    }

    /// <summary>
    /// 清空全部探测缓存。环境变量刷新后调用：同一路径下的 exe 可能是新版本
    /// （如原地升级 JDK），旧缓存会导致版本号不更新。
    /// </summary>
    public static void ClearCache()
    {
        lock (CacheLock)
        {
            Cache.Clear();
        }
    }

    private static string Key(string lang, string exePath) => lang + "\u0001" + exePath;

    private static (bool ok, string? version) ProbeCore(string lang, string exePath)
    {
        if (!File.Exists(exePath))
            return (false, null);
        if (!Probes.TryGetValue(lang, out var probe))
            return (false, null); // 未知语言：不强制校验，交由运行时判断

        try
        {
            var psi = new ProcessStartInfo(exePath, probe.Args)
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using var proc = Process.Start(psi);
            if (proc == null) return (false, null);
            if (!proc.WaitForExit(10000))
            {
                try { proc.Kill(); } catch { }
                return (false, null);
            }
            // 版本号可能在 stdout 或 stderr（如 java -version），合并取首行非空
            var combined = proc.StandardOutput.ReadToEnd() + "\n" + proc.StandardError.ReadToEnd();
            string? firstLine = null;
            foreach (var line in combined.Split('\n'))
            {
                var t = line.Trim();
                if (!string.IsNullOrWhiteSpace(t)) { firstLine = t; break; }
            }
            // 关键修复：除 ExitCode==0 外，输出首行必须匹配该语言的版本号特征，避免「能跑但不是该语言」误判
            var matched = firstLine != null && probe.VersionPattern.IsMatch(firstLine);
            return (proc.ExitCode == 0 && matched, matched ? firstLine : null);
        }
        catch
        {
            return (false, null);
        }
    }
}
