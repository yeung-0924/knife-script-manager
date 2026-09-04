using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using ScriptManager.Utils;

namespace ScriptManager.Views;

/// <summary>
/// 配置编辑弹窗：结构化编辑 config.ini 的 [script] 节关键项。
/// 写入由 <see cref="AppConfig.SetRawValue"/> 保证保留注释/顺序/其它节；保存后调用
/// <see cref="AppConfig.Reload"/> 刷新内存缓存，但部分配置（如脚本目录切换）仍需重启才真正生效，
/// 故弹窗仅提示「已保存（重启后生效）」，不自动重建。
/// 目录/文件项均为只读选择框（浏览按钮），不可手输；未自定义时留空并显示默认相对路径占位符，
/// 点击 × 或「默认值」可清除、回落到内置相对默认（script\index.json / lib / runtime / cache / log）。
/// 「默认执行超时(秒)」是弹窗内唯一允许手输的数字项（空白 = 不限制）。
/// </summary>
public partial class ConfigEditorWindow : Window
{
    private readonly List<ConfigRow> _rows = new();
    // 默认执行超时(秒)：唯一可手输字段，空白 = 不限制（0）。
    private readonly TimeoutRow _timeout = new();

    public ConfigEditorWindow()
    {
        InitializeComponent();
        // 第四参数为「默认相对路径」（即未自定义时 AppConfig 实际使用的相对默认值），仅作占位提示；
        // 真实值永远存在 config.ini 的 [script] 节里（空 = 使用此相对默认），故内部值留空即可。
        _rows.Add(MakeRow("default_script_file", "默认脚本索引文件", "file", "script\\index.json"));
        _rows.Add(MakeRow("lib_dir", "第三方依赖目录", "folder", "lib"));
        _rows.Add(MakeRow("runtime_dir", "运行时安装目录", "folder", "runtime"));
        _rows.Add(MakeRow("cache_dir", "缓存目录", "folder", "cache"));
        _rows.Add(MakeRow("log_dir", "日志目录", "folder", "log"));
        Rows.ItemsSource = _rows;

        var tRaw = AppConfig.GetRawValue("script", "default_timeout");
        _timeout.Placeholder = Strings.ConfigEditorTimeoutPlaceholder;
        _timeout.Value = string.IsNullOrWhiteSpace(tRaw) ? "" : tRaw.Trim();
        TimeoutGrid.DataContext = _timeout;
    }

    /// <summary>
    /// 构建一行：内部 <see cref="ConfigRow.Value"/> 只保存用户在 config.ini 中的「自定义覆盖值」
    /// （绝对路径），未自定义时为空白。空白即代表「使用默认相对路径」，由 <see cref="AppConfig"/> 在
    /// 读取时回落到 Placeholder 所示的相对默认值（script\index.json / lib / runtime / cache / log）。
    /// </summary>
    private static ConfigRow MakeRow(string key, string label, string kind, string placeholder)
    {
        var raw = AppConfig.GetRawValue("script", key);
        return new ConfigRow
        {
            Key = key,
            Label = label,
            Kind = kind,
            Placeholder = placeholder,
            Value = string.IsNullOrWhiteSpace(raw) ? "" : raw.Trim(),
        };
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: ConfigRow row }) return;
        if (row.Kind == "folder")
        {
            var picked = FolderPicker.PickFolder(Strings.ConfigEditorBrowseFolder, row.Value);
            if (picked != null) row.Value = picked;
        }
        else if (row.Kind == "file")
        {
            var dlg = new OpenFileDialog
            {
                Title = Strings.ConfigEditorBrowseFile,
                Filter = "脚本索引 (index.json)|index.json|JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*",
                CheckFileExists = true,
                FileName = row.Value
            };
            if (dlg.ShowDialog() == true) row.Value = dlg.FileName;
        }
    }

    private void BtnSave_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            foreach (var row in _rows)
                AppConfig.SetRawValue("script", row.Key, row.Value.Trim());
            AppConfig.SetRawValue("script", "default_timeout", SanitizeTimeout(_timeout.Value));
            AppConfig.Reload();
            ShowStatus(Strings.ConfigEditorSaved);
        }
        catch (System.Exception ex)
        {
            ShowStatus(string.Format(Strings.ConfigEditorSaveFail, ex.Message));
        }
    }

    /// <summary>一键还原默认值：把各项清为「未自定义」（空白），由 AppConfig 回落到内置相对默认；立即写盘并刷新缓存。</summary>
    private void BtnReset_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            foreach (var row in _rows)
            {
                row.Value = "";
                AppConfig.SetRawValue("script", row.Key, "");
            }
            _timeout.Value = "";
            AppConfig.SetRawValue("script", "default_timeout", "");
            AppConfig.Reload();
            ShowStatus(Strings.ConfigEditorRestored);
        }
        catch (System.Exception ex)
        {
            ShowStatus(string.Format(Strings.ConfigEditorSaveFail, ex.Message));
        }
    }

    /// <summary>清除单行自定义：置空即回落到默认相对路径（占位符随之显示）。</summary>
    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: ConfigRow row })
            row.Value = "";
    }

    /// <summary>清除超时字段：置空即回落到「不限制」（0）。</summary>
    private void TimeoutClear_Click(object sender, RoutedEventArgs e) => _timeout.Value = "";

    /// <summary>超时输入框仅允许数字，拦截其它字符的输入。</summary>
    private void Timeout_PreviewTextInput(object sender, TextCompositionEventArgs e)
    {
        foreach (var c in e.Text)
            if (!char.IsDigit(c)) { e.Handled = true; return; }
    }

    /// <summary>取出超时文本中的纯数字部分；空或非数字则返回空（AppConfig 解析为空=不限制）。</summary>
    private static string SanitizeTimeout(string value)
    {
        value = (value ?? "").Trim();
        if (value.Length == 0) return "";
        var sb = new System.Text.StringBuilder();
        foreach (var c in value)
            if (char.IsDigit(c)) sb.Append(c);
        return sb.ToString();
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => Close();

    private void ShowStatus(string text)
    {
        StatusText.Text = text;
        StatusText.Visibility = Visibility.Visible;
    }
}

/// <summary>配置编辑弹窗的一行绑定模型（目录/文件选择：只读展示 + 浏览/清除修改）。</summary>
public class ConfigRow : INotifyPropertyChanged
{
    public string Key { get; set; } = "";
    public string Label { get; set; } = "";
    /// <summary>folder=选目录；file=选文件。</summary>
    public string Kind { get; set; } = "folder";
    /// <summary>未自定义时显示的默认相对路径占位符（如 script\index.json / lib）。</summary>
    public string Placeholder { get; set; } = "";

    // Value 仅保存用户在 config.ini 中的「自定义覆盖值」（绝对路径）；空白 = 使用默认相对路径。
    private string _value = "";
    public string Value
    {
        get => _value;
        set { if (_value != value) { _value = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value))); } }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}

/// <summary>默认执行超时(秒) 绑定模型：配置编辑器内唯一允许手输的字段；空白 = 不限制（0）。</summary>
public class TimeoutRow : INotifyPropertyChanged
{
    /// <summary>未填写时显示的占位提示（如「0（不限制）」）。</summary>
    public string Placeholder { get; set; } = "";

    // Value 保存用户输入的纯数字字符串；空白 = 不限制。
    private string _value = "";
    public string Value
    {
        get => _value;
        set { if (_value != value) { _value = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value))); } }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
