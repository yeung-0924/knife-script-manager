using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using ScriptManager.Cache;
using ScriptManager.Utils;
using ScriptManager.ViewModels;

namespace ScriptManager.Views;

/// <summary>
/// 配置编辑弹窗：结构化编辑 config.ini 的 [script] 节关键项。
/// 写入由 <see cref="AppConfig.SetRawValue"/> 保证保留注释/顺序/其它节；保存后调用
/// <see cref="AppConfig.Reload"/> 刷新内存缓存。所有配置项均为「保存即生效、无需重启」：
/// <list type="bullet">
///   <item>脚本索引文件(script_index_file)被改动时，通知宿主视图模型实时重建左侧目录树；</item>
///   <item>缓存目录(cache_dir)被改动时，<see cref="CacheStore.Relocate"/> 把旧目录内容整体迁移到新目录并即时切换，无需重启；</item>
///   <item>运行时目录(runtime_dir)/日志目录(log_dir)等仅作环境变量注入或目录图标，下次启动脚本/重绘即生效。</item>
/// </list>
/// 目录/文件项均为只读选择框（浏览按钮），不可手输；未自定义时留空并显示默认相对路径占位符，
/// 点击 × 或「默认值」可清除、回落到内置相对默认（script\index.json / lib / runtime / cache / log）。
/// 「默认执行超时(秒)」是弹窗内唯一允许手输的数字项（空白 = 不限制）。
/// </summary>
public partial class ConfigEditorWindow : Window
{
    private readonly List<ConfigRow> _rows = new();
    // 默认执行超时(秒)：唯一可手输字段，空白 = 不限制（0）。
    private readonly TimeoutRow _timeout = new();

    /// <summary>宿主主窗口的视图模型，保存后用于触发左侧目录树按新脚本索引重建；可为 null（防御性）。</summary>
    public MainViewModel? OwnerViewModel { get; set; }

    public ConfigEditorWindow()
    {
        InitializeComponent();
        // 第四参数为「默认相对路径」（即未自定义时 AppConfig 实际使用的相对默认值），仅作占位提示；
        // 真实值永远存在 config.ini 的 [script] 节里（空 = 使用此相对默认），故内部值留空即可。
        _rows.Add(MakeRow("script_index_file", "脚本索引文件", "file", "script\\index.json"));
        _rows.Add(MakeRow("lib_dir", "第三方依赖目录", "folder", "lib"));
        _rows.Add(MakeRow("runtime_dir", "运行时安装目录", "folder", "runtime"));
        _rows.Add(MakeRow("cache_dir", "缓存目录", "folder", "cache"));
        _rows.Add(MakeRow("log_dir", "日志目录", "folder", "log"));
        Rows.ItemsSource = _rows;

        // 超时同理：留空或显式写 0 都表示「不限制」，统一显示为空白 + 占位符「0（不限制）」
        var tRaw = AppConfig.GetRawValue("script", "default_timeout")?.Trim();
        _timeout.Placeholder = Strings.ConfigEditorTimeoutPlaceholder;
        _timeout.Value = string.IsNullOrWhiteSpace(tRaw) || tRaw == "0" ? "" : tRaw;
        TimeoutGrid.DataContext = _timeout;
    }

    /// <summary>
    /// 构建一行：内部 <see cref="ConfigRow.Value"/> 只保存用户在 config.ini 中的「自定义覆盖值」
    /// （绝对路径），未自定义时为空白。空白即代表「使用默认相对路径」，由 <see cref="AppConfig"/> 在
    /// 读取时回落到 Placeholder 所示的相对默认值（script\index.json / lib / runtime / cache / log）。
    /// 注意：config.ini 里若把默认相对路径原样写了出来（如 lib_dir = lib），语义与留空完全等价，
    /// 此时同样视为「未自定义」，显示为空白 + 占位符，避免用户误以为已经改过配置。
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
            Value = IsBuiltInDefault(raw, placeholder) ? "" : raw!.Trim(),
        };
    }

    /// <summary>
    /// 判断 config.ini 中的显式值是否等同于内置默认：留空当然是默认；把默认相对路径原样写出来
    /// （如 script\index.json / lib）语义也与留空一致，同样按默认处理。
    /// </summary>
    private static bool IsBuiltInDefault(string? raw, string placeholder)
    {
        if (string.IsNullOrWhiteSpace(raw)) return true;
        return NormalizePath(raw) == NormalizePath(placeholder);
    }

    /// <summary>路径等价性归一化：统一分隔符、去结尾斜杠、去 .\ 前缀、忽略大小写。</summary>
    private static string NormalizePath(string p)
    {
        p = p.Trim().Replace('/', '\\').TrimEnd('\\');
        if (p.StartsWith(".\\", StringComparison.Ordinal)) p = p[2..];
        return p.ToLowerInvariant();
    }

    /// <summary>
    /// 配置落盘并刷新内存后，使「需即时切换」的项无需重启即生效：
    /// ① cache_dir 改动 → <see cref="CacheStore.Relocate"/> 把旧缓存内容迁到新目录并切换 CacheStore.CacheRoot；
    /// ② 标准目录（config/log/cache/runtime/lib/script）重新套用彩色文件夹图标，使新目录立即获得图标、
    ///    旧目录的残留图标在下一次打开资源管理器时被覆盖（旧缓存目录已被 Relocate 清空，无碍）。
    /// 两者均自带异常吞没与调试日志，绝不抛出影响主流程。
    /// </summary>
    private static void ApplyLiveEffects()
    {
        try { CacheStore.Relocate(AppConfig.CacheDir); } catch (Exception ex) { Debug.WriteLine("缓存目录切换失败(可忽略): " + ex.Message); }
        try { FolderCustomizer.ApplyToStandardDirs(); } catch (Exception ex) { Debug.WriteLine("文件夹图标刷新失败(可忽略): " + ex.Message); }
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
            // 保存前记录当前脚本索引路径，便于判断本次是否改动了它
            var oldIndex = AppConfig.ScriptIndexJsonPath;
            foreach (var row in _rows)
                AppConfig.SetRawValue("script", row.Key, row.Value.Trim());
            AppConfig.SetRawValue("script", "default_timeout", SanitizeTimeout(_timeout.Value));
            AppConfig.Reload();
            // cache_dir 迁移 + 标准目录图标刷新：使目录类配置改动保存即生效，无需重启
            ApplyLiveEffects();
            // 若脚本索引文件被改动，左侧目录树需按新索引重新渲染（与「文件▸打开」同源）
            if (!string.Equals(oldIndex, AppConfig.ScriptIndexJsonPath, System.StringComparison.OrdinalIgnoreCase))
                OwnerViewModel?.ReloadTree();
            // 保存成功后关闭弹窗
            Close();
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("保存配置失败：" + ex.Message);
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
            // 还原默认值同样可能把 cache_dir 改回内置默认，即时迁移 + 刷新图标，避免重启
            ApplyLiveEffects();
        }
        catch (System.Exception ex)
        {
            System.Diagnostics.Debug.WriteLine("还原默认值失败：" + ex.Message);
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
