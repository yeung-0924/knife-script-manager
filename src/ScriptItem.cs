namespace ScriptManager;

/// <summary>
/// 对应 script/index.json 数组中的单个节点。
/// 索引采用嵌套结构以表达层级：
///   - 目录节点：仅需 name + children（children 非空即视为目录）
///   - 脚本节点：name + path + lang 等（属性与旧格式一致，不再需要 group 字段）
/// </summary>
public class ScriptItem
{
    /// <summary>在界面上显示的名称（目录名 / 脚本名）</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>脚本文件路径，支持 ./ 前缀，相对 script 目录；目录节点为空</summary>
    public string Path { get; set; } = string.Empty;

    /// <summary>子节点（目录）。为空表示当前节点是脚本项。</summary>
    public List<ScriptItem>? Children { get; set; }

    /// <summary>
    /// 外部索引引用（可选）。值为字符串或字符串数组，每个元素是一个相对【当前 json 所在目录】的索引文件路径。
    /// 被引用文件的内容会原地展开为当前节点的子节点（支持被引文件是数组、单个目录节点对象、或 { "children": [...] } 聚合）。
    /// 设计目标：允许把大 index.json 拆到任意层级子目录，最终在根 index.json 用 include 汇聚；
    /// 被引文件内的 path / 嵌套 include 一律相对【被引文件自身所在目录】，使其自洽。
    /// 同时支持单字符串（Include）与字符串数组（Includes）两种 JSON 写法。
    /// </summary>
    [System.Text.Json.Serialization.JsonPropertyName("include")]
    public string? Include { get; set; }

    [System.Text.Json.Serialization.JsonPropertyName("includes")]
    public List<string>? Includes { get; set; }

    /// <summary>
    /// 非序列化：被 include 进来的节点，其 path / 嵌套 include 的相对基准目录（即所在 json 文件目录）。
    /// 外层递归处理时优先使用此值而非父级 dir，使被引文件自洽。由 ConfigLoader 在解析 include 时填充。
    /// </summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public string? BaseDir { get; set; }

    /// <summary>是否为目录节点（有子节点即视为目录）。</summary>
    public bool IsGroup => Children is { Count: > 0 };

    /// <summary>
    /// 脚本语言（index.json 的 lang 字段），取值见 ScriptLangs。
    /// 为空表示未声明，树图标按空语言处理（透明占位）。
    /// </summary>
    public string Lang { get; set; } = string.Empty;

    /// <summary>是否以管理员身份执行，默认 false</summary>
    public bool Admin { get; set; }

    /// <summary>
    /// 执行超时（秒，可选）。超过该时长仍未结束则自动终止（杀掉进程树）。
    /// 为空（未声明）时回退到全局默认 <c>config.ini</c> 的 <c>default_timeout</c>；
    /// 两者均未设或值为 0/负数，则不限制（无限等待）。
    /// </summary>
    [System.Text.Json.Serialization.JsonPropertyName("timeout")]
    public int? Timeout { get; set; }

    /// <summary>
    /// 参数声明列表（来自 index.json 的 params）。为空表示脚本不需要参数。
    /// UI 会据此动态生成输入框，并把用户输入拼成 -key value 形式传给脚本。
    /// </summary>
    public List<ScriptParam>? Params { get; set; }

    // ---- 以下为运行时辅助属性，不来自 json ----

    /// <summary>规范化后的完整脚本路径</summary>
    public string ResolvedPath { get; set; } = string.Empty;
}

/// <summary>
/// 脚本语言常量（对应 index.json 的 lang 字段值）。
/// 语言固定顺序（朝云约定，凡需列举这些语言时均须遵循）：cmd(bat) → powershell → powershell7 → bash → java → nodejs → python → go → rust。
/// 目前支持：cmd / powershell / pwsh / bash / java / node / python / go / rust；新增语言在此登记，
/// 并在 Form1.ScriptIconIndex 补充对应树图标映射。
/// </summary>
public static class ScriptLangs
{
    // 顺序遵循朝云约定：cmd(bat) → powershell → powershell7 → bash → java → nodejs → python → go → rust
    public const string Cmd = "cmd";
    public const string PowerShell = "powershell";
    /// <summary>PowerShell 7+（pwsh.exe）。与 <see cref="PowerShell"/>（Windows PowerShell 5.1）区分：
    /// 后者候选为 pwsh.exe/powershell.exe 依次回退，此 lang 只认 PowerShell 6+ 的 pwsh.exe。</summary>
    public const string Pwsh = "pwsh";
    public const string Bash = "bash";
    public const string Java = "java";
    public const string Node = "node";
    public const string Python = "python";
    public const string Go = "go";
    public const string Rust = "rust";
}

/// <summary>
/// 对应 index.json 中 params 数组的单条参数定义。
/// </summary>
public class ScriptParam
{
    /// <summary>传给脚本的参数名，如 port；拼成 -port 8080</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>界面上显示的标签，如“端口号”</summary>
    public string? Label { get; set; }

    /// <summary>默认值，输入框初始内容</summary>
    public string? Default { get; set; }

    /// <summary>占位提示文字</summary>
    public string? Placeholder { get; set; }

    /// <summary>是否必填；为 true 时空值不允许执行</summary>
    public bool Required { get; set; }

    /// <summary>
    /// 可选值列表；提供则界面用下拉框（ComboBox）而非文本框。
    /// </summary>
    public List<string>? Options { get; set; }

    /// <summary>
    /// 输入控件类型（区分"填字"、"选择"、"选文件"、"选目录"）：
    ///   - "text"（默认）：文本框，用户手填
    ///   - "select"：下拉框（需配合 options）
    ///   - "file"：文本框 + 浏览按钮，弹出文件选择框
    ///   - "folder"：文本框 + 浏览按钮，弹出目录选择框
    /// 仅影响 UI 呈现，取值仍按原样代入脚本（_p{参数名} 占位符）。
    /// </summary>
    [System.Text.Json.Serialization.JsonPropertyName("type")]
    public string? Type { get; set; }

    // ---- 运行时：用户当前输入的值 ----
    /// <summary>运行时用户输入的值（不来自 json）</summary>
    public string CurrentValue { get; set; } = string.Empty;
}
