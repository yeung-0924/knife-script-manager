using System.Text.Json;

namespace ScriptManager.Cache;

/// <summary>
/// 日志面板显示选项缓存：所有脚本共享同一套开关（显示行号 / 显示时间）。
/// 持久化到 cache/logview.json，进程退出后再启动仍保留上次选择。
/// </summary>
public static class LogViewCache
{
    private const string FileName = "logview.json";

    public static LogViewState Load()
        => CacheStore.ReadJson<LogViewState>(FileName) ?? new LogViewState();

    public static void Save(LogViewState state)
        => CacheStore.WriteJson(FileName, state);
}

/// <summary>日志面板开关的纯数据形态，便于 JSON 序列化。</summary>
public sealed class LogViewState
{
    public bool ShowLineNumbers { get; set; }
    public bool ShowTimestamp { get; set; }
    public bool ScriptShowLineNumbers { get; set; }
    public bool ScriptWordWrap { get; set; }
}
