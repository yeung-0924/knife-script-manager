using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace ScriptManager;

/// <summary>
/// 用户侧配置：读取 exe 同级的 config/config.ini。修改后重启程序生效。
/// 当前支持（[script] 节）：
///   default_script_file = 默认脚本索引文件（指向 index.json，默认 script\index.json；相对路径相对 exe 目录，绝对/UNC 直接用）
///   user_script_file    = 用户通过「打开」按钮选择的脚本索引文件（程序自动写入；留空则回退 default_script_file）
///   lib_dir    = 第三方依赖目录（默认 lib，如 JDBC jar；注入环境变量 SCRIPT_MANAGER_LIB）
///   runtime_dir = 运行时安装目录（默认 runtime；注入环境变量 SCRIPT_MANAGER_RUNTIME，供安装脚本默认使用）
///   cache_dir  = 缓存文件目录（默认 cache）
///   log_dir    = 日志文件目录（默认 log，如 error.log）
///   default_timeout = 脚本默认执行超时（秒，0/留空=不限制）
/// 路径规则：留空/被注释则使用默认值；填相对路径则相对 exe 目录解析；填绝对路径（含 UNC 如 \\Mac\Home\...）则直接使用。
/// 后续新增配置项，在此追加对应的静态属性并从 Sections 取值即可。
/// </summary>
public static class AppConfig
{
    // 用 Environment.ProcessPath 取 exe 实际目录（兼容自包含单文件发布：AppContext.BaseDirectory 在单文件模式下会指向临时解压目录）
    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;

    public static readonly string ConfigDir = Path.Combine(ExeDir, "config");
    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.ini");

    // section(lower) -> (key(lower) -> value)
    private static readonly Dictionary<string, Dictionary<string, string>> Sections = Load();

    /// <summary>
    /// 解析一个目录配置：raw 为空用默认子目录；非空且非绝对则相对 exe 目录解析；绝对路径（含 UNC）直接使用。
    /// </summary>
    private static string ResolveDir(string section, string key, string defaultSubDir)
    {
        var raw = GetValue(section, key)?.Trim();
        if (string.IsNullOrWhiteSpace(raw))
            raw = Path.Combine(ExeDir, defaultSubDir);
        else if (!Path.IsPathRooted(raw))
            raw = Path.Combine(ExeDir, raw);
        return Path.GetFullPath(raw);
    }

    /// <summary>
    /// 默认脚本索引文件（指向 index.json）的完整路径，来自配置的 [script] default_script_file。
    /// 留空/注释则默认 exe 同级 script\index.json；相对路径相对 exe 目录解析；绝对路径（含 UNC）直接使用。
    /// </summary>
    public static string DefaultScriptFilePath
    {
        get
        {
            var raw = GetValue("script", "default_script_file")?.Trim();
            if (string.IsNullOrWhiteSpace(raw))
                return Path.GetFullPath(Path.Combine(ExeDir, "script", "index.json"));
            return Path.IsPathRooted(raw)
                ? Path.GetFullPath(raw)
                : Path.GetFullPath(Path.Combine(ExeDir, raw));
        }
    }

    /// <summary>脚本目录路径 = 默认脚本索引文件所在目录（由 DefaultScriptFilePath 推导）。</summary>
    public static string ScriptDir => Path.GetDirectoryName(DefaultScriptFilePath) ?? Path.Combine(ExeDir, "script");

    /// <summary>第三方依赖目录（来自配置的 lib_dir，默认 exe 同级 lib；注入环境变量 SCRIPT_MANAGER_LIB 供脚本引用）。</summary>
    public static string LibDir => ResolveDir("script", "lib_dir", "lib");

    /// <summary>
    /// 运行时安装目录（来自配置的 runtime_dir，默认 exe 同级 runtime；注入环境变量 SCRIPT_MANAGER_RUNTIME 供脚本引用）。
    /// 安装类脚本（Install-*.ps1）在未指定安装目录时以此作为默认目标；目录不存在时由脚本自行创建。
    /// </summary>
    public static string RuntimeDir => ResolveDir("script", "runtime_dir", "runtime");

    /// <summary>缓存文件目录（来自配置的 cache_dir，默认 exe 同级 cache）。</summary>
    public static string CacheDir => ResolveDir("script", "cache_dir", "cache");

    /// <summary>日志文件目录（来自配置的 log_dir，默认 exe 同级 log）。</summary>
    public static string LogDir => ResolveDir("script", "log_dir", "log");

    /// <summary>
    /// 脚本默认执行超时（秒）。0 或负数表示不限制（无限等待，默认）。
    /// 单脚本可在 index.json 用 <c>timeout</c> 字段单独覆盖；两者皆未设则不超时。
    /// 修改后重启程序生效。
    /// </summary>
    public static int DefaultTimeoutSeconds
    {
        get
        {
            var raw = GetValue("script", "default_timeout");
            return int.TryParse(raw, out var v) ? v : 0;
        }
    }

    /// <summary>脚本索引 json 的完整路径（固定为 DefaultScriptFilePath）。</summary>
    public static string ScriptIndexJsonPath => DefaultScriptFilePath;

    /// <summary>
    /// 最近一次「打开」按钮选择的脚本索引文件（index.json）绝对路径。
    /// 为空表示未持久化（或所选文件已被移除），启动时回退到默认 default_script_file。
    /// 仅用于记住用户选择，使重启后自动加载该文件；不影响其它配置项。
    /// 相对路径按 exe 目录解析（与 default_script_file 一致），绝对路径（含 UNC）直接使用。
    /// </summary>
    public static string UserScriptFilePath
    {
        get
        {
            var raw = GetValue("script", "user_script_file")?.Trim();
            if (string.IsNullOrWhiteSpace(raw)) return "";
            return Path.IsPathRooted(raw)
                ? Path.GetFullPath(raw)
                : Path.GetFullPath(Path.Combine(ExeDir, raw));
        }
    }

