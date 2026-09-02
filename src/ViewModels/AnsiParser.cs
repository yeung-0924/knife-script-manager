using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Windows.Media;

namespace ScriptManager.ViewModels;

/// <summary>
/// 单段已解析文本（可能带 ANSI 前景色）。<see cref="Foreground"/> 为 null 表示「用所属日志级别的默认色」。
/// </summary>
public readonly struct LogSpan
{
    public string Text { get; }
    public Brush? Foreground { get; }

    public LogSpan(string text, Brush? foreground)
    {
        Text = text;
        Foreground = foreground;
    }
}

/// <summary>
/// 解析 ANSI SGR 转义（如 <c>\u001b[31m</c> 红、<c>\u001b[0m</c> 重置）为彩色文本片段。
/// 仅处理前景色（30-37 / 90-97），其余 SGR 参数（粗体等）忽略；转义序列本身不保留到文本中。
/// 这样 Java 等脚本用 <c>System.out.println("\u001b[31m红色\u001b[0m")</c> 也能在日志面板着色。
/// </summary>
public static class AnsiParser
{
    // ESC [ params m
    private static readonly Regex Sgr = new(@"\x1b\[([0-9;]*)m", RegexOptions.Compiled);

    private static readonly Dictionary<int, Brush> Fg = new()
    {
        [30] = Brushes.Black,       [31] = Brushes.Red,         [32] = Brushes.Green,
        [33] = Brushes.Yellow,      [34] = Brushes.Blue,        [35] = Brushes.Magenta,
        [36] = Brushes.Cyan,        [37] = Brushes.White,
        [90] = Brushes.Gray,        [91] = Brushes.Tomato,      [92] = Brushes.LimeGreen,
        [93] = Brushes.Gold,        [94] = Brushes.DodgerBlue,  [95] = Brushes.Violet,
        [96] = Brushes.Cyan,        [97] = Brushes.White,
    };

    /// <summary>
    /// 把含 ANSI 的文本拆成片段；不含转义时返回单片段（Foreground=null）。
    /// </summary>
    public static List<LogSpan> Parse(string text)
    {
        var result = new List<LogSpan>();
        Brush? current = null; // null = 用日志级别默认色
        var matches = Sgr.Matches(text);
        if (matches.Count == 0)
        {
            result.Add(new LogSpan(text, null));
            return result;
        }

        var last = 0;
        foreach (Match m in matches)
        {
            if (m.Index > last)
                result.Add(new LogSpan(text.Substring(last, m.Index - last), current));

            foreach (var raw in m.Groups[1].Value.Split(';'))
            {
                if (!int.TryParse(raw, out var code)) continue;
                if (code == 0) current = null;                 // 重置
                else if (Fg.TryGetValue(code, out var b)) current = b; // 前景色
                // 粗体(1)/下划线(4)/背景色等：忽略，不破坏着色
            }
            last = m.Index + m.Length;
        }
        if (last < text.Length)
            result.Add(new LogSpan(text.Substring(last), current));

        return result;
    }
}
