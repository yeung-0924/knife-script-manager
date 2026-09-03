using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using ICSharpCode.AvalonEdit.Document;
using Microsoft.Win32;
using ScriptManager;
using ScriptManager.Cache;

namespace ScriptManager.ViewModels;

/// <summary>
/// 主界面视图模型（MVVM）。保留原 Form1 的全部业务行为：
/// 单一来源脚本树（来自 config.ini 配置的脚本目录，按 children 嵌套层级）、参数动态控件、实时预览（代入后脚本）、runtime 选择、执行/管理员提权、
/// 多色日志、导出目录复制、复制/终止、窗口状态持久化。
/// UI 通过数据绑定消费本 VM，逻辑不再依赖具体控件。
/// </summary>
public class MainViewModel : ViewModelBase
{
    #region 常量与路径
    private static readonly string ExeDir = AppContext.BaseDirectory;
    private const double TopRegionHeight = 400;
    #endregion

    /// <summary>当前加载的脚本索引 json 路径：默认内置 script/index.json；通过「打开」按钮可切换为任意脚本目录。</summary>
    private string _loadedIndexPath = ConfigLoader.ScriptIndexJson;

    #region 按脚本路径缓存的运行态（参数值 + 日志）
    // 切换脚本时保留各自的填写参数与控制台日志，再次切回即恢复；进程退出字典销毁 → 重进自动清空
    private readonly Dictionary<string, ObservableCollection<ParamFieldViewModel>> _paramCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ObservableCollection<LogEntry>> _logCache = new(StringComparer.OrdinalIgnoreCase);
    // 预览内存缓存：每个脚本保留原始内容、已渲染的 Document 实例与滚动位置，切回时直接复用，不重读磁盘、不跳顶
    private readonly Dictionary<string, (string Raw, TextDocument Doc, double ScrollOffset)> _previewCache = new(StringComparer.OrdinalIgnoreCase);
    // 日志面板滚动位置缓存：切走时存、切回时恢复，避免每次重建文档都回到第一行
    private readonly Dictionary<string, double> _logScrollCache = new(StringComparer.OrdinalIgnoreCase);
    private string _currentScriptPath = ""; // 当前选中脚本的稳定路径（用于离开时存缓存）

    // 当前执行会话 id：每次点「运行」生成一次，OnLog 回调携带它，不匹配则丢弃，
    // 解决「切到别的脚本后控制台仍在刷上一个长命令日志」的串台问题。
    private Guid _runSession = Guid.Empty;
    #endregion

    #region 可绑定属性
    private ObservableCollection<ScriptTreeItem> _scriptTree = new();
    public ObservableCollection<ScriptTreeItem> ScriptTree
    {
        get => _scriptTree;
        set => SetProperty(ref _scriptTree, value);
    }

    /// <summary>当且仅当所有目录节点都处于展开状态时为真；驱动工具栏「展开/收起全部」按钮的图标与提示切换。</summary>
    private bool _allExpanded;
    public bool AllExpanded
    {
        get => _allExpanded;
        set => SetProperty(ref _allExpanded, value);
    }

    private ScriptTreeItem? _selectedNode;
    public ScriptTreeItem? SelectedNode
    {
        get => _selectedNode;
        set
        {
            if (!SetProperty(ref _selectedNode, value)) return;
            OnScriptSelected(value);
        }
    }

    private ScriptItem? _selectedScript;
    public ScriptItem? SelectedScript
    {
        get => _selectedScript;
        private set => SetProperty(ref _selectedScript, value);
    }

    private ObservableCollection<ParamFieldViewModel> _paramFields = new();
    public ObservableCollection<ParamFieldViewModel> ParamFields
    {
        get => _paramFields;
        set => SetProperty(ref _paramFields, value);
    }

    private bool _hasParameters;
    /// <summary>当前选中脚本是否含参数；false 时参数面板整块隐藏，仅脚本预览可见。</summary>
    public bool HasParameters
    {
        get => _hasParameters;
        private set => SetProperty(ref _hasParameters, value);
    }

    private bool _hasScript;
    /// <summary>是否选中了脚本；与复制/清空等按钮启用逻辑一致，无脚本时编码下拉等控件禁用。</summary>
    public bool HasScript
    {
        get => _hasScript;
        private set => SetProperty(ref _hasScript, value);
    }

    private bool _runtimeError;
    /// <summary>当前脚本语言的可执行文件无效（未配置/检测不到，或用户选了不匹配的 exe 文件）：输入框边框变红，运行按钮提前置灰。</summary>
    public bool RuntimeError
    {
        get => _runtimeError;
        private set
        {
            if (SetProperty(ref _runtimeError, value))
                CommandManager.InvalidateRequerySuggested();
        }
    }

    private bool _isRuntimeChecking;
    /// <summary>可执行文件版本校验进行中：执行按钮置灰、选择框禁用，直到校验完成。</summary>
    public bool IsRuntimeChecking
    {
        get => _isRuntimeChecking;
        private set
        {
            if (SetProperty(ref _isRuntimeChecking, value))
                CommandManager.InvalidateRequerySuggested(); // 影响 CanRun，需刷新执行按钮
        }
    }

    private string _scriptSource = "";
    public string ScriptSource
    {
        get => _scriptSource;
        private set => SetProperty(ref _scriptSource, value);
    }

    // 脚本原始内容（不含参数头）；用于与参数值拼接生成预览
    private string _rawScript = "";

    // 语法高亮编辑器文档（AvalonEdit）
    private TextDocument _scriptDocument = new();
    public TextDocument ScriptDocument
    {
        get => _scriptDocument;
        private set => SetProperty(ref _scriptDocument, value);
    }

    // 日志条目集合（多色真源，由 XAML 后台监听追加到 RichTextBox 并自动按 Level 着色）
    private ObservableCollection<LogEntry> _logs = new ObservableCollection<LogEntry>();
    public ObservableCollection<LogEntry> Logs
    {
        get => _logs;
        set
        {
            if (SetProperty(ref _logs, value))
                CommandManager.InvalidateRequerySuggested(); // 集合整体替换（切脚本/恢复缓存）后刷新复制/清空按钮可用性
        }
    }

    private string _runtimePlaceholder = "";
    /// <summary>可执行文件未配置时，input 中显示的占位提示文字。</summary>
    public string RuntimePlaceholder
    {
        get => _runtimePlaceholder;
        private set => SetProperty(ref _runtimePlaceholder, value);
    }

    /// <summary>是否展示可执行文件占位提示（SelectedExePath 为空时为真）。</summary>
    public bool ShowExePlaceholder => string.IsNullOrWhiteSpace(SelectedExePath);

    private string _selectedExePath = "";
    /// <summary>顶部只读输入框：显示当前脚本语言对应可执行文件的校验结果（自动带出 / 等待用户选择）。</summary>
    public string SelectedExePath
    {
        get => _selectedExePath;
        private set
        {
            if (SetProperty(ref _selectedExePath, value))
                OnPropertyChanged(nameof(ShowExePlaceholder));
        }
    }

    private bool _isRunning;
    public bool IsRunning
    {
        get => _isRunning;
        private set
        {
            if (!SetProperty(ref _isRunning, value)) return;
            CommandManager.InvalidateRequerySuggested();
        }
    }

    public bool CanRun =>
        SelectedScript != null
        && !IsRunning
        && !string.IsNullOrEmpty(SelectedScript.Lang)
        && !RuntimeError
        && !IsRuntimeChecking
        && !HasMissingRequired;

    private bool _hasMissingRequired;
    /// <summary>存在「必填但用户未填写」的参数：运行按钮提前置灰，输入框标红。</summary>
    public bool HasMissingRequired
    {
        get => _hasMissingRequired;
        private set
        {
            if (!SetProperty(ref _hasMissingRequired, value)) return;
            CommandManager.InvalidateRequerySuggested(); // 值变化需重算 CanRun，否则按钮状态不刷新
        }
    }

