using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using ScriptManager.ViewModels;

namespace ScriptManager.Views;

/// <summary>
/// 主窗口代码-behind：极薄层，仅做 DataContext 绑定、TreeView 选中转发、窗口状态持久化、默认展开所有节点。
/// 所有业务逻辑在 MainViewModel 中。
/// </summary>
public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly LogViewOptions _logOptions = new();
    private int _logLineNo = 0;

    public MainWindow()
    {
        InitializeComponent();
        _vm = new MainViewModel();
        DataContext = _vm;

        // 窗口显示前就位：全屏/最大化立即生效，避免先普通尺寸闪一帧（位置不缓存）
        ScriptManager.Cache.WindowStateCache.ApplyPreShow(this);

        // 窗口加载完成后：普通窗口恢复尺寸，并把初始焦点设到左侧目录树，
        // 避免默认焦点落到顶部编码框导致其蓝框高亮
        Loaded += (_, _) =>
        {
            ScriptManager.Cache.WindowStateCache.ApplyNormalSize(this);
            ScriptTreeView.Focus();
        };

        // 脚本预览为只读查看器（AvalonEdit）：隐藏光标，但保留鼠标拖选 + Ctrl+C 复制。
        // 说明：AvalonEdit 的 IsReadOnly=True 仍会绘制光标；把 CaretBrush 设为透明即可隐藏，
        //       而文本选择由 SelectionBrush 独立渲染，隐藏光标不影响选中与复制。
        //       这两个属性都挂在 TextArea / TextArea.Caret 下，XAML 的 Class.Property 语法
        //       无法解析（TextArea 不是 TextEditor 的依赖属性宿主），故在代码中设置。
        ScriptEditor.TextArea.Caret.CaretBrush = Brushes.Transparent;
        ScriptEditor.TextArea.SelectionBrush = (Brush)FindResource("BrushSelection");

        // 执行日志：RichTextBox 多色渲染。监听 Logs 集合变化，按 Level 追加带色段落。
        LogBox.Document = new FlowDocument();
        _vm.Logs.CollectionChanged += LogEntries_CollectionChanged;
        // 切脚本时 Logs 会被整体替换为新集合（从 _logCache 恢复历史日志）。需重新订阅，
        // 并立即用恢复出的快照重建文档，否则切回后看不到之前执行的日志。
        _vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(MainViewModel.Logs)) return;
            _vm.Logs.CollectionChanged += LogEntries_CollectionChanged;
            RefreshLogs();
        };

        // 显示选项承载实例：所有脚本共享，挂到窗口 Tag 供 XAML（脚本预览）与齿轮菜单（日志/预览）双向绑定。
        this.Tag = _logOptions;
        BtnLogOptions.Tag = _logOptions;
        LogOptionsMenu.Tag = _logOptions;
        BtnScriptOptions.Tag = _logOptions;
        ScriptOptionsMenu.Tag = _logOptions;
        // 行号/时间开关变更后重绘整段日志，使历史日志也立即生效；脚本预览选项由 XAML 绑定即时应用
        _logOptions.OptionsChanged += (_, _) => RefreshLogs();

        // 齿轮菜单使用自定义定位：默认右边缘对齐按钮右边缘，避免靠近窗口右边缘时被截断
        LogOptionsMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Custom;
        LogOptionsMenu.CustomPopupPlacementCallback = PlaceContextMenuRightAligned;
        ScriptOptionsMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Custom;
        ScriptOptionsMenu.CustomPopupPlacementCallback = PlaceContextMenuRightAligned;
    }

    /// <summary>
    /// 日志集合变化 → 把新增条目按 Level 着色追加到 RichTextBox，并自动滚到底部。
    /// Reset（清空）时同步清空文档。整个动作在 UI 线程执行，符合 RichTextBox 的线程要求。
    /// <summary>
    /// Logs 集合变化回调：Reset（清空/切脚本）时重建文档并重置行号；否则逐条追加。
    /// 行号按「当前显示的第几条日志」递增，与显示时间开关无关。
    /// </summary>
    private void LogEntries_CollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        if (e.Action == System.Collections.Specialized.NotifyCollectionChangedAction.Reset)
        {
            LogBox.Document.Blocks.Clear();
            _logLineNo = 0;
            LogBox.ScrollToEnd();
            return;
        }
        if (e.NewItems == null) return;
        foreach (LogEntry entry in e.NewItems)
        {
            _logLineNo++;
            LogBox.Document.Blocks.Add(BuildParagraph(entry, _logLineNo));
        }
        // 自动滚动到底部，保持「最新日志可见」
        LogBox.ScrollToEnd();
    }

    /// <summary>
    /// 选项（行号/时间）变更后重绘整段日志：清空并依当前开关重建全部段落，历史日志也立即生效。
    /// 行号从 1 开始连续编号。
    /// </summary>
    private void RefreshLogs()
    {
        _logLineNo = 0;
        var doc = new FlowDocument();
        foreach (var entry in _vm.Logs)
        {
            _logLineNo++;
            doc.Blocks.Add(BuildParagraph(entry, _logLineNo));
        }
        LogBox.Document = doc;
        // 重建文档后会重置到顶部，这里恢复到该脚本上次离开时的滚动位置（与预览面板一致）
        var offset = _vm.GetLogScrollOffset();
        if (offset > 0)
            LogBox.ScrollToVerticalOffset(offset);
    }

    /// <summary>
    /// 构建单条日志段落：可选行号前缀（"  12 │ "）+ 可选时间前缀（"[HH:mm:ss.fff] "）+ 彩色正文。
    /// </summary>
    private Paragraph BuildParagraph(LogEntry entry, int lineNo)
    {
        var defaultBrush = entry.Kind switch
        {
            LogEntry.Level.System => (Brush)FindResource("BrushLogSystem"),
            LogEntry.Level.Output => (Brush)FindResource("BrushLogOutput"),
            LogEntry.Level.Error => (Brush)FindResource("BrushLogError"),
            LogEntry.Level.Exit => (Brush)FindResource("BrushLogExit"),
            _ => (Brush)FindResource("BrushLogOutput")
        };
        var dimBrush = (Brush)FindResource("BrushLogLineNo");

        var prefixBuilder = new System.Text.StringBuilder();
        if (_logOptions.ShowLineNumbers)
            prefixBuilder.Append($"{lineNo,4} │ ");
        if (_logOptions.ShowTimestamp)
            prefixBuilder.Append($"[{entry.Timestamp:HH:mm:ss.fff}] ");
        var prefix = prefixBuilder.ToString();

        var para = new Paragraph();

        // 悬挂缩进：把前缀作为"外凸"的左边界，使自动换行后的后续行与第一行正文对齐。
        if (prefix.Length > 0)
        {
            var prefixWidth = MeasurePrefixWidth(prefix);
            para.Margin = new Thickness(prefixWidth, 0, 0, 0);
            para.TextIndent = -prefixWidth;
            para.Inlines.Add(new Run(prefix) { Foreground = dimBrush });
        }

        if (entry.Spans != null && entry.Spans.Count > 0)
        {
            // 含 ANSI 着色片段：逐片段上色，无显式色的片段回退到级别默认色
            foreach (var span in entry.Spans)
            {
                var run = new Run(span.Text);
                if (span.Foreground != null) run.Foreground = span.Foreground;
                else run.Foreground = defaultBrush;
                para.Inlines.Add(run);
            }
        }
        else
        {
            para.Inlines.Add(new Run(entry.Text) { Foreground = defaultBrush });
        }
        return para;
    }

    /// <summary>测量前缀在日志 RichTextBox 当前字体下的宽度，用于悬挂缩进对齐。</summary>
    private double MeasurePrefixWidth(string prefix)
    {
        var measureBlock = new TextBlock
        {
            Text = prefix,
            FontFamily = LogBox.FontFamily,
            FontSize = LogBox.FontSize,
            FontStyle = LogBox.FontStyle,
            FontWeight = LogBox.FontWeight,
            FontStretch = LogBox.FontStretch,
        };
        measureBlock.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        return measureBlock.DesiredSize.Width;
    }

    /// <summary>齿轮按钮：点击在按钮正下方弹出下拉菜单（显式指定 PlacementTarget，避免跑到窗口左上角）。</summary>
    private void BtnLogOptions_Click(object sender, RoutedEventArgs e) => OpenOptionsMenu(sender, e);

    /// <summary>脚本预览齿轮按钮：点击在按钮正下方弹出下拉菜单（显式指定 PlacementTarget，避免跑到窗口左上角）。</summary>
    private void BtnScriptOptions_Click(object sender, RoutedEventArgs e) => OpenOptionsMenu(sender, e);

    /// <summary>打开选项菜单：Placement 已在构造时设为 Custom，这里只指定目标并打开。</summary>
    private void OpenOptionsMenu(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.ContextMenu != null)
        {
            var cm = btn.ContextMenu;
            cm.PlacementTarget = btn;
            cm.IsOpen = true;
            e.Handled = true;
        }
    }

    /// <summary>顶部「设置 ▸ 编辑配置」：打开 config.ini 结构化编辑弹窗（模态， Owner=主窗口）。</summary>
    private void MenuEditConfig_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ConfigEditorWindow { Owner = this };
        dlg.ShowDialog();
    }

    /// <summary>顶部「设置 ▸ 打开配置目录」：在资源管理器中选中 config.ini，便于手动编辑。</summary>
    private void MenuOpenConfigDir_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dir = AppConfig.ConfigDir;
            Directory.CreateDirectory(dir);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{Path.Combine(dir, "config.ini")}\"",
                UseShellExecute = true
            });
        }
        catch
        {
            // 打开文件管理器失败属非关键操作，静默忽略（不影响主流程）
        }
    }

    /// <summary>
    /// 自定义 ContextMenu 定位：默认让菜单右边缘与按钮右边缘对齐（防止在窗口右边缘被截断），
    /// 若左侧空间不足则回退到左边缘对齐。
    /// </summary>
    private CustomPopupPlacement[] PlaceContextMenuRightAligned(Size popupSize, Size targetSize, Point offset)
    {
        return new[]
        {
            new CustomPopupPlacement(
                new Point(targetSize.Width - popupSize.Width, targetSize.Height),
                PopupPrimaryAxis.Horizontal),
            new CustomPopupPlacement(
                new Point(0, targetSize.Height),
                PopupPrimaryAxis.Horizontal)
        };
    }

    private void TreeView_SelectedItemChanged(object sender, RoutedPropertyChangedEventArgs<object> e)
    {
        var node = e.NewValue as ScriptTreeItem;
        if (node == null)
            return;

        // 漂移纠正：WPF 在某些情况下会把选中回退到父目录（Group/Root）；以鼠标实际命中的项为准
        var hit = VisualTreeHelper.HitTest(ScriptTreeView, Mouse.GetPosition(ScriptTreeView));
        var hitTvi = FindParentTreeViewItem(hit?.VisualHit);
        var hitNode = hitTvi?.DataContext as ScriptTreeItem;
        if (node.Kind != ScriptTreeItem.NodeKind.Script
            && hitNode != null && hitNode.Kind == ScriptTreeItem.NodeKind.Script
            && hitTvi != null)
        {
            hitTvi.IsSelected = true;   // 重新触发 SelectedItemChanged，此次 NewValue 为脚本
            return;
        }

        // 切换前：把当前预览与日志面板的滚动位置存回旧脚本缓存（此时 _vm 内部 _currentScriptPath 仍指向旧脚本）
        _vm.SaveScrollOffset(ScriptEditor.TextArea.TextView.VerticalOffset);
        _vm.SaveLogScrollOffset(LogBox.VerticalOffset);

        _vm.SelectedNode = node;

        // 选中后：恢复新脚本缓存的滚动位置（等布局完成再设，否则被重置到顶部）
        var offset = _vm.GetScrollOffset();
        if (offset > 0)
        {
            ScriptEditor.Dispatcher.BeginInvoke(
                System.Windows.Threading.DispatcherPriority.Loaded,
                new Action(() => ScriptEditor.ScrollToVerticalOffset(offset)));
        }
    }

    private static TreeViewItem? FindParentTreeViewItem(DependencyObject? obj)
    {
        while (obj != null)
        {
            if (obj is TreeViewItem tvi) return tvi;
            obj = VisualTreeHelper.GetParent(obj);
        }
        return null;
    }

    /// <summary>
    /// TreeViewItem 选中后默认会触发 RequestBringIntoView，框架把它对齐到滚动条左边缘；
    /// 超长脚本名（如「网络详情网络详情...」）会被截掉左半，用户看不到关键信息。
    /// 此处拦截：仅做垂直方向 BringIntoView（保留自动滚到可见行的体验），水平方向置 Handled=false 交由默认行为，
    /// 然后用 ScrollViewer.HorizontalScrollBarVisibility 配合自定义偏移——但水平 RequestBringIntoView 没有现成 API，
    /// 因此改用一种"实用妥协"：把项对齐到滚动条右端，确保文件名末尾可见（用户最关心"选了哪个"）。
    /// </summary>
    private void TreeViewItem_RequestBringIntoView(object sender, RequestBringIntoViewEventArgs e)
    {
        var tvi = sender as TreeViewItem;
        if (tvi == null) return;

        // 仅处理水平滚动：垂直滚动保留框架默认行为（点击项若不在视图内仍会自动滚到该行）
        e.Handled = true;
        Dispatcher.BeginInvoke(new Action(() =>
        {
            // 找到承载该 TreeViewItem 的 ScrollViewer（树视图中 ItemPresenter 外层）
            var sv = FindAncestor<ScrollViewer>(tvi);
            if (sv == null) return;

            // 计算"把该项右边缘对齐到滚动条右端"所需的水平偏移
            var point = tvi.TransformToAncestor(sv).Transform(new Point(0, 0));
            var itemLeft = point.X;
            var itemWidth = tvi.ActualWidth;
            var viewport = sv.ViewportWidth;

            // 仅当项比视口宽或会被裁掉左半时，才向右滚
            if (itemWidth > viewport)
            {
                // 项本身就比视口宽，滚到最左（用户能从头看到结尾）
                sv.ScrollToHorizontalOffset(0);
            }
            else if (itemLeft + itemWidth > viewport)
            {
                // 项右端超出视口：把它右边缘对齐到视口右端
                sv.ScrollToHorizontalOffset(itemLeft + itemWidth - viewport);
            }
            else if (itemLeft < 0)
            {
                // 项左端被截：把它左边缘对齐到视口左端
                sv.ScrollToHorizontalOffset(itemLeft);
            }
            // 否则完全可见，不动
        }), System.Windows.Threading.DispatcherPriority.Background);
    }

    private static T? FindAncestor<T>(DependencyObject? obj) where T : DependencyObject
    {
        while (obj != null)
        {
            if (obj is T t) return t;
            obj = VisualTreeHelper.GetParent(obj);
        }
        return null;
    }

    // 顶部只读 exe 路径输入框：点击即弹出文件选择框
    private void ExePathBox_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        // 执行中禁止切换运行时文件（输入框容器已 IsEnabled=false，这里双重保险）
        if (_vm.IsRunning) return;
        _vm.PickExeCommand.Execute(null);
    }

    protected override void OnClosed(EventArgs e)
    {
        // 关闭时持久化：窗口几何状态 + 目录树展开状态，下次启动恢复
        _vm.SaveTreeState();
        ScriptManager.Cache.WindowStateCache.Save(this);
        base.OnClosed(e);
    }
}
