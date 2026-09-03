using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace ScriptManager.Cache;

/// <summary>
/// 统一缓存基础设施：所有缓存文件都放在配置的缓存目录下（默认 exe 同级 cache/，可用 config.ini 的 cache_dir 覆盖）。
/// 具体缓存内容各自实现为独立的 JSON 文件（如 window-state.json），
/// 便于后续持续扩展更多缓存项，且互不影响。
/// </summary>
public static class CacheStore
{
    /// <summary>缓存根目录：来自 AppConfig.CacheDir（默认 exe 同级 cache/）。</summary>
    public static readonly string CacheRoot = AppConfig.CacheDir;

    /// <summary>读取指定缓存文件并反序列化为 T；文件不存在或解析失败返回 default(T)。</summary>
    public static T? ReadJson<T>(string fileName)
    {
        try
        {
            var path = Path.Combine(CacheRoot, fileName);
            if (!File.Exists(path)) return default;
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<T>(json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"读取缓存 {fileName} 失败: {ex.Message}");
            return default;
        }
    }

    /// <summary>将对象序列化为 JSON 写入指定缓存文件（目录不存在自动创建）。失败静默忽略。</summary>
    public static void WriteJson<T>(string fileName, T value)
    {
        try
        {
            Directory.CreateDirectory(CacheRoot);
            var path = Path.Combine(CacheRoot, fileName);
            var json = JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(path, json);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"写入缓存 {fileName} 失败: {ex.Message}");
        }
    }
}