    /// <summary>当前未填写的必填参数名集合（用于状态栏/日志提示）。</summary>
    public List<string> MissingRequiredNames { get; private set; } = new();

    /// <summary>
    /// 校验必填参数：逐个刷新 ParamFieldViewModel.IsMissing，并汇总 HasMissingRequired。
    /// 在「参数值变化」「切换脚本」「参数面板重建」后调用。
    /// </summary>
    private void ValidateRequired()
    {
        var missing = new List<string>();
        foreach (var f in ParamFields)
        {
            f.IsMissing = f.Required && string.IsNullOrWhiteSpace(f.Value);
            if (f.IsMissing) missing.Add(f.Name);
        }
        MissingRequiredNames = missing;
        HasMissingRequired = missing.Count > 0;
    }

    private string _statusText = Strings.StatusReady;
    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    /// <summary>
    /// 状态栏「基础文本」：即未被临时提示覆盖时应显示的内容。
    /// 包括：未选中脚本时的「就绪」、选中后的「就绪 · 语言 版本」、校验异常时的「就绪 · 未检测到有效的可执行文件」，
    /// 以及执行过程/结果状态（正在执行 / 已停止 / 完成 / 异常）。
    /// 临时提示到期后恢复到此文本。
    /// </summary>
    private string _baseStatusText = Strings.StatusReady;

    /// <summary>执行脚本前的基础状态（如「就绪 · 语言 版本」），执行结果作为临时提示显示 5 秒后恢复到此文本。</summary>
    private string _statusBeforeRun = Strings.StatusReady;

    /// <summary>临时提示显示时长（毫秒），到点后恢复为基础文本。</summary>
    private const int StatusResetDelayMs = 5000;

    /// <summary>临时提示的自动恢复定时器（DispatcherTimer 保证在 UI 线程回调）。</summary>
    private readonly DispatcherTimer _statusResetTimer;

    /// <summary>
    /// 执行耗时刷新间隔（毫秒）。取 16ms ≈ 60fps——这是 WPF 的渲染上限（每帧约 16.7ms）。
    /// 设为 1ms 并无意义：DispatcherTimer 受消息循环限制本就无法精确触发，只会让 UI 线程被
    /// tick 塞满、CPU 飙升，而屏幕刷新率不变，用户看到的数字跳动频率完全一致。
    /// 显示精度仍到毫秒（3 位小数），视觉上就是毫秒位连续跳变。
    /// </summary>
    private const int ElapsedRefreshMs = 16;

    /// <summary>执行耗时计时器（包裹在 _runStopwatch 中，执行开始 Restart、结束 Stop）。</summary>
    private readonly Stopwatch _runStopwatch = new();

    /// <summary>执行耗时刷新定时器（DispatcherTimer → UI 线程回调，可直接更新绑定属性）。</summary>
    private readonly DispatcherTimer _elapsedTimer;

    private string _elapsedText = "";
    /// <summary>
    /// 状态栏右侧耗时文本：执行中为「已用时 mm:ss.fff」（持续跳变），结束后定格为「总用时 mm:ss.fff」。
    /// 独立显示、不并入左侧状态文字；下次执行或切换脚本时清空。
    /// </summary>
    public string ElapsedText
    {
        get => _elapsedText;
        private set
        {
            if (SetProperty(ref _elapsedText, value))
                OnPropertyChanged(nameof(HasElapsed));
        }
    }

    /// <summary>是否存在可显示的耗时文本（为空则状态栏隐藏该块）。</summary>
    public bool HasElapsed => _elapsedText.Length > 0;

    /// <summary>
    /// 耗时格式化。
    /// ⚠️ 不能直接用 <c>@"mm\:ss\.fff"</c>：TimeSpan 自定义格式里的 mm 只取「分钟部分」(0-59)，
    /// 70 分钟会显示成 <c>10:00.000</c> —— 小时被<b>静默丢弃</b>，看着像只跑了 10 分钟。
    /// 故满 1 小时起改用「总小时:分:秒.毫秒」；总小时按 TotalHours 取整、不做 24 取模，
    /// 避免跨天（如 25 小时）同样被截断成 01。
    /// 各段均补零到固定宽度，避免数字位数变化导致状态栏文本抖动。
    /// </summary>
    private static string FormatElapsed(TimeSpan value)
    {
        var frac = value.Milliseconds.ToString("000", CultureInfo.InvariantCulture);
        return value.TotalHours >= 1
            ? string.Format(CultureInfo.InvariantCulture, "{0:00}:{1:00}:{2:00}.{3}",
                (int)value.TotalHours, value.Minutes, value.Seconds, frac)
            : string.Format(CultureInfo.InvariantCulture, "{0:00}:{1:00}.{2}",
                value.Minutes, value.Seconds, frac);
    }

    /// <summary>按当前 Stopwatch 读数刷新耗时文本（执行中，前缀「已用时」）。</summary>
    private void UpdateElapsedText()
        => ElapsedText = string.Format(Strings.StatusElapsedFormat, FormatElapsed(_runStopwatch.Elapsed));

    /// <summary>
    /// 停止计时并把耗时文本定格为「总用时」（不再跳变）。计时器与 Stopwatch 均可安全重复 Stop。
    /// </summary>
    private void StopAndShowTotalElapsed()
    {
        _elapsedTimer.Stop();
        _runStopwatch.Stop();
        ElapsedText = string.Format(Strings.StatusTotalElapsedFormat, FormatElapsed(_runStopwatch.Elapsed));
    }

    /// <summary>
    /// 清空耗时显示（切换脚本 / 刷新列表时）。执行进行中则不清除，避免打断正在跳动的计时。
    /// </summary>
    private void ClearElapsed()
    {
        if (IsRunning) return;
        ElapsedText = "";
    }

    /// <summary>
    /// 设置基础状态文本并立即显示。用于所有非临时提示的状态更新。
    /// 会停止已挂起的恢复定时器——因为基础状态已改变，旧的临时提示再恢复已无意义（且会显示过期的旧状态）。
    /// </summary>
    private void SetBaseStatus(string message)
    {
        _statusResetTimer.Stop();
        _baseStatusText = message;
        StatusText = message;
    }

    /// <summary>
    /// 显示一条临时提示（如「已复制」「已清空」），StatusResetDelayMs 后自动恢复为当前基础文本。
    /// 连续调用只重置计时，不会叠加多个定时器。
    /// </summary>
    private void ShowTemporaryStatus(string message)
    {
        StatusText = message;
        _statusResetTimer.Stop();
        _statusResetTimer.Start();
    }

    private string _versionText = "v " + Strings.Version;
    public string VersionText
    {
        get => _versionText;
        private set => SetProperty(ref _versionText, value);
    }

    #endregion

    #region 命令
    public RelayCommand RunCommand { get; }
    public RelayCommand ExportCommand { get; }
    public RelayCommand PickRuntimeCommand { get; }
    public RelayCommand PickExeCommand { get; }
    public RelayCommand AutoRuntimeCommand { get; }
    public RelayCommand CopyCommand { get; }
    public RelayCommand ExportPreviewCommand { get; }
    public RelayCommand StopCommand { get; }
    public RelayCommand ResetParamsCommand { get; }
    public RelayCommand ClearLogCommand { get; }
    public RelayCommand CopyLogCommand { get; }
    public RelayCommand ToggleExpandAllCommand { get; }
    public RelayCommand OpenFolderCommand { get; }
    #endregion

    public MainViewModel()
    {
        // 临时提示到期后自动恢复为基础状态文本
        _statusResetTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(StatusResetDelayMs) };
        _statusResetTimer.Tick += (_, _) =>
        {
            _statusResetTimer.Stop();
            StatusText = _statusBeforeRun;
        };

