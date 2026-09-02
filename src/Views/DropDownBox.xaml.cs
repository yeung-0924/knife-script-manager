using System.Collections;
using System.Windows;
using System.Windows.Controls;

namespace ScriptManager.Views;

/// <summary>
/// 外观等同普通输入框（TextBox），但点击时弹出下拉列表供选择；同时仍允许自由输入。
/// 解决原生 ComboBox 在可编辑模式下点击文本会强制收起下拉、且边框/聚焦态与纯输入框不一致的问题。
/// </summary>
public partial class DropDownBox : UserControl
{
    // 标记当前是否正在把外部 SelectedItem 反向同步到内部 ListBox。
    // 用于区分「VM 初始化/代码赋值」和「用户真正点击列表项」：前者不应抢夺焦点。
    private bool _syncingListSelection;

    public static readonly DependencyProperty TextProperty =
        DependencyProperty.Register(
            nameof(Text), typeof(string), typeof(DropDownBox),
            new FrameworkPropertyMetadata(string.Empty, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault));

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    public static readonly DependencyProperty ItemsSourceProperty =
        DependencyProperty.Register(
            nameof(ItemsSource), typeof(IEnumerable), typeof(DropDownBox));

    public IEnumerable? ItemsSource
    {
        get => (IEnumerable?)GetValue(ItemsSourceProperty);
        set => SetValue(ItemsSourceProperty, value);
    }

    /// <summary>校验失败标记（如必填未填写）：内部输入框标红。
    /// 本控件外观由内部 TextBox 呈现，直接对 UserControl 设 BorderBrush 无效，故通过此 DP 传给内部元素。</summary>
    public static readonly DependencyProperty IsInvalidProperty =
        DependencyProperty.Register(
            nameof(IsInvalid), typeof(bool), typeof(DropDownBox),
            new FrameworkPropertyMetadata(false));

    public bool IsInvalid
    {
        get => (bool)GetValue(IsInvalidProperty);
        set => SetValue(IsInvalidProperty, value);
    }

    /// <summary>当前选中的对象（用于需要强类型选中值的场景）。
    /// 设为 TwoWay 时，VM 初始化默认值也会反向驱动输入框文本与列表高亮。</summary>
    public static readonly DependencyProperty SelectedItemProperty =
        DependencyProperty.Register(
            nameof(SelectedItem), typeof(object), typeof(DropDownBox),
            new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnSelectedItemChanged));

    public object? SelectedItem
    {
        get => GetValue(SelectedItemProperty);
        set => SetValue(SelectedItemProperty, value);
    }

    private static void OnSelectedItemChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var box = (DropDownBox)d;
        // 反向同步：VM 设置默认选中项时，更新输入框文本，并在列表中高亮对应项
        var item = e.NewValue;
        box.Text = item?.ToString() ?? string.Empty;
        if (item != null && box.List.ItemsSource != null)
        {
            foreach (var obj in box.List.ItemsSource)
            {
                if (Equals(obj, item))
                {
                    box._syncingListSelection = true;
                    try
                    {
                        box.List.SelectedItem = obj;
                    }
                    finally
                    {
                        box._syncingListSelection = false;
                    }
                    break;
                }
            }
        }
    }

    public DropDownBox()
    {
        InitializeComponent();
    }

    private void Input_PreviewMouseDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        // 只读模式：点击即弹出下拉列表（始终展开，便于选择）
        Popup.IsOpen = true;
    }

    private void Input_LostFocus(object sender, RoutedEventArgs e)
    {
        // 延迟到焦点稳定后再判断，避免点击列表项瞬间误关
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Background, new System.Action(() =>
        {
            if (!Popup.IsKeyboardFocusWithin)
                Popup.IsOpen = false;
        }));
    }

    private void List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (List.SelectedItem != null)
        {
            SelectedItem = List.SelectedItem;
            Text = List.SelectedItem.ToString() ?? string.Empty;
        }
        Popup.IsOpen = false;
        // 只有用户真正从下拉列表选择时才把焦点拉回输入框；VM 初始化同步时不抢焦点。
        if (!_syncingListSelection)
            Input.Focus();
    }
}
