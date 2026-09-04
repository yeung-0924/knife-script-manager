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
    /// <summary>
    /// 缓存根目录：来自 AppConfig.CacheDir（默认 exe 同级 cache/）。
    /// 原设计为 static readonly（启动时固化），现改为可变——当 config.ini 的 cache_dir 被改到新目录时，
    /// 由 <see cref="Relocate"/> 把旧目录内容整体迁移过来并切换此值，使缓存目录改动「保存即生效、无需重启」。
    /// </summary>
    public static string CacheRoot = AppConfig.CacheDir;

    /// <summary>
    /// 将缓存根目录切换到 newRoot，并把当前 <see cref="CacheRoot"/> 下的全部内容（文件及子目录，递归）迁移过去。
    /// 仅当 newRoot 与当前值不同才执行；采用「先复制到新目录、成功后删除旧目录」策略，
    /// 复制阶段任何异常都会被吞掉并仅记日志、保留旧目录不动、CacheRoot 不更新，保证主流程安全。
    /// 切换后所有缓存读写（runtimes.json / window-state.json / 各业务缓存等）立即落到新目录，
    /// 旧目录被清空删除（缓存可重建，删之无碍）。无需重启程序。
    /// </summary>
    public static void Relocate(string newRoot)
    {
        if (string.Equals(CacheRoot, newRoot, StringComparison.OrdinalIgnoreCase)) return;
        try
        {
            if (Directory.Exists(CacheRoot))
            {
                foreach (var file in Directory.EnumerateFiles(CacheRoot, "*", SearchOption.AllDirectories))
                {
                    var rel = Path.GetRelativePath(CacheRoot, file);
                    var dest = Path.Combine(newRoot, rel);
                    Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                    File.Copy(file, dest, overwrite: true);
                }
                // 内容已整体复制到新目录，清空并删除旧缓存目录（缓存可重建，删之无碍）
                try { Directory.Delete(CacheRoot, recursive: true); }
                catch (Exception ex) { Debug.WriteLine($"清理旧缓存目录失败(可忽略): {ex.Message}"); }
            }
            Directory.CreateDirectory(newRoot);
            CacheRoot = newRoot;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"迁移缓存目录到 {newRoot} 失败: {ex.Message}");
        }
    }

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
