namespace ScriptManager;

/// <summary>
/// 集中管理所有用户可见的文本（按钮、标题、状态消息、占位提示、对话框文案等），
/// 方便统一维护与本地化。内部实现细节（Debug 日志、运行时命令参数）不在此列。
/// </summary>
public static class Strings
{
    #region 版本号
    // 发版时在此修改；UI 右下角以 "v {Version}" 形式展示，常量写死，运行时不暴露给用户修改
    public const string Version = "1.0.0";
    #endregion

    #region 标题（面板/分区）
    public const string TitleScriptList = "脚本列表";
    public const string TitleScriptParams = "脚本参数";
    public const string TitleScriptPreview = "脚本预览";
    public const string TitleExecLog = "执行日志";
    public const string TitleWindow = "脚本管理器";
    #endregion

    #region 按钮
    public const string BtnExport = "导出";
    public const string BtnOpen = "打开";
    public const string BtnSave = "保存";
    public const string BtnReset = "重置";
    public const string BtnDefault = "默认值";
    public const string BtnCopy = "复制";
    public const string BtnSettings = "配置";
    public const string BtnClear = "清空";
    public const string BtnRun = "执行";
    public const string BtnStop = "停止";
    public const string BtnAuto = "自动检测";
    public const string BtnAutoToolTip = "自动检测环境变量中的可执行文件";
    public const string BtnExpandAll = "展开全部";
    public const string BtnCollapseAll = "收起全部";
        public const string BtnExpandCollapseToolTip = "展开/收起全部目录";
        #endregion

        #region 顶部菜单（工具栏）
        public const string MenuFile = "文件";
        public const string MenuSettings = "设置";
        public const string MenuEditConfig = "编辑配置...";
        public const string TitleConfigEditor = "配置编辑 - config.ini";
        public const string ConfigEditorNote = "修改后需重启程序生效。各项只能选择目录/文件，不可手动输入；点击「默认值」可一键恢复出厂设置。";
        public const string ConfigEditorSaved = "已保存（重启后生效）";
        public const string ConfigEditorRestored = "已还原为默认值（重启后生效）";
        public const string ConfigEditorSaveFail = "保存失败：{0}";
        public const string ConfigEditorBrowseFolder = "选择目录";
        public const string ConfigEditorBrowseFile = "选择脚本索引文件 (index.json)";
        #endregion

    #region 状态消息（StatusText）
    public const string StatusReady = "就绪";
    public const string StatusRunningFormat = "正在执行：{0}";
    public const string StatusStoppedFormat = "已停止：{0}";
    public const string StatusCompletedFormat = "完成：{0}（退出码 0）";
    public const string StatusExitedFormat = "结束：{0}（退出码 {1}）";
    public const string StatusExceptionFormat = "执行异常：{0}";
    // 执行超时（{0} = 脚本名）：自动终止后的状态栏提示
    public const string StatusTimeoutFormat = "执行超时，已终止：{0}";
    public const string StatusStopping = "正在停止…";
    // 可执行文件版本校验进行中（覆盖 StatusText 显示）
    public const string StatusRuntimeChecking = "可执行文件检测中…";
    // 执行耗时（状态栏右侧独立文本块，不并入左侧状态文字）：{0} = mm:ss.fff，如 00:05.123
    public const string StatusElapsedFormat = "已用时 {0}";       // 执行进行中（数值持续跳变）
    public const string StatusTotalElapsedFormat = "总用时 {0}";  // 执行结束后（定格为总耗时）
    public const string StatusRuntimePickedFormat = "已为 {0} 指定可执行文件：{1}";
    // 执行器（可执行文件）校验失败时的状态栏后缀：与 StatusReady 拼接为「就绪 · 未检测到有效的可执行文件」
    public const string StatusRuntimeInvalid = "未检测到有效的可执行文件";
    public const string StatusExportedTo = "已导出到：{0}";
    public const string StatusExportEmpty = "导出失败：没有可导出的脚本";
    public const string StatusExportSameDir = "导出目标与源脚本目录相同，请另选目录";
    public const string StatusExportSourceMissingFormat = "脚本目录不存在：{0}";
    public const string StatusExportFailFormat = "导出失败：{0}";
    public const string StatusCopied = "已复制脚本内容到剪贴板";
    public const string StatusLogCopied = "已复制日志内容到剪贴板";
    #endregion

