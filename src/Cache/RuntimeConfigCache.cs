using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

using ScriptManager.Cache;

namespace ScriptManager.Cache;

/// <summary>
/// 运行时路径缓存：按 lang 维护各语言的执行程序路径（每种语言一条）。
/// 数据持久化到 cache/runtimes.json。纯 IO 封装，探测逻辑（TryDetect 等）在 RuntimeConfig 内。
/// </summary>
public static class RuntimeConfigCache
{
    private const string FileName = "runtimes.json";

    private static string FilePath => Path.Combine(CacheStore.CacheRoot, FileName);

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>加载全部 lang→路径。文件缺失/解析失败都返回空字典（调用方需自行检测或让用户选择）。</summary>
    public static Dictionary<string, string?> Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return new Dictionary<string, string?>();
            var json = File.ReadAllText(FilePath);
            var dto = JsonSerializer.Deserialize<Dictionary<string, string?>>(json);
            return dto ?? new Dictionary<string, string?>();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[RuntimeConfigCache] 加载失败 {FilePath}：{ex.Message}");
            return new Dictionary<string, string?>();
        }
    }

    /// <summary>保存指定 lang 的路径；其他 lang 保持不变。null/空视为"用户取消选择"，写入空以禁用自动检测覆盖。</summary>
    public static void Save(string lang, string? path)
    {
        try
        {
            var all = Load();
            all[lang] = string.IsNullOrWhiteSpace(path) ? null : path;
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(all, JsonOpts));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[RuntimeConfigCache] 保存失败 {FilePath}：{ex.Message}");
        }
    }

    /// <summary>整体覆盖保存（供首次自动检测后落盘）。</summary>
    public static void SaveAll(Dictionary<string, string?> all)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(all, JsonOpts));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[RuntimeConfigCache] 保存失败 {FilePath}：{ex.Message}");
        }
    }
}