    /// <summary>
    /// 运行时持久化「打开」选择的脚本索引文件到 config.ini 的 [script] user_script_file（存绝对路径）。
    /// 保留其它 section / key / 注释与顺序；文件或 [script] 节不存在则创建。
    /// 同时更新内存缓存，使同进程内 UserScriptFilePath 即时反映新值。写入失败仅记调试日志、不抛异常。
    /// </summary>
    public static void SetUserScriptFilePath(string file)
    {
        if (string.IsNullOrWhiteSpace(file)) return;
        SetRawValue("script", "user_script_file", Path.GetFullPath(file));
    }

    /// <summary>
    /// 读取配置项原始字符串值（未解析路径）。节或 key 不存在返回 null。供配置编辑弹窗回显当前值。
    /// </summary>
    public static string? GetRawValue(string section, string key)
    {
        if (Sections.TryGetValue(section, out var kv) && kv.TryGetValue(key, out var v))
            return v;
        return null;
    }

    /// <summary>
    /// 通用写入配置项：保留注释、空行、节顺序与文件格式。value 为空则移除该 key 行（恢复默认）；
    /// 节不存在则创建。写入失败仅记调试日志、不抛异常。同时同步内存缓存，使同进程内即时反映。
    /// </summary>
    public static void SetRawValue(string section, string key, string? value)
    {
        try
        {
            var lines = File.Exists(ConfigPath)
                ? new List<string>(File.ReadAllLines(ConfigPath))
                : new List<string>();
            value = (value ?? "").Trim();

            var secIdx = -1;
            for (var i = 0; i < lines.Count; i++)
            {
                var t = lines[i].Trim();
                if (t.StartsWith("[") && t.EndsWith("]") &&
                    t.Substring(1, t.Length - 2).Trim().Equals(section, StringComparison.OrdinalIgnoreCase))
                {
                    secIdx = i;
                    break;
                }
            }

            if (secIdx < 0)
            {
                if (string.IsNullOrEmpty(value)) return; // 节与值都不存在，无需创建
                // 整个 [section] 节都不存在：追加新节
                if (lines.Count > 0 && lines[^1].Trim().Length > 0) lines.Add("");
                lines.Add($"[{section}]");
                lines.Add($"{key}={value}");
            }
            else
            {
                // 在该节范围内查找 key（到下一个 [section] 为止）
                var end = lines.Count;
                for (var i = secIdx + 1; i < lines.Count; i++)
                {
                    var t = lines[i].Trim();
                    if (t.StartsWith("[") && t.EndsWith("]")) { end = i; break; }
                }
                var keyIdx = -1;
                for (var i = secIdx + 1; i < end; i++)
                {
                    var t = lines[i].Trim();
                    if (t.Length == 0 || t.StartsWith(";") || t.StartsWith("#")) continue;
                    var eq = t.IndexOf('=');
                    if (eq >= 0 && t.Substring(0, eq).Trim().Equals(key, StringComparison.OrdinalIgnoreCase))
                    {
                        keyIdx = i;
                        break;
                    }
                }
                if (string.IsNullOrEmpty(value))
                {
                    if (keyIdx >= 0) lines.RemoveAt(keyIdx); // 清空即移除该行，恢复默认
                }
                else if (keyIdx >= 0)
                    lines[keyIdx] = $"{key}={value}";
                else
                    lines.Insert(end, $"{key}={value}");
            }

            Directory.CreateDirectory(ConfigDir);
            File.WriteAllLines(ConfigPath, lines, new UTF8Encoding(false));

            // 同步内存缓存：清空则移除，否则更新
            if (!Sections.ContainsKey(section))
                Sections[section] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(value)) Sections[section].Remove(key);
            else Sections[section][key] = value;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"写入 config.ini ({section}/{key}) 失败: " + ex.Message);
        }
    }

    /// <summary>
    /// 重新从磁盘加载配置到内存缓存（<see cref="Sections"/>）。配置编辑保存后调用，
    /// 使本进程后续读取即时反映新值（部分配置如脚本目录切换仍需重启才真正生效）。
    /// </summary>
    public static void Reload()
    {
        var fresh = Load();
        Sections.Clear();
        foreach (var kv in fresh)
            Sections[kv.Key] = kv.Value;
    }

    private static string? GetValue(string section, string key)
    {
        if (Sections.TryGetValue(section, out var kv) &&
            kv.TryGetValue(key, out var value))
            return value;
        return null;
    }

    private static Dictionary<string, Dictionary<string, string>> Load()
    {
        var map = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
        try
        {
            if (!File.Exists(ConfigPath))
                return map;

            string? current = null;
            foreach (var lineRaw in File.ReadAllLines(ConfigPath))
            {
                var line = lineRaw.Trim();
                if (line.Length == 0 || line.StartsWith(";") || line.StartsWith("#"))
                    continue;

                if (line.StartsWith("[") && line.EndsWith("]"))
                {
                    current = line.Substring(1, line.Length - 2).Trim();
                    if (!map.ContainsKey(current))
                        map[current] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                }
                else if (current != null && line.Contains('='))
                {
                    var idx = line.IndexOf('=');
                    var key = line.Substring(0, idx).Trim();
                    var val = line.Substring(idx + 1).Trim();
                    map[current!][key] = val;
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine("读取 config.ini 失败: " + ex.Message);
        }
        return map;
    }
}