    #region 参数清空按钮
    public const string ClearButtonToolTip = "清空";
    // 浏览按钮已改为图标样式，文本常量（Bz"浏览…"）已不再被 XAML 引用，保留无意义故删除；ToolTip 仍由 Bz BrowseButtonToolTip 提供
    //（保留作死代码清理记录，2026-09-01 复检若仍无引用即可删除）
    public const string BrowseButtonToolTip = "选择文件或目录";
    #endregion

    #region 脚本复制（结果统一反馈在底部状态栏，不弹窗）
    public const string StatusCopyEmpty = "没有可复制的脚本内容";
    public const string StatusCopyFailFormat = "复制失败：{0}";
    #endregion

    #region 操作反馈（临时提示，数秒后自动恢复为就绪态）
    // StatusReloaded / StatusReloadedEnv：原「刷新」按钮提示，刷新功能下线后已废弃（保留作清理记录）。
    public const string StatusLogCleared = "已清空执行日志";
    public const string StatusParamsReset = "已重置为默认值";
    public const string StatusRuntimeAutoSet = "已按环境变量自动获取可执行文件";
    // 「打开」脚本索引文件的反馈（状态栏轻提示，不弹窗）：成功加载并记住 / 所选文件非有效脚本索引
    public const string StatusOpenScriptFileDone = "已打开脚本文件（已记住，重启后自动加载）";
    public const string StatusOpenScriptFileInvalid = "所选文件不是有效的脚本索引（index.json）";
    public const string StatusRuntimeAutoFail = "环境中未检测到该语言的可执行文件，请配置环境变量或自行选择";
    #endregion

    #region 占位提示
    public const string RuntimePlaceholderMissing = "未检测到有效的可执行文件，请配置环境变量或自行选择";
    #endregion

    #region 可执行文件路径输入框 ToolTip
    public const string ExePathBoxToolTip = "点击输入框选择可执行文件";
    #endregion

    #region 脚本读取/渲染提示
    public const string ScriptFileMissingFormat = "(脚本文件不存在: {0})";
    public const string ScriptReadFailFormat = "(读取脚本失败: {0})";
    #endregion

    #region 对话框
    public const string DlgPickRuntimeTitleFormat = "选择 {0} 的可执行文件（exe）";
    public const string DlgPickRuntimeFilter = "可执行文件 (*.exe)|*.exe|所有文件 (*.*)|*.*";
    public const string DlgPickFileTitle = "请选择{0}";
    public const string DlgPickFileFilter = "所有文件 (*.*)|*.*";
    public const string DlgPickFolderTitle = "请选择{0}";
    public const string DlgExportDirTitle = "选择导出目录";
    public const string DlgExportScriptFilter = "脚本文件|*.*";
    public const string DlgExportScriptDonePrefix = "导出的脚本已保存到：";
    public const string DlgOpenScriptFileTitle = "选择脚本索引文件（index.json）";
    #endregion

    #region 执行日志（输出到日志面板与 log/ 文件，用户可见）
    public const string LogRuntimeUnresolvedFormat = "✗ 无法解析运行时：语言 [{0}] 未检测到有效的可执行文件（请点击顶部右侧输入框选择 exe）";
    // 必填参数未填写（{0} = 未填写的参数名列表，以「、」分隔）
    public const string LogRequiredMissingFormat = "✗ 以下必填参数未填写：{0}";
    public const string StatusRequiredMissingFormat = "必填参数未填写：{0}";
    public const string LogProcessStartFormat = "── 开始执行 ──";
    public const string LogProcessStartAdminFormat = "── 开始执行（管理员权限）──";
    public const string LogProcessExitFormat = "── 结束执行（退出码 {0}）──";
    public const string LogExecExceptionFormat = "✗ 执行异常：{0}";
    // 执行超时（{0} = 超时秒数）：自动终止进程树
    public const string LogTimeoutFormat = "✗ 执行超时（{0} 秒），已自动终止进程";
    public const string LogElevatedFailFormat = "✗ 提权执行失败：{0}";
    #endregion
}
