using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

using ScriptManager.Cache;

namespace ScriptManager;

/// <summary>
/// 按 lang 维护运行程序路径（每种语言一条），持久化到 cache/runtimes.json（IO 见 RuntimeConfigCache）。
/// 缺失的路径由 <see cref="EnsureAutoDetected"/> 在首次启动时尝试自动检测（cmd/powershell 必有；其他按需）。
/// </summary>
public static class RuntimeConfig
{
    /// <summary>加载全部 lang→路径。文件缺失/解析失败/未配置项都返回空字典（调用方需自行检测或让用户选择）。</summary>
    public static Dictionary<string, string?> Load() => RuntimeConfigCache.Load();

    /// <summary>保存指定 lang 的路径；其他 lang 保持不变。空字符串视为"用户取消选择"，写入空以禁用自动检测覆盖。</summary>
    public static void Save(string lang, string? path) => RuntimeConfigCache.Save(lang, path);

    /// <summary>首次启动对每个 lang 尝试自动检测；只填充"未配置"项，不覆盖用户已设置的值。</summary>
    public static void EnsureAutoDetected()
    {
        var all = RuntimeConfigCache.Load();
        foreach (var (lang, hint) in DefaultCandidates)
        {
            if (!string.IsNullOrWhiteSpace(all.GetValueOrDefault(lang)))
                continue; // 用户已配置，跳过
            var found = TryDetect(hint);
            if (found != null) all[lang] = found;
        }
        RuntimeConfigCache.SaveAll(all);
    }

    /// <summary>取某个 lang 的当前路径（可能为 null：未配置或自动检测失败）。</summary>
    public static string? Get(string lang) => RuntimeConfigCache.Load().GetValueOrDefault(lang);

    /// <summary>仅尝试自动检测某语言可执行文件（不落盘），找到返回完整路径，否则 null。供 UI 校验时即时带出。</summary>
    public static string? Detect(string lang)
    {
        if (string.IsNullOrWhiteSpace(lang)) return null;
        if (DefaultCandidates.TryGetValue(lang!, out var candidates))
            return TryDetect(candidates);
        return null;
    }

    /// <summary>每个 lang 在自动检测时尝试的执行文件名候选（按顺序匹配）。</summary>
    private static readonly Dictionary<string, string[]> DefaultCandidates = new()
    {
        [ScriptLangs.PowerShell] = new[] { "pwsh.exe", "powershell.exe" },
        [ScriptLangs.Cmd]        = new[] { "cmd.exe" },
        [ScriptLangs.Python]     = new[] { "python.exe", "python3.exe" },
        [ScriptLangs.Java]       = new[] { "java.exe" },
        [ScriptLangs.Bash]       = new[] { "bash.exe" },
        [ScriptLangs.Node]       = new[] { "node.exe" },
        [ScriptLangs.Go]         = new[] { "go.exe" },
        [ScriptLangs.Rust]       = new[] { "rustc.exe", "cargo.exe" },
        // 只认 pwsh.exe（PowerShell 6+），不回退到 powershell.exe——
        // 回退会让「指定 pwsh」退化成可能跑在 5.1 上，失去区分意义
        [ScriptLangs.Pwsh]       = new[] { "pwsh.exe" }
    };

    /// <summary>优先用 PATH 找，再回退到 Windows 系统目录（System32 / SystemWOW64），都找不到返回 null。</summary>
    private static string? TryDetect(string[] candidates)
    {
        foreach (var name in candidates)
        {
            // 1) PATH 解析（兼容普通环境）
            var viaPath = FindOnPath(name);
            if (viaPath != null) return viaPath;
            // 2) Windows 系统目录兜底（cmd.exe / powershell.exe 几乎一定在 System32）
            var sysRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            var systemDir = Path.Combine(sysRoot, "System32");
            var sysFull = Path.Combine(systemDir, name);
            if (File.Exists(sysFull)) return sysFull;
            var wowFull = Path.Combine(sysRoot, "SysWOW64", name);
            if (File.Exists(wowFull)) return wowFull;
        }
        return null;
    }

    private static string? FindOnPath(string exe)
    {
        var pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathEnv)) return null;
        foreach (var dir in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var full = Path.Combine(dir.Trim(), exe);
                if (File.Exists(full)) return Path.GetFullPath(full);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[RuntimeConfig] PATH 探测异常 {dir}：{ex.Message}");
            }
        }
        return null;
    }
}
