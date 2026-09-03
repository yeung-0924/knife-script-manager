using System.Collections.ObjectModel;
using System.IO;
using System.Reflection;
using System.Windows.Media.Imaging;

namespace ScriptManager.ViewModels;

/// <summary>
/// 树节点模型：支持两层结构——分组（Group，含嵌套分组）→ 脚本项（Script）。
/// 单一来源（来自 config.ini 配置的脚本目录，按 children 嵌套层级构建），不再有来源根层。
/// 绑定到 TreeView，图标按类型/语言选择；脚本项被选中时由 MainViewModel 监听 SelectedScript 处理。
/// </summary>
public class ScriptTreeItem : ViewModelBase
{
    public enum NodeKind { Root, Group, Script }

    public NodeKind Kind { get; }

    public string Name { get; }

    /// <summary>仅脚本项有值，指向 ScriptItem 实体。</summary>
    public ScriptItem? Item { get; }

    /// <summary>稳定路径标识（如 "自定义脚本/网络/show-ip"），用于跨刷新匹配展开/选中状态。</summary>
    public string Path { get; }

    public ObservableCollection<ScriptTreeItem> Children { get; } = new();

    private bool _isSelected;
    public bool IsSelected
    {
        get => _isSelected;
        set => SetProperty(ref _isSelected, value);
    }

    private bool _isExpanded = false;
    public bool IsExpanded
    {
        get => _isExpanded;
        set => SetProperty(ref _isExpanded, value);
    }

    /// <summary>程序集中全部嵌入资源名（首次访问时缓存），用于诊断与真实匹配命名空间。</summary>
    private static string[]? _allResourceNames;
    private static string[] AllResourceNames
    {
        get
        {
            if (_allResourceNames == null)
            {
                try { _allResourceNames = typeof(ScriptTreeItem).Assembly.GetManifestResourceNames(); }
                catch { _allResourceNames = new string[0]; }
            }
            return _allResourceNames;
        }
    }

    private BitmapSource? _icon;
    public BitmapSource? Icon
    {
        get
        {
            if (_icon != null) return _icon;
            _icon = LoadIcon();
            return _icon;
        }
    }

    private BitmapSource? LoadIcon()
    {
        var logicalName = Kind switch
        {
            NodeKind.Root => "icons.folder.ico",
            NodeKind.Group => "icons.folder.ico",
            NodeKind.Script => Item?.Lang?.ToLowerInvariant() switch
            {
                // 顺序遵循朝云约定：cmd → powershell → powershell7 → bash → java → nodejs → python → go → rust
                ScriptLangs.Cmd => "icons.cmd.ico",
                ScriptLangs.PowerShell => "icons.powershell.ico",
                ScriptLangs.Pwsh => "icons.pwsh.ico",
                ScriptLangs.Bash => "icons.bash.ico",
                ScriptLangs.Java => "icons.java.ico",
                ScriptLangs.Node => "icons.node.ico",
                ScriptLangs.Python => "icons.python.ico",
                ScriptLangs.Go => "icons.go.ico",
                ScriptLangs.Rust => "icons.rust.ico",
                _ => "icons.folder.ico"
            },
            _ => null
        };
        if (logicalName == null) return null;

        try
        {
            var asm = typeof(ScriptTreeItem).Assembly;
            // 真实资源名可能与预期命名空间不同；用 EndsWith 匹配 .LogicalName 形式，避免前缀猜测错误
            var match = AllResourceNames.FirstOrDefault(n => n.EndsWith(logicalName, StringComparison.OrdinalIgnoreCase));
            if (match == null)
                return null;

            using var stream = asm.GetManifestResourceStream(match);
            if (stream == null) return null;
            var decoder = new IconBitmapDecoder(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
            var frame = decoder.Frames[0];
            frame.Freeze();
            return frame;
        }
        catch
        {
            return null;
        }
    }

    public ScriptTreeItem(NodeKind kind, string name, ScriptItem? item = null, string path = "")
    {
        Kind = kind;
        Name = name;
        Item = item;
        Path = path;
    }
}
