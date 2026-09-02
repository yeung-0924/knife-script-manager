namespace ScriptManager.ViewModels;

/// <summary>
/// 单条日志模型：区分颜色（stdout 灰、error 红、系统/退出码 青），供 WPF RichTextBox/FlowDocument 渲染多色输出。
/// <see cref="Text"/> 为去除 ANSI 转义后的纯文本（用于复制/导出）；<see cref="Spans"/> 为可选的 ANSI 着色片段（null 表示用级别默认色）。
/// <see cref="Timestamp"/> 为日志产生时刻（在 UI 线程赋值，保证与显示顺序一致），供「显示时间」开关使用。
/// </summary>
public class LogEntry : ViewModelBase
{
    public enum Level { System, Output, Error, Exit }

    public Level Kind { get; }
    public string Text { get; }
    public IReadOnlyList<LogSpan>? Spans { get; }
    public DateTimeOffset Timestamp { get; }

    public LogEntry(Level kind, string text) : this(kind, text, null, DateTimeOffset.Now) { }

    public LogEntry(Level kind, string text, IReadOnlyList<LogSpan>? spans)
        : this(kind, text, spans, DateTimeOffset.Now) { }

    public LogEntry(Level kind, string text, IReadOnlyList<LogSpan>? spans, DateTimeOffset timestamp)
    {
        Kind = kind;
        Text = text;
        Spans = spans;
        Timestamp = timestamp;
    }
}
