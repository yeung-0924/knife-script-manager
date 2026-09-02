using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace ScriptManager;

/// <summary>
/// 用户侧配置：读取 exe 同级的 config/config.ini。修改后重启程序生效。
/// 当前支持（[script] 节）：
///   script_path = 脚本目录路径（默认 script，目录下固定查找 index.json）
///   lib_path    = 第三方依赖目录（默认 lib，如 JDBC jar；注入环境变量 SCRIPT_MANAGER_LIB）
///   runtime_path = 运行时安装目录（默认 runtime；注入环境变量 SCRIPT_MANAGER_RUNTIME，供安装脚本默认使用）
///   cache_path  = 缓存文件目录（默认 cache）
///   log         = 日志文件目录（默认 log，如 error.log）
/// 路径规则：留空/被注释则使用默认值；填相对路径则相对 exe 目录解析；填绝对路径（含 UNC 如 \\Mac\Home\...）则直接使用。
/// 后续新增配置项，在此追加对应的静态属性并从 Sections 取值即可。
/// </summary>
public static class AppConfig
{
    // 用 Environment.ProcessPath 取 exe 实际目录（兼容自包含单文件发布：AppContext.BaseDirectory 在单文件模式下会指向临时解压目录）
    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;

    private static readonly string ConfigDir = Path.Combine(ExeDir, "config");
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

    /// <summary>脚本目录路径（来自配置的 script_path，默认 exe 同级 script）。</summary>
    public static string ScriptDir => ResolveDir("script", "script_path", "script");

    /// <summary>第三方依赖目录（来自配置的 lib_path，默认 exe 同级 lib；注入环境变量 SCRIPT_MANAGER_LIB 供脚本引用）。</summary>
    public static string LibDir => ResolveDir("script", "lib_path", "lib");

    /// <summary>
    /// 运行时安装目录（来自配置的 runtime_path，默认 exe 同级 runtime；注入环境变量 SCRIPT_MANAGER_RUNTIME 供脚本引用）。
    /// 安装类脚本（Install-*.ps1）在未指定安装目录时以此作为默认目标；目录不存在时由脚本自行创建。
    /// </summary>
    public static string RuntimeDir => ResolveDir("script", "runtime_path", "runtime");

    /// <summary>缓存文件目录（来自配置的 cache_path，默认 exe 同级 cache）。</summary>
    public static string CacheDir => ResolveDir("script", "cache_path", "cache");

    /// <summary>日志文件目录（来自配置的 log，默认 exe 同级 log）。</summary>
    public static string LogDir => ResolveDir("script", "log", "log");

    /// <summary>脚本索引 json 的完整路径 = 脚本目录下的 index.json（固定文件名）。找不到则 Load 返回空树。</summary>
    public static string ScriptIndexJsonPath => Path.Combine(ScriptDir, "index.json");

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
