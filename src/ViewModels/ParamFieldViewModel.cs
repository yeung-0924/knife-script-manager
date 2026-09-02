using System.Collections.Generic;
using System.Linq;
using System.Windows.Input;

namespace ScriptManager.ViewModels;

/// <summary>
/// 单个参数输入控件模型：根据 ScriptParam 的 Options 决定渲染为 TextBox（无选项）或 ComboBox（有选项）。
/// 绑定到 View 的 ItemsControl，替代原 WinForms 手动 BuildParamControls 的布局 hack。
/// </summary>
public class ParamFieldViewModel : ViewModelBase
{
    public ScriptParam Param { get; }

    /// <summary>界面显示名：优先用 json 的 label，缺失时回退到 name</summary>
    public string Name => string.IsNullOrWhiteSpace(Param.Label) ? Param.Name : Param.Label!;

    public string Placeholder => Param.Placeholder ?? "";

    public bool Required => Param.Required;

    public bool HasOptions => Param.Options != null && Param.Options.Count > 0;

    public List<string> Options => Param.Options ?? new List<string>();

    /// <summary>是否为"选文件"型参数（文本框右侧显示浏览…按钮，弹文件选择框）。</summary>
    public bool IsFile => string.Equals((Param.Type ?? "text"), "file", System.StringComparison.OrdinalIgnoreCase);

    /// <summary>是否为"选目录"型参数（文本框右侧显示浏览…按钮，弹目录选择框）。</summary>
    public bool IsFolder => string.Equals((Param.Type ?? "text"), "folder", System.StringComparison.OrdinalIgnoreCase);

    /// <summary>是否为"选文件/选目录"型：文本框右侧显示浏览…按钮。</summary>
    public bool IsPath => IsFile || IsFolder;

    /// <summary>清空当前值。下拉框（有 Options）一旦选中就无法再回到"未选"状态，靠此按钮清空。</summary>
    public ICommand ClearCommand { get; }

    /// <summary>浏览按钮命令：弹出文件/目录选择框，把选中路径写回 Value。弹窗由 View 通过 PickPath 注入。</summary>
    public ICommand BrowseCommand { get; }

    /// <summary>
    /// View 注入的弹窗委托：接收该字段（IsFile/IsFolder 已就绪），返回选中路径（取消/无则 null）。
    /// 让 ViewModel 不直接依赖 WPF 对话框，保持 MVVM 分层。
    /// </summary>
    public Func<ParamFieldViewModel, string?>? PickPath { get; set; }

    private string _value = "";
    public string Value
    {
        get => _value;
        set
        {
            if (!SetProperty(ref _value, value)) return;
            // 值变化即更新缺失状态：填了就不算缺失，清空且必填则标红
            IsMissing = Required && string.IsNullOrWhiteSpace(_value);
        }
    }

    private bool _isMissing;
    /// <summary>必填但未填写：输入框标红，且禁止执行。由 MainViewModel.ValidateRequired() 统一管理，值变化时也会自更新。</summary>
    public bool IsMissing
    {
        get => _isMissing;
        set
        {
            SetProperty(ref _isMissing, value);
        }
    }

    public ParamFieldViewModel(ScriptParam param)
    {
        Param = param;
        ClearCommand = new RelayCommand(_ => Value = "");
        BrowseCommand = new RelayCommand(_ => Browse());
        // 有默认值时预填（Options 首项的语义由脚本决定，这里不自动选，保持空白让用户显式选择）
        // 注意：此处用私有字段 _value 而非 Value 属性，避免构造期间触发属性变更通知
        if (!string.IsNullOrEmpty(param.Default))
            _value = param.Default;
    }

    private void Browse()
    {
        var path = PickPath?.Invoke(this);
        if (!string.IsNullOrEmpty(path))
            Value = path!;
    }
}
