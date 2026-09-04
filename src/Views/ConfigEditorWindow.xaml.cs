using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using ScriptManager.Utils;

namespace ScriptManager.Views;

/// <summary>
/// 配置编辑弹窗：结构化编辑 config.ini 的 [script] 节关键项。
/// 写入由 <see cref="AppConfig.SetRawValue"/> 保证保留注释/顺序/其它节；保存后调用
/// <see cref="AppConfig.Reload"/> 刷新内存缓存，但部分配置（如脚本目录切换）仍需重启才真正生效，
/// 故弹窗仅提示「已保存（重启后生效）」，不自动重建。
/// 字段均为目录/文件选择（只读输入框 + 浏览按钮），不可手输、不可置空；「默认值」可一键还原。
/// </summary>
public partial class ConfigEditorWindow : Window
{
    private readonly List<ConfigRow> _rows = new();

    public ConfigEditorWindow()
    {
        InitializeComponent();
        _rows.Add(MakeRow("default_script_file", "默认脚本索引文件", "file", AppConfig.DefaultScriptFilePath));
        _rows.Add(MakeRow("lib_dir", "第三方依赖目录", "folder", AppConfig.LibDir));
        _rows.Add(MakeRow("runtime_dir", "运行时安装目录", "folder", AppConfig.RuntimeDir));
        _rows.Add(MakeRow("cache_dir", "缓存目录", "folder", AppConfig.CacheDir));
        _rows.Add(MakeRow("log_dir", "日志目录", "folder", AppConfig.LogDir));
        Rows.ItemsSource = _rows;
    }

    /// <summary>构建一行：未自定义时显示解析后的默认值（保证输入框非空、不可置空）。</summary>
    private static ConfigRow MakeRow(string key, string label, string kind, string resolvedDefault)
    {
        var raw = AppConfig.GetRawValue("script", key);
        var effective = string.IsNullOrWhiteSpace(raw) ? resolvedDefault : raw.Trim();
        return new ConfigRow
        {
            Key = key,
            Label = label,
            Kind = kind,
            Value = effective,
            DefaultValue = resolvedDefault,
            DefaultHint = "默认：" + resolvedDefault,
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
            AppConfig.Reload();
            ShowStatus(Strings.ConfigEditorSaved);
        }
        catch (System.Exception ex)
        {
            ShowStatus(string.Format(Strings.ConfigEditorSaveFail, ex.Message));
        }
    }

    /// <summary>一键还原默认值：立即写回内置默认并刷新缓存，用户无需再点「保存」。</summary>
    private void BtnReset_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            foreach (var row in _rows)
            {
                row.Value = row.DefaultValue;
                AppConfig.SetRawValue("script", row.Key, row.DefaultValue.Trim());
            }
            AppConfig.Reload();
            ShowStatus(Strings.ConfigEditorRestored);
        }
        catch (System.Exception ex)
        {
            ShowStatus(string.Format(Strings.ConfigEditorSaveFail, ex.Message));
        }
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => Close();

    private void ShowStatus(string text)
    {
        StatusText.Text = text;
        StatusText.Visibility = Visibility.Visible;
    }
}

/// <summary>配置编辑弹窗的一行绑定模型（目录/文件选择：只读展示 + 浏览修改）。</summary>
public class ConfigRow : INotifyPropertyChanged
{
    public string Key { get; set; } = "";
    public string Label { get; set; } = "";
    /// <summary>folder=选目录；file=选文件。</summary>
    public string Kind { get; set; } = "folder";
    public string DefaultHint { get; set; } = "";
    /// <summary>解析后的内置默认值，供「默认值」按钮还原。</summary>
    public string DefaultValue { get; set; } = "";

    private string _value = "";
    public string Value
    {
        get => _value;
        set { if (_value != value) { _value = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value))); } }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
