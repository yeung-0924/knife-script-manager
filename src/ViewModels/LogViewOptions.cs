using ScriptManager.Cache;

namespace ScriptManager.ViewModels;

/// <summary>
/// 日志面板显示选项（所有脚本共享）：显示行号 / 显示时间。
/// 脚本预览面板显示选项（所有脚本共享）：显示行号 / 自动换行。
/// 基于 ViewModelBase 实现属性通知；任一属性变更即持久化到 cache/logview.json。
/// </summary>
public sealed class LogViewOptions : ViewModelBase
{
    private bool _showLineNumbers;
    private bool _showTimestamp;
    private bool _scriptShowLineNumbers = true;
    private bool _scriptWordWrap = true;

    public LogViewOptions()
    {
        var s = LogViewCache.Load();
        _showLineNumbers = s.ShowLineNumbers;
        _showTimestamp = s.ShowTimestamp;
        _scriptShowLineNumbers = s.ScriptShowLineNumbers;
        _scriptWordWrap = s.ScriptWordWrap;
    }

    public bool ShowLineNumbers
    {
        get => _showLineNumbers;
        set
        {
            if (!SetProperty(ref _showLineNumbers, value)) return;
            Persist();
            OptionsChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public bool ShowTimestamp
    {
        get => _showTimestamp;
        set
        {
            if (!SetProperty(ref _showTimestamp, value)) return;
            Persist();
            OptionsChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public bool ScriptShowLineNumbers
    {
        get => _scriptShowLineNumbers;
        set
        {
            if (!SetProperty(ref _scriptShowLineNumbers, value)) return;
            Persist();
            OptionsChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public bool ScriptWordWrap
    {
        get => _scriptWordWrap;
        set
        {
            if (!SetProperty(ref _scriptWordWrap, value)) return;
            Persist();
            OptionsChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    /// <summary>任一显示选项（行号/时间/脚本预览）变更时触发，供 UI 重绘或立即应用。</summary>
    public event EventHandler? OptionsChanged;

    private void Persist()
    {
        LogViewCache.Save(new LogViewState
        {
            ShowLineNumbers = _showLineNumbers,
            ShowTimestamp = _showTimestamp,
            ScriptShowLineNumbers = _scriptShowLineNumbers,
            ScriptWordWrap = _scriptWordWrap,
        });
    }
}
