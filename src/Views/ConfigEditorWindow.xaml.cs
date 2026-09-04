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
/// </summary>
public partial class ConfigEditorWindow : Window
{
    public ConfigEditorWindow()
    {
        InitializeComponent();
        var rows = new List<ConfigRow>
        {
            new ConfigRow { Key = "default_script_file", Label = "默认脚本索引文件", Kind = "file",
                Value = AppConfig.GetRawValue("script", "default_script_file") ?? "",
                DefaultHint = "默认：" + AppConfig.DefaultScriptFilePath },
            new ConfigRow { Key = "lib_dir", Label = "第三方依赖目录", Kind = "folder",
                Value = AppConfig.GetRawValue("script", "lib_dir") ?? "",
                DefaultHint = "默认：" + AppConfig.LibDir },
            new ConfigRow { Key = "runtime_dir", Label = "运行时安装目录", Kind = "folder",
                Value = AppConfig.GetRawValue("script", "runtime_dir") ?? "",
                DefaultHint = "默认：" + AppConfig.RuntimeDir },
            new ConfigRow { Key = "cache_dir", Label = "缓存目录", Kind = "folder",
                Value = AppConfig.GetRawValue("script", "cache_dir") ?? "",
                DefaultHint = "默认：" + AppConfig.CacheDir },
            new ConfigRow { Key = "log_dir", Label = "日志目录", Kind = "folder",
                Value = AppConfig.GetRawValue("script", "log_dir") ?? "",
                DefaultHint = "默认：" + AppConfig.LogDir },
            new ConfigRow { Key = "default_timeout", Label = "默认执行超时(秒)", Kind = "text",
                Value = AppConfig.GetRawValue("script", "default_timeout") ?? "",
                DefaultHint = "0 = 不限制" },
        };
        Rows.ItemsSource = rows;
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
            foreach (ConfigRow row in Rows.ItemsSource)
                AppConfig.SetRawValue("script", row.Key, row.Value.Trim());
            AppConfig.Reload();
            StatusText.Text = Strings.ConfigEditorSaved;
            StatusText.Visibility = Visibility.Visible;
        }
        catch (System.Exception ex)
        {
            StatusText.Text = string.Format(Strings.ConfigEditorSaveFail, ex.Message);
            StatusText.Visibility = Visibility.Visible;
        }
    }

    private void BtnCancel_Click(object sender, RoutedEventArgs e) => Close();
}

/// <summary>配置编辑弹窗的一行绑定模型（路径类带「浏览」按钮）。</summary>
public class ConfigRow : INotifyPropertyChanged
{
    public string Key { get; set; } = "";
    public string Label { get; set; } = "";
    /// <summary>text=普通文本；folder=目录浏览；file=文件浏览。</summary>
    public string Kind { get; set; } = "text";
    public bool IsPath => Kind != "text";
    public string DefaultHint { get; set; } = "";

    private string _value = "";
    public string Value
    {
        get => _value;
        set { if (_value != value) { _value = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Value))); } }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
}