        // 执行期间按固定间隔刷新耗时显示
        _elapsedTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(ElapsedRefreshMs) };
        _elapsedTimer.Tick += (_, _) => UpdateElapsedText();

        RuntimeConfig.EnsureAutoDetected();
        // 启动优先加载「打开」持久化的脚本目录；若该目录已失效（无 index.json）则回退到默认内置 script 目录
        LoadTreeFromIndex(ResolveStartupIndex());
        RefreshRuntimeStatus();

        RunCommand = new RelayCommand(_ => ExecuteRun(false), _ => CanRun);
        ExportCommand = new RelayCommand(_ => DoExport(), _ => Directory.Exists(ConfigLoader.ScriptDir));
        PickRuntimeCommand = new RelayCommand(_ => PickRuntime());
        PickExeCommand = new RelayCommand(_ => PickExe());
        AutoRuntimeCommand = new RelayCommand(_ => AutoRuntime(), _ => SelectedScript != null && !IsRuntimeChecking);
        CopyCommand = new RelayCommand(_ => CopyPreview(), _ => SelectedScript != null);
        ExportPreviewCommand = new RelayCommand(_ => ExportPreview(), _ => SelectedScript != null);
        StopCommand = new RelayCommand(_ => StopRunning(), _ => IsRunning);
        CopyLogCommand = new RelayCommand(_ => CopyLog(), _ => SelectedScript != null && Logs.Count > 0);
        ResetParamsCommand = new RelayCommand(_ => ResetParams(), _ => SelectedScript != null);
        ClearLogCommand = new RelayCommand(_ => ClearLog(), _ => SelectedScript != null && Logs.Count > 0);
        ToggleExpandAllCommand = new RelayCommand(_ => ToggleExpandAll());
        OpenFolderCommand = new RelayCommand(_ => OpenScriptFile(), _ => !IsRunning);
    }

    private void CopyLog()
    {
        // 复制当前日志区全部文本到剪贴板（与脚本预览复制反馈一致，不弹 MessageBox）。
        var text = string.Join("\n", Logs.Select(e => e.Text));
        if (string.IsNullOrEmpty(text))
        {
            ShowTemporaryStatus(Strings.StatusCopyEmpty);
            return;
        }
        try
        {
            Clipboard.SetText(text);
            ShowTemporaryStatus(Strings.StatusLogCopied);
        }
        catch (Exception ex)
        {
            ShowTemporaryStatus(string.Format(Strings.StatusCopyFailFormat, ex.Message));
        }
    }

    private void ClearLog()
    {
        ClearLogSilently();
        ShowTemporaryStatus(Strings.StatusLogCleared);
    }

    /// <summary>
    /// 只清空日志区，不显示「日志已清除」状态提示。
    /// 供执行前的自动清空使用——其后紧接本次执行的输出，再弹提示会一闪而过且无意义；
    /// 手动点「清除日志」按钮则用 <see cref="ClearLog"/>，需要该提示作为操作反馈。
    /// </summary>
    private void ClearLogSilently()
    {
        Logs.Clear();
        CommandManager.InvalidateRequerySuggested(); // 日志已清空，刷新复制/清空按钮可用性
    }

    #region 树构建
    // 刷新时保留各节点的展开/折叠状态（按稳定 Path 匹配）
    // 展开状态持久化到 cache/tree-state.json（见 TreeStateCache），不再存内存字典，故重启后仍可恢复

    /// <summary>
    /// 解析启动时应加载的索引 json：优先用 config.ini 持久化的「打开」文件（[script] user_script_file），
    /// 仅当该文件确实存在时才采用；否则回退到默认 default_script_file，保证重启后总有可用脚本树。
    /// </summary>
    private static string ResolveStartupIndex()
    {
        var userIdx = AppConfig.UserScriptFilePath;
        if (!string.IsNullOrEmpty(userIdx) && File.Exists(userIdx))
            return userIdx;
        return ConfigLoader.ScriptIndexJson;
    }

    /// <summary>
    /// 「打开」按钮：弹出文件选择框，直接选择脚本索引文件 index.json（结构同内置 script 目录的 index.json）。
    /// 选中非有效脚本索引（解析为空）时，目录树渲染为空（符合「渲染不出来即可」的预期，不弹窗报错），且不记忆该选择。
    /// </summary>
    private void OpenScriptFile()
    {
        // 初始定位到当前已加载索引所在目录，连续打开同类文件更顺手
        var dlg = new OpenFileDialog
        {
            Title = Strings.DlgOpenScriptFileTitle,
            Filter = "脚本索引 (index.json)|index.json|JSON 文件 (*.json)|*.json|所有文件 (*.*)|*.*",
            CheckFileExists = true
        };
        if (!string.IsNullOrWhiteSpace(_loadedIndexPath) && File.Exists(_loadedIndexPath))
            dlg.InitialDirectory = Path.GetDirectoryName(_loadedIndexPath);

        if (dlg.ShowDialog() != true) return; // 用户取消

        var indexPath = dlg.FileName;
        // 先校验是否为有效脚本索引（解析出节点）再决定是否记忆，避免把随机 json 记住导致重启后空树
        var items = ConfigLoader.LoadIndex(indexPath);
        LoadTreeFromIndex(indexPath);
        if (items.Count > 0)
        {
            // 持久化到 config.ini 的 [script] user_script_file，使重启后仍自动加载该索引文件
            AppConfig.SetUserScriptFilePath(indexPath);
            ShowTemporaryStatus(Strings.StatusOpenScriptFileDone);
        }
        else
        {
            ShowTemporaryStatus(Strings.StatusOpenScriptFileInvalid);
        }
    }

    /// <summary>
    /// 从指定索引 json 重建脚本目录树（不写展开状态缓存——跨目录的恢复无意义）。
    /// 索引文件不存在时 <see cref="BuildTreeFromIndex"/> 返回空集合，目录树保持不渲染。
    /// </summary>
    private void LoadTreeFromIndex(string indexPath)
    {
        _loadedIndexPath = indexPath;
        // 切换目录前重置当前选中（参数/日志/预览缓存各自按原路径保留，互不影响）
        OnScriptSelected(null);
        var roots = new ObservableCollection<ScriptTreeItem>();
        BuildTreeFromIndex(roots, indexPath);
        ScriptTree = roots;
        RestoreExpandedState(ScriptTree);
        WireTreeNotifications();
        RecalcAllExpanded();
    }

    /// <summary>把当前展开（非叶子）节点的稳定 Path 集合写入缓存（cache/tree-state.json）。</summary>
    private void SaveExpandedState(IEnumerable<ScriptTreeItem>? nodes)
    {
        var expanded = new HashSet<string>();
        CollectExpanded(nodes, expanded);
        TreeStateCache.Save(expanded);
    }

    private static void CollectExpanded(IEnumerable<ScriptTreeItem>? nodes, HashSet<string> acc)
    {
        if (nodes == null) return;
        foreach (var n in nodes)
        {
            if (!string.IsNullOrEmpty(n.Path) && n.Kind != ScriptTreeItem.NodeKind.Script && n.IsExpanded)
                acc.Add(n.Path);
            CollectExpanded(n.Children, acc);
        }
    }

    /// <summary>从缓存恢复展开状态。无缓存（首次）则全部收起。</summary>
    private void RestoreExpandedState(IEnumerable<ScriptTreeItem>? nodes)
    {
        var expanded = TreeStateCache.LoadExpanded();
        ApplyExpanded(nodes, expanded);
    }

    private static void ApplyExpanded(IEnumerable<ScriptTreeItem>? nodes, HashSet<string>? expanded)
    {
        if (nodes == null) return;
        foreach (var n in nodes)
        {
            if (!string.IsNullOrEmpty(n.Path) && n.Kind != ScriptTreeItem.NodeKind.Script)
            {
                // 无缓存（首次）：全部收起；有缓存：仅在集合内的节点展开
                n.IsExpanded = expanded != null && expanded.Contains(n.Path);
            }
            ApplyExpanded(n.Children, expanded);
        }
    }

    // 已订阅 PropertyChanged 的树节点，用于重建树时退订，避免泄漏
    private readonly List<ScriptTreeItem> _wiredNodes = new();

    /// <summary>遍历当前树全部节点，订阅 IsExpanded 变化，使手动展开/收起时按钮图标能实时切换。</summary>
    private void WireTreeNotifications()
    {
        foreach (var old in _wiredNodes)
            old.PropertyChanged -= OnTreeNodePropertyChanged;
        _wiredNodes.Clear();

        WalkNodes(ScriptTree, n =>
        {
            if (!string.IsNullOrEmpty(n.Path) && n.Kind != ScriptTreeItem.NodeKind.Script)
            {
                n.PropertyChanged += OnTreeNodePropertyChanged;
                _wiredNodes.Add(n);
            }
        });
    }

    private void OnTreeNodePropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ScriptTreeItem.IsExpanded) && sender is ScriptTreeItem node
            && !string.IsNullOrEmpty(node.Path) && node.Kind != ScriptTreeItem.NodeKind.Script)
        {
            RecalcAllExpanded();
        }
    }

    /// <summary>重算 AllExpanded：所有目录节点均展开时为真。</summary>
    private void RecalcAllExpanded()
    {
        var all = true;
        WalkNodes(ScriptTree, n =>
        {
            if (all && !string.IsNullOrEmpty(n.Path) && n.Kind != ScriptTreeItem.NodeKind.Script && !n.IsExpanded)
                all = false;
        });
        AllExpanded = all;
    }

    /// <summary>展开/收起全部目录：当前全展开则收起，否则展开。</summary>
    private void ToggleExpandAll()
    {
        var expand = !AllExpanded;
        WalkNodes(ScriptTree, n =>
        {
            if (!string.IsNullOrEmpty(n.Path) && n.Kind != ScriptTreeItem.NodeKind.Script)
                n.IsExpanded = expand;
        });
        AllExpanded = expand;
    }

    private static void WalkNodes(IEnumerable<ScriptTreeItem>? nodes, Action<ScriptTreeItem> visit)
    {
        if (nodes == null) return;
        foreach (var n in nodes)
        {
            visit(n);
            WalkNodes(n.Children, visit);
        }
    }

    /// <summary>关闭程序时显式持久化当前展开状态，确保重启后恢复。</summary>
    public void SaveTreeState() => SaveExpandedState(ScriptTree);

    /// <summary>按索引 json 的嵌套结构（children）构建目录树，不再依赖 group 字段。</summary>
    private void BuildTreeFromIndex(ObservableCollection<ScriptTreeItem> roots, string indexPath)
    {
        if (!File.Exists(indexPath))
            return;
        // 索引为嵌套结构：目录节点（name + children）与脚本节点（name + path）按 children 递归还原层级
        var items = ConfigLoader.LoadIndex(indexPath);
        BuildNodes(roots, items, "");
    }

    /// <summary>
    /// 递归把 ScriptItem 节点转成 ScriptTreeItem 树节点。
    /// parentPath 用于拼出稳定路径标识（如 "网络/防火墙/启用防火墙"），供跨刷新恢复展开状态。
    /// </summary>
    private static void BuildNodes(ObservableCollection<ScriptTreeItem> target, List<ScriptItem> items, string parentPath)
    {
        foreach (var it in items)
        {
            var path = parentPath.Length == 0 ? it.Name : parentPath + "/" + it.Name;

            if (it.IsGroup)
            {
                var groupNode = new ScriptTreeItem(ScriptTreeItem.NodeKind.Group, it.Name, path: path);
                target.Add(groupNode);
                BuildNodes(groupNode.Children, it.Children!, path);
            }
            else
            {
                target.Add(new ScriptTreeItem(ScriptTreeItem.NodeKind.Script, it.Name, it, path: path));
            }
        }
    }
    #endregion

    #region 选中脚本
    private void OnScriptSelected(ScriptTreeItem? node)
    {
        // 切换脚本即作废当前执行会话：旧进程若仍在输出，其 OnLog 会因 session 不匹配被丢弃，
        // 不会串入新脚本控制台（旧日志仍保留在 _logCache 中，切回原脚本可恢复）。
        _runSession = Guid.Empty;
        // 耗时属于上一个脚本，切换后清掉（执行中则保留，不打断正在跳动的计时）
        ClearElapsed();
        // 离开上一个脚本时：把当前参数值 + 日志存入缓存（按稳定路径），再次切回即恢复
        if (!string.IsNullOrEmpty(_currentScriptPath) && _selectedScript != null)
        {
            _paramCache[_currentScriptPath] = ParamFields;
            _logCache[_currentScriptPath] = new ObservableCollection<LogEntry>(Logs);
        }
        // 离开旧脚本前，由 View 把当前预览滚动位置写回缓存（通过 SaveScrollOffset）
        _currentScriptPath = node?.Path ?? "";

        if (node?.Kind != ScriptTreeItem.NodeKind.Script || node.Item == null)
        {
            SelectedScript = null;
            HasScript = false;
            SelectedExePath = "";
            RuntimeError = false;
            RuntimePlaceholder = "";
            SetBaseStatus(Strings.StatusReady);
            ParamFields = new ObservableCollection<ParamFieldViewModel>();
            HasParameters = false;
            HasMissingRequired = false;
            MissingRequiredNames = new List<string>();
            _rawScript = "";
            Logs = new ObservableCollection<LogEntry>();
            RenderPreview();
            return;
        }
        var script = node.Item;
        var path = node.Path;
        SelectedScript = script;
        HasScript = true;

        // 参数面板：优先复用缓存（保留填写值），首次进入才新建
        if (_paramCache.TryGetValue(path, out var cachedFields))
        {
            ParamFields = cachedFields;
        }
        else
        {
            var fields = new ObservableCollection<ParamFieldViewModel>();
            if (script.Params != null)
                foreach (var p in script.Params)
                {
                    var f = new ParamFieldViewModel(p);
                    // 文件/目录选择型参数：注入浏览委托，由 ViewModel 弹出对应对话框，把路径写回 Value
                    f.PickPath = field =>
                    {
                        if (field.IsFolder)
                        {
                            return Utils.FolderPicker.PickFolder(
                                string.Format(Strings.DlgPickFolderTitle, field.Name),
                                field.Value);
                        }
                        var ofd = new OpenFileDialog
                        {
                            Title = string.Format(Strings.DlgPickFileTitle, field.Name),
                            Filter = Strings.DlgPickFileFilter,
                            CheckFileExists = true
                        };
                        if (!string.IsNullOrWhiteSpace(field.Value) && File.Exists(field.Value))
                            ofd.InitialDirectory = Path.GetDirectoryName(field.Value);
                        var ok = ofd.ShowDialog();
                        return ok == true ? ofd.FileName : null;
                    };
                    // 参数值变化 → 重新渲染脚本预览 + 重新校验必填（填了才解除禁用）。
                    // keepScrollPosition=true：保留用户当前的预览滚动位置，不被拉回顶部
                    f.PropertyChanged += (_, e) =>
                    {
                        if (e.PropertyName != nameof(ParamFieldViewModel.Value)) return;
                        RenderPreview(keepScrollPosition: true);
                        ValidateRequired();
                    };
                    fields.Add(f);
                }
            _paramCache[path] = fields;
            ParamFields = fields;
        }
        HasParameters = ParamFields.Count > 0;
        ValidateRequired(); // 必填项初始状态（有 default 的已预填，不算缺失）

        // 日志：优先恢复缓存，首次进入才清空
        if (_logCache.TryGetValue(path, out var cachedLog))
        {
            Logs = new ObservableCollection<LogEntry>(cachedLog);
        }
        else
        {
            Logs = new ObservableCollection<LogEntry>();
        }

        // 实时预览：优先复用内存缓存（保留之前渲染的 Document 实例与滚动位置），首次进入才读磁盘
        if (_previewCache.TryGetValue(path, out var cachedPreview))
        {
            _rawScript = cachedPreview.Raw;
            ScriptDocument = cachedPreview.Doc;
        }
        else
        {
            try
            {
                _rawScript = File.Exists(script.ResolvedPath) ? File.ReadAllText(script.ResolvedPath) : string.Format(Strings.ScriptFileMissingFormat, script.ResolvedPath);
            }
            catch (Exception ex)
            {
                _rawScript = string.Format(Strings.ScriptReadFailFormat, ex.Message);
            }
            RenderPreview();
            _previewCache[path] = (_rawScript, ScriptDocument, 0);
        }
        // 按当前脚本语言校验/带出可执行文件（PATH 内能找到就默认带出，否则提示用户点击选择）
        RefreshRuntimeStatus();
    }

    /// <summary>View 在切换脚本前调用：把当前预览滚动位置存回该脚本的内存缓存（切回时恢复，不跳顶）。</summary>
    public void SaveScrollOffset(double offset)
    {
        if (string.IsNullOrEmpty(_currentScriptPath)) return;
        if (_previewCache.TryGetValue(_currentScriptPath, out var c))
            _previewCache[_currentScriptPath] = (c.Raw, c.Doc, offset);
    }

    /// <summary>获取当前脚本缓存的预览滚动位置（View 在选中后恢复用）。</summary>
    public double GetScrollOffset() => _previewCache.TryGetValue(_currentScriptPath, out var c) ? c.ScrollOffset : 0;

    /// <summary>View 在切换脚本前调用：把当前日志面板滚动位置存回该脚本缓存。</summary>
    public void SaveLogScrollOffset(double offset)
    {
        if (string.IsNullOrEmpty(_currentScriptPath)) return;
        _logScrollCache[_currentScriptPath] = offset;
    }

    /// <summary>获取当前脚本缓存的日志面板滚动位置（View 在重建文档后恢复用）。</summary>
    public double GetLogScrollOffset() => _logScrollCache.TryGetValue(_currentScriptPath, out var o) ? o : 0;



    /// <summary>
    /// 生成「代入后」的脚本：按约定把源码中的占位符 _p{参数名} 替换为用户输入值。
    /// 约定：脚本内用 _p{NAME} 表示名为 NAME 的参数（与 index.json 的 params[].name 对应，
    /// 大小写敏感），所有语言统一适用（不再依赖各语言自己的参数解析）。源文件始终不被修改，
    /// 仅用于预览/运行/复制（所见即所得）。
    /// <para>
    /// 命名规范建议 UPPER_SNAKE_CASE（如 <c>SVG_PATH</c>），但**不做强制校验**——
    /// 匹配方式是「按 params[].name 字面精确匹配 _p{...} 内的名字」，
    /// 故任何命名（含小写、驼峰等）只要写在 _p{} 内且与 params[].name 字面一致，均可正常代入。
    /// </para>
    /// </summary>
    /// <param name="source">要代入的源脚本；省略则用当前加载的 _rawScript。</param>
    /// <param name="lang">脚本语言（来自 index.json 的 lang）。用于把参数值转义为
    /// 可安全嵌入源码字符串字面量的形式，避免 Windows 路径反斜杠（如 C:\Users…）被脚本语言
    /// 当作转义序列解析（典型如 Python 的 unicodeescape 报错）。</param>
    private string BuildParameterizedScript(string? source = null, string? lang = null)
    {
        var raw = source ?? _rawScript;
        if (ParamFields.Count == 0 || raw.StartsWith("(脚本"))
            return raw;

        var text = raw;
        foreach (var f in ParamFields)
        {
            var name = f.Param.Name;
            if (string.IsNullOrEmpty(name)) continue;
            // 值为空也参与替换（用户可能就是想填空，预览里以"空"显示，不再保留占位符原文）
            var val = f.Value ?? f.Param.Default ?? "";

            // 占位符通常写在源码字符串字面量内，需按语言转义，否则反斜杠/引号会破坏语法。
            var escaped = EscapeForLiteral(val, lang);
            // 占位符 _p{NAME}：先转义替换值中的 $（Regex 替换字符串里 $ 是特殊字符）
            var replacement = escaped.Replace("$", "$$");
            // 宽容匹配：只要求是 _p{...} 形式且内部名字与 params[].name 字面一致，
            // 不校验命名风格（UPPER_SNAKE_CASE 仅为规范建议）。允许 _p{ NAME } 含空格。
            var pattern = @"_p\{\s*" + Regex.Escape(name) + @"\s*\}";
            // 大小写敏感：参数名必须与脚本内占位符字面完全一致，
            // _p{name} 不会匹配 params[].name = "NAME"。
            text = Regex.Replace(text, pattern, replacement, RegexOptions.None);
        }
        return text;
    }

    /// <summary>
    /// 把参数值转义为「可安全嵌入源码字符串字面量」的形式。
    /// 脚本作者把 _p{NAME} 写在字符串字面量里时（如 Python 的 default="_p{SVG_PATH}"），
    /// 用户的 Windows 路径含反斜杠（C:\Users\…），若不转义会被当成转义序列。
    /// 按语言分别处理最危险的字符（反斜杠、引号、反引号）。
    /// </summary>
    private static string EscapeForLiteral(string value, string? lang)
    {
        if (string.IsNullOrEmpty(value)) return value;
        lang = (lang ?? "").ToLowerInvariant();
        switch (lang)
        {
            case ScriptLangs.Python:
                // Python 双引号字符串：反斜杠与双引号必须转义；其余控制字符转义为 \n 等
                var sb = new StringBuilder(value.Length + 16);
                foreach (var c in value)
                {
                    switch (c)
                    {
                        case '\\': sb.Append("\\\\"); break;
                        case '"': sb.Append("\\\""); break;
                        case '\n': sb.Append("\\n"); break;
                        case '\r': sb.Append("\\r"); break;
                        case '\t': sb.Append("\\t"); break;
                        default: sb.Append(c); break;
                    }
                }
                return sb.ToString();

            case ScriptLangs.PowerShell:
                // PowerShell 双引号字符串：反引号 ` 为转义符，需转义它自身与双引号；
                // 反斜杠无需转义（PS 不把 \ 当转义）。
                return value
                    .Replace("`", "``")
                    .Replace("\"", "`\"");

            default:
                // 通用兜底：至少转义反斜杠与双引号，覆盖 cmd/java/bash/node 等多数情况。
                return value
                    .Replace("\\", "\\\\")
                    .Replace("\"", "\\\"");
        }
    }

    // 重新渲染脚本预览（代入后的完整脚本）
    // keepScrollPosition=false（默认）：重建 Document → AvalonEdit 视图重置、回到顶部。
    //   用于「切换脚本 / 清空」，此时保留上一脚本的滚动位置没有意义。
    // keepScrollPosition=true：原地 Replace 全文 → 保留滚动位置与光标位置。
    //   用于「改参数后重新代入」，用户正在查看脚本某处时不应被拉回顶部。
    private void RenderPreview(bool keepScrollPosition = false)
    {
        var text = BuildParameterizedScript(lang: SelectedScript?.Lang);
        ScriptSource = text;

        if (!keepScrollPosition)
        {
            ScriptDocument = new TextDocument(new StringTextSource(text));
            return;
        }

        // 内容未变化则不动，避免无谓重绘与撤销栈污染
        if (string.Equals(ScriptDocument.Text, text, StringComparison.Ordinal))
            return;

        ScriptDocument.Replace(0, ScriptDocument.TextLength, text);
        // 参数变化刷新了 Document 内容，同步更新缓存里的实例引用（保持同一实例，滚动位置得以保留）
        if (!string.IsNullOrEmpty(_currentScriptPath))
            _previewCache[_currentScriptPath] = (_rawScript, ScriptDocument, GetScrollOffset());
    }
    #endregion

    #region 执行
    private async void ExecuteRun(bool _)
    {
        if (SelectedScript == null) return;

        // 执行前同步注册表环境变量到当前进程：安装脚本（如 JDK）可能刚更新过 PATH，
        // 子进程默认继承本进程环境快照，不刷新会导致脚本里 java 等命令仍用旧版本
        EnvironmentSync.RefreshProcessEnvironment();
        RuntimeProbe.ClearCache();

        // 必填校验（防御）：运行按钮虽已置灰，此处仍兜底，避免任何绕过路径带着空值执行
        ValidateRequired();
        if (HasMissingRequired)
        {
            var names = string.Join("、", MissingRequiredNames);
            OnLog(Guid.Empty, LogEntry.Level.Error, string.Format(Strings.LogRequiredMissingFormat, names));
            ShowTemporaryStatus(string.Format(Strings.StatusRequiredMissingFormat, names));
            return;
        }

        var script = SelectedScript;
        var workingDir = Path.GetDirectoryName(script.ResolvedPath) ?? ExeDir;

        // 执行前清空上一轮日志，避免同一脚本多次执行的输出累积混在一起。
        // ⚠️ 位置必须在必填校验【之后】：校验失败时用户并未真正执行，
        //    保留原有日志并追加错误信息，比先清空更有诊断价值。
        ClearLogSilently();

        // 执行前把源文件内容重新写出为临时文件再运行（源文件从不修改）。
        // 读源文件用其实际编码（探测 BOM/无 BOM），否则 GBK 中文会按 UTF-8 误读；
        // 写出编码按语言固定：
        //   - PowerShell：Windows PowerShell 5.1 读取无 BOM 的 .ps1 时按系统 ANSI 代码页解码，中文会乱码，
        //     故临时文件强制 UTF-8 带 BOM（PowerShell 7 亦兼容）；源文件保持 UTF-8 无 BOM 不变。
        //   - Java：单文件源码启动（java x.java）不支持源文件带 BOM（会报「非法字符 \ufeff」），强制无 BOM，
        //     内容正确性由 JDK_JAVA_OPTIONS 的 -Dfile.encoding=UTF-8 保证。
        //   - 其余语言：UTF-8 无 BOM（与源文件一致）。
        // 临时文件扩展名按语言映射（如 powershell→ps1、java→java、python→py），保证运行时识别正确。
        var ext = LangToTempExt(script.Lang);
        var tempScript = Path.Combine(Path.GetTempPath(), $"se_script_{Guid.NewGuid():N}.{ext}");
        var srcText = File.ReadAllText(script.ResolvedPath, EncodingHelper.DetectFromFile(script.ResolvedPath));
        if (ParamFields.Count > 0)
            srcText = BuildParameterizedScript(srcText, script.Lang); // 占位符替换（在已正确解码的文本上操作）

        // cmd/bat 专用：把中文等非 ASCII 片段抽成 %SM_TXT_nnn% 占位符，让脚本在字节层面降为 ASCII，
        // 规避 cmd 按控制台代码页解码 bat 造成的中文乱码；中文真值改由进程环境块（UTF-16）注入，无损。
        // 必须排在参数代入之后——用户填的中文参数值同样需要被抽走。
        IReadOnlyDictionary<string, string>? injectedVars = null;
        if (string.Equals(script.Lang, ScriptLangs.Cmd, StringComparison.OrdinalIgnoreCase))
        {
            var rewritten = CmdScriptRewriter.Rewrite(srcText);
            srcText = rewritten.Content;
            injectedVars = rewritten.Variables;
        }

        // PowerShell 强制 UTF-8 带 BOM（见上方注释）；Java 与其余语言 UTF-8 无 BOM。
        var writeEncoding = IsPowerShellLang(script.Lang)
            ? new UTF8Encoding(true)
            : new UTF8Encoding(false);
        File.WriteAllText(tempScript, srcText, writeEncoding);
        string scriptOverride = tempScript;

        // Rust 是编译型语言：需在运行前用 rustc 把临时 .rs 预编译为临时 .exe。
        // 编译失败（语法错误等）直接报错并中止，不进入执行阶段。
        if (string.Equals(script.Lang, ScriptLangs.Rust, StringComparison.OrdinalIgnoreCase))
        {
            var rustc = RuntimeConfig.Get(ScriptLangs.Rust);
            if (string.IsNullOrWhiteSpace(rustc) || !File.Exists(rustc))
            {
                OnLog(Guid.Empty, LogEntry.Level.Error, string.Format(Strings.LogRuntimeUnresolvedFormat, ScriptLangs.Rust));
                IsRunning = false;
                return;
            }
            var tempExe = Path.ChangeExtension(tempScript, ".exe");
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = rustc,
                    Arguments = $"\"{tempScript}\" -O -o \"{tempExe}\"",
                    WorkingDirectory = workingDir,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                };
                using var proc = Process.Start(psi);
                if (proc == null)
                {
                    OnLog(Guid.Empty, LogEntry.Level.Error, string.Format(Strings.LogExecExceptionFormat, "无法启动 rustc"));
                    IsRunning = false;
                    return;
                }
                var compileErr = proc.StandardError.ReadToEnd();
                proc.WaitForExit();
                if (proc.ExitCode != 0 || !File.Exists(tempExe))
                {
                    OnLog(Guid.Empty, LogEntry.Level.Error, $"Rust 编译失败（rustc 退出码 {proc.ExitCode}）：");
                    foreach (var line in compileErr.Split('\n'))
                        if (!string.IsNullOrWhiteSpace(line)) OnLog(Guid.Empty, LogEntry.Level.Error, line.Trim());
                    IsRunning = false;
                    return;
                }
                scriptOverride = tempExe; // 执行编译产物，而非源文件
            }
            catch (Exception ex)
            {
                OnLog(Guid.Empty, LogEntry.Level.Error, string.Format(Strings.LogExecExceptionFormat, ex.Message));
                IsRunning = false;
                return;
            }
        }

        IsRunning = true;
        _stopRequested = false;
        // 本次执行会话 id：用于隔离「切换脚本后旧进程仍在输出」的日志串台问题。
        // OnLog 回调会携带此 id，只有与当前会话匹配才写入 UI/文件。
        _runSession = Guid.NewGuid();
        // 计算本次运行的日志文件路径：exe同级 log/yyyy-MM-dd/脚本名_yyyyMMddHHmmss.log
        try
        {
            var logDir = Path.Combine(ExeDir, "log", DateTime.Now.ToString("yyyy-MM-dd"));
            Directory.CreateDirectory(logDir);
            var baseName = Path.GetFileNameWithoutExtension(script.ResolvedPath);
            _currentLogFile = Path.Combine(logDir, $"{baseName}_{DateTime.Now:yyyyMMddHHmmss}.log");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] 创建日志文件失败：{ex.Message}");
            _currentLogFile = null;
        }
        _statusBeforeRun = _baseStatusText; // 记住执行前基准（如「就绪 · 语言 版本」），供结果提示到期后恢复
        SetBaseStatus(string.Format(Strings.StatusRunningFormat, script.Name));
        // 起表并立刻显示首帧耗时（不必等第一次 tick，避免状态栏出现一瞬间的空白）
        _runStopwatch.Restart();
        UpdateElapsedText();
        _elapsedTimer.Start();
        try
        {
            // 放到后台线程执行，避免 proc.WaitForExit 阻塞 UI 线程导致界面卡死
            var session = _runSession;
            // 有效超时：单脚本 timeout 优先，回退全局 default_timeout（0/负=不限制）
            var timeout = script.Timeout ?? AppConfig.DefaultTimeoutSeconds;
            OnLog(session, LogEntry.Level.Exit, script.Admin ? Strings.LogProcessStartAdminFormat : Strings.LogProcessStartFormat);
            var result = await Task.Run(() => ScriptRunner.Run(script, "", workingDir, script.Admin, (lv, tx) => OnLog(session, lv, tx), scriptOverride, injectedVars, timeout));
            // 耗时定格为「总用时」，与执行中同样的位置与样式继续显示
            StopAndShowTotalElapsed();
            if (_stopRequested)
            {
                ShowTemporaryStatus(string.Format(Strings.StatusStoppedFormat, script.Name));
                _stopRequested = false;
            }
            else if (result.TimedOut)
                ShowTemporaryStatus(string.Format(Strings.StatusTimeoutFormat, script.Name));
            else if (result.ExitCode == 0)
                ShowTemporaryStatus(string.Format(Strings.StatusCompletedFormat, script.Name));
            else
                ShowTemporaryStatus(string.Format(Strings.StatusExitedFormat, script.Name, result.ExitCode));
        }
        catch (Exception ex)
        {
            StopAndShowTotalElapsed();
            ShowTemporaryStatus(string.Format(Strings.StatusExceptionFormat, ex.Message));
        }
        finally
        {
            // 停表：耗时随 IsRunning=false 一并从状态栏隐藏
            _elapsedTimer.Stop();
            _runStopwatch.Stop();
            IsRunning = false;
            _currentLogFile = null;
            if (tempScript != null)
            {
                try { File.Delete(tempScript); } catch { }
            }
        }
    }

    /// <summary>
    /// <summary>
    /// 按语言返回临时文件的扩展名，保证运行时能正确识别脚本（如 java→java、python→py）。
    /// 未登记的语言回退到原脚本扩展名。
    /// </summary>
    private static string LangToTempExt(string lang)
    {
        return lang.Trim().ToLowerInvariant() switch
        {
            ScriptLangs.PowerShell => "ps1",
            ScriptLangs.Cmd => "bat",
            ScriptLangs.Bash => "sh",
            ScriptLangs.Java => "java",
            ScriptLangs.Python => "py",
            ScriptLangs.Node => "js",
            ScriptLangs.Go => "go",
            ScriptLangs.Rust => "rs",
            ScriptLangs.Pwsh => "ps1",
            _ => "tmp"
        };
    }

    /// <summary>
    /// 判断 lang 是否属于 PowerShell 系（Windows PowerShell 5.1 与 PowerShell 7/pwsh）。
    /// 二者共用一套写出约定：临时文件强制 UTF-8 带 BOM。
    /// PS7 自身按 UTF-8 解码无 BOM 的 .ps1 已正确，但带 BOM 同样兼容且更保险，故与 5.1 保持一致。
    /// </summary>
    private static bool IsPowerShellLang(string? lang) =>
        string.Equals(lang, ScriptLangs.PowerShell, StringComparison.OrdinalIgnoreCase) ||
        string.Equals(lang, ScriptLangs.Pwsh, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    private bool _stopRequested;

    // 当前执行会话的日志文件路径（log/yyyy-MM-dd/脚本名_yyyyMMddHHmmss.log），无活动执行时为空
    private string? _currentLogFile;

    private void OnLog(Guid session, LogEntry.Level level, string text)
    {
        // 会话隔离：只接受「当前执行会话」的日志，避免切走脚本后旧进程输出串台到新脚本控制台
        if (session != _runSession) return;
        // 后台线程通过 Dispatcher 回到 UI 线程更新日志集合
        Application.Current.Dispatcher.BeginInvoke(new Action(() =>
        {
            // 解析 ANSI 转义为彩色片段；Text 取去 ANSI 后的纯文本（用于复制/导出）
            var spans = AnsiParser.Parse(text);
            var clean = string.Concat(spans.Select(s => s.Text));
            Logs.Add(new LogEntry(level, clean, spans));
            // 文件日志带时间戳前缀（不含行号），与面板「显示时间」格式一致
            AppendLogToFile($"[{DateTimeOffset.Now:HH:mm:ss.fff}] {clean}");
            CommandManager.InvalidateRequerySuggested(); // 日志数量变化，刷新复制/清空按钮可用性
        }), DispatcherPriority.Background);
    }

    /// <summary>
    /// 将一行日志持续追加写入 exe 同级 log/yyyy-MM-dd/脚本名_yyyyMMddHHmmss.log（UTF-8 无 BOM）。
    /// 文件按执行会话（运行开始时）确定，目录不存在则自动创建。
    /// </summary>
    private void AppendLogToFile(string text)
    {
        if (string.IsNullOrEmpty(_currentLogFile)) return;
        try
        {
            File.AppendAllText(_currentLogFile, text + "\n", new UTF8Encoding(false));
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MainViewModel] 写入日志文件失败：{ex.Message}");
        }
    }

    private void StopRunning()
    {
        if (!IsRunning) return;
        _stopRequested = true;
        ScriptRunner.Stop();
        // 会话作废：即便进程还有残留输出，OnLog 也会因 session 不匹配而丢弃
        _runSession = Guid.Empty;
        SetBaseStatus(Strings.StatusStopping);
    }
    #endregion

    #region runtime 选择（按脚本语言校验/带出可执行文件）
    /// <summary>
    /// 校验当前脚本语言的可执行文件：先读已保存配置，缺失则尝试自动检测（PATH / 系统目录）。
    /// 结果驱动顶部只读输入框（SelectedExePath）；未配置时 SelectedExePath 为空并展示占位提示。
    /// </summary>
    private void RefreshRuntimeStatus()
    {
        var lang = SelectedScript?.Lang;
        if (string.IsNullOrEmpty(lang))
        {
            // 未选择脚本：不显示 placeholder，也不带出任何路径
            SelectedExePath = "";
            RuntimePlaceholder = "";
            return;
        }

        // 已保存的选择优先；未配置【或已失效（文件已被删除，如旧 JDK 卸载/更新）】则尝试自动检测并落盘，
        // 实现「PATH 里有就默认带出」「换新版本后无需手动重选」
        var path = RuntimeConfig.Get(lang!);
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            var detected = RuntimeConfig.Detect(lang!);
            if (!string.IsNullOrWhiteSpace(detected))
            {
                RuntimeConfig.Save(lang!, detected);
                path = detected;
            }
        }

        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
        {
            // 成功带出（或已配置且有效）
            SelectedExePath = path;
            RuntimePlaceholder = "";
        }
        else
        {
            // 带不出来：提示用户配置环境变量或自行选择文件（即使已配置但路径失效也归于此提示）
            SelectedExePath = "";
            RuntimePlaceholder = Strings.RuntimePlaceholderMissing;
            RuntimeError = true;   // 未找到有效可执行文件：输入框标红
        }

        // 校验可执行文件有效性：实跑「获取版本号」命令。
        // 该操作会启动子进程，冷启动可达数百毫秒~数秒，绝不能在 UI 线程同步等待（会导致点选目录树卡顿）。
        // 策略：命中缓存直接同步回填；未命中先置为「就绪」让 UI 立刻响应，再后台实跑，完成后回 UI 线程刷新版本号。
        var exePath = SelectedExePath;
        if (RuntimeProbe.TryGetCached(lang, exePath, out var cached))
        {
            ApplyProbeResult(lang!, cached.ok, cached.version);
            return;
        }

        SetBaseStatus(Strings.StatusReady);
        RuntimeError = false;
        IsRuntimeChecking = true;   // 校验中：执行按钮置灰、选择框禁用
        var probeLang = lang!;
        Task.Run(() =>
        {
            var (ok, version) = RuntimeProbe.Probe(probeLang, exePath);
            Application.Current.Dispatcher.BeginInvoke(new Action(() =>
            {
                // 用户可能已切到别的脚本，丢弃过期结果
                if (!string.Equals(SelectedScript?.Lang, probeLang, StringComparison.OrdinalIgnoreCase)) return;
                ApplyProbeResult(probeLang, ok, version);
            }));
        });
    }

    /// <summary>把探测结果落到 UI：成功显示版本号，失败则可执行文件路径输入框标红、运行按钮置灰。</summary>
    private void ApplyProbeResult(string lang, bool ok, string? version)
    {
        IsRuntimeChecking = false;  // 校验完成：恢复执行按钮与选择框
        RuntimeError = !ok;
        SetBaseStatus(ok
            ? $"{Strings.StatusReady} · {lang} {version}"
            : $"{Strings.StatusReady} · {Strings.StatusRuntimeInvalid}");
    }

    private void PickRuntime()
    {
        PickExeForCurrentLang();
    }

    // 点击顶部只读输入框：选择该语言对应的 exe（java.exe / cmd.exe / python.exe …），选择后写入 RuntimeConfig 并刷新
    private void PickExe()
    {
        PickExeForCurrentLang();
    }

    private void PickExeForCurrentLang()
    {
        var lang = SelectedScript?.Lang;
        if (string.IsNullOrEmpty(lang)) return;
        var dlg = new OpenFileDialog
        {
            Title = string.Format(Strings.DlgPickRuntimeTitleFormat, lang),
            Filter = Strings.DlgPickRuntimeFilter,
            FileName = RuntimeConfig.Get(lang!) ?? ""
        };
        if (dlg.ShowDialog() != true) return;

        // 手动选择即落盘（无论版本校验是否通过）：用户错选后可由「自动」按钮纠正。
        // 校验失败会在 UI 标红、置灰运行按钮，但不应丢弃用户的显式选择。
        RuntimeConfig.Save(lang!, dlg.FileName);
        RefreshRuntimeStatus(); // 内部回填 SelectedExePath 并实跑/命中版本号探测，失败则标红
    }

    /// <summary>
    /// 「自动」按钮：忽略用户当前选择，重新按环境变量/系统目录自动检测该语言的可执行文件，
    /// 覆盖缓存并回填，用于纠正用户错选后「不知道本来该选哪个」的情况。
    /// 不缓存版本号 —— 仍由 RefreshRuntimeStatus 实时探测。
    /// </summary>
    private void AutoRuntime()
    {
        var lang = SelectedScript?.Lang;
        if (string.IsNullOrEmpty(lang)) return;

        // 自动检测 = 从注册表（Machine+User）重新加载环境变量到当前进程，再按最新 PATH 重新查找。
        // 这样刚装/升级的运行时（如 JDK）无需重启工具即可被检测到；同时作废版本探测缓存。
        EnvironmentSync.RefreshProcessEnvironment();
        RuntimeProbe.ClearCache();

        var detected = RuntimeConfig.Detect(lang!);
        if (string.IsNullOrWhiteSpace(detected))
        {
            // 环境中确实找不到：提示用户配置环境变量或手动选择，不动现有选择
            ShowTemporaryStatus(Strings.StatusRuntimeAutoFail);
            return;
        }

        RuntimeConfig.Save(lang!, detected);   // 覆盖用户错选
        SelectedExePath = detected;
        RuntimePlaceholder = "";
        ShowTemporaryStatus(Strings.StatusRuntimeAutoSet);
        RefreshRuntimeStatus();                // 重新实跑版本探测，刷新状态栏版本号
    }
    #endregion

    #region 导出 / 复制 / 重置
    private void DoExport()
    {
        try
        {
            // 让用户自行选择导出目录，将整个 script 目录打包为 script_yyyyMMddHHmmss.zip
            var dlg = new OpenFolderDialog
            {
                Title = Strings.DlgExportDirTitle,
                InitialDirectory = ExeDir
            };
            if (dlg.ShowDialog() != true) return; // 用户取消
            var ok = Exporter.ExportToZip(ConfigLoader.ScriptDir, dlg.FolderName, out var zipPath, out var error);
            if (ok)
            {
                ShowTemporaryStatus(string.Format(Strings.StatusExportedTo, zipPath));
                // 打开资源管理器并选中刚导出的压缩包
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"/select,\"{zipPath}\"",
                    UseShellExecute = true
                });
            }
            else
            {
                ShowTemporaryStatus(string.IsNullOrEmpty(error)
                    ? Strings.StatusExportEmpty
                    : string.Format(Strings.StatusExportFailFormat, error));
            }
        }
        catch (Exception ex)
        {
            ShowTemporaryStatus(string.Format(Strings.StatusExportFailFormat, ex.Message));
        }
    }

    private void CopyPreview()
    {
        // 复制「代入后」的完整脚本（与预览一致），源文件不受影响。
        // 结果统一反馈在底部状态栏，不弹 MessageBox（避免打断操作）。
        var text = BuildParameterizedScript(lang: SelectedScript?.Lang);
        if (string.IsNullOrEmpty(text))
        {
            ShowTemporaryStatus(Strings.StatusCopyEmpty);
            return;
        }

        try
        {
            Clipboard.SetText(text);
            ShowTemporaryStatus(Strings.StatusCopied);
        }
        catch (Exception ex)
        {
            // 剪贴板可能被其它程序占用，SetText 会抛异常：只提示，不崩
            ShowTemporaryStatus(string.Format(Strings.StatusCopyFailFormat, ex.Message));
        }
    }

    /// <summary>导出「代入参数后」的完整脚本，文件名与脚本文件一致，UTF8 无 BOM。</summary>
    private void ExportPreview()
    {
        if (SelectedScript == null) return;
        var script = SelectedScript;
        var text = BuildParameterizedScript(lang: script.Lang);
        var defaultName = Path.GetFileName(script.ResolvedPath);
        SaveTextWithDialog(defaultName, text, Strings.DlgExportScriptFilter, Strings.DlgExportScriptDonePrefix);
    }

    /// <summary>用 SaveFileDialog 让用户选择保存位置，按 UTF-8 无 BOM 写出文本（与源脚本一致）。</summary>
    private void SaveTextWithDialog(string defaultFileName, string content, string filter, string successPrefix)
    {
        try
        {
            var dlg = new SaveFileDialog
            {
                FileName = defaultFileName,
                Filter = filter,
                AddExtension = true,
                DefaultExt = Path.GetExtension(defaultFileName)
            };
            if (dlg.ShowDialog() != true) return; // 用户取消
            File.WriteAllText(dlg.FileName, content ?? string.Empty, new UTF8Encoding(false));
            ShowTemporaryStatus($"{successPrefix}{dlg.FileName}");
        }
        catch (Exception ex)
        {
            ShowTemporaryStatus(string.Format(Strings.StatusExportFailFormat, ex.Message));
        }
    }

    private void ResetParams()
    {
        // 原位复位当前每个参数的值为默认（保留缓存引用，避免切换后缓存失效）。
        // 注意：给 f.Value 赋值会触发 PropertyChanged → 内部已调过 RenderPreview(keepScrollPosition: true)，
        // 此处再调一次是为了覆盖「参数无变化」的情况（此时事件不会触发，但预览需与默认值保持一致）。
        foreach (var f in ParamFields)
            f.Value = f.Param.Default ?? "";
        RenderPreview(keepScrollPosition: true);
        ShowTemporaryStatus(Strings.StatusParamsReset);
    }
    #endregion
}
