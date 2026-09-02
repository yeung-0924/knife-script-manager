---
name: csharp-coding-standards
description: 一套可直接执行的 C# 代码规范。覆盖命名、格式、异步、空值、异常、集合、依赖注入、性能与安全，用于编写、审查、重构 C# 代码时将质量内化。
agent_created: true
---

# C# 开发规范（Craft / Code-First）

一套可直接落地的 C# 代码规范。当你写、审阅、重构 C# 代码时，优先按本技能约束，而不是依赖通用经验——本规范优于模型的泛化知识。

适用：.NET 6+（含 .NET 8/9），默认 C# 最新语言版本。未声明的差异按微软官方 .NET 约定处理。

## 何时使用

- 编写新功能、类、接口、API、工具类
- 审查（code review）他人或既有 C# 代码
- 重构、诊断、解释 C# 代码时给出符合规范的结论
- 用户明确要求 "规范" / "标准" / "最佳实践" / "代码风格" 时

## 一、命名规范（Naming）

- **PascalCase**：类、接口、方法、属性、事件、结构体、枚举、namespace。
  - 接口名以 `I` 开头：`IRepository`、`IUserService`。
- **camelCase**：局部变量、方法参数、私有字段；私有字段可加 `_` 前缀：`_userId`。只读私有字段也可用 `_userName`。
- **全大写 + 下划线**：常量 `MaxRetryCount`、静态只读常量；不要 `MAX_RETRY`。
- 布尔变量用肯定式：`IsEnabled` / `HasValue` / `CanDelete`，不用 `Flag`、`Flagged`。
- 集合/数组用复数：`orders`、`userList` 不如 `users`；避免 `List`/`Array` 后缀。
- 不要用匈牙利命名（`strName`、`iCount`）、不要缩写（`mgr`、`calc`，除非 `Id`、`Url`、`Api` 等通用缩写）。
- 命名空间：`Company.Product.Module`（如 `Acme.Order.Service`）。文件名与主要类型同名。
- 异步方法以 `Async` 结尾：`GetUserAsync`，事件用 `OnXxx` 或 `XxxChanged`。

## 二、代码格式（Formatting）

- 使用 4 个空格缩进，禁止 Tab。
- 一行最大 120 字符；超出则换行（链式调用、长参数列表优先换行）。
- 每个文件单个顶级类型（类/接口/枚举），除非极小的嵌套类型。
- 大括号另起一行（Allman）：`if (x) { }` 的 `{` 在新行。
- `using` 写在文件顶部，按字母排序，按命名空间分组用空行。
- 优先 `var`（右值能明显看出类型时）；类型不明显时用具体类型：`var list = new List<int>();` 好；`var x = GetById(id);` 不如 `User user = GetById(id);`。
- 优先表达式体成员：`public string Name => _name;` / `public int Sum() => a + b;`
- 禁止无意义空行和连续空行（最多 1 行）。

## 三、类型与语法（Types & Syntax）

- 优先不可变：`record`（值语义）、`readonly struct`、`readonly` 字段；`init` 属性用于创建后不可变对象。
- 优先 `string` 内插而非拼接：`$"id={id}"` 而非 `"id=" + id`。
- 字符串处理用 `StringBuilder`/`string.Create` 在循环中拼接；避免反复 `+`。
- 优先 `switch` 表达式与模式匹配：`x switch { }`。
- 枚举用 `[Flags]` + 位运算处理组合；避免魔法数字，用命名常量。
- 优先 `using` 声明（C# 8+）管理 `IDisposable`：`using var conn = new SqlConnection(...);`
- 不要暴露 public 可变集合字段；暴露 `IReadOnlyList<T>` / `ImmutableArray<T>`。
- 优先 `nameof()` 而非硬编码字符串，便于重命名。
- 数值比较使用 `decimal` 处理货币，`double` 仅用于科学计算。

## 四、异步编程（Async/Await）

- 异步方法返回 `Task` / `Task<T>` / `ValueTask<T>`；事件处理或入口点可 `async void`（仅限事件）。
- **禁止 `async void`**（除事件处理器），改用 `async Task`。
- 用 `await` 而非 `.Result` / `.Wait()` / `.GetAwaiter().GetResult()`（避免死锁与异常包装）。
- 禁止 `Task.Run` 包装同步 CPU 密集代码后声称异步——CPU 密集用专用线程或 `Task.Run` 时明确注释。
- 需要并行用 `Task.WhenAll` 而非顺序 `await`。
- 取消支持：长时间/可取消操作接收 `CancellationToken` 参数，默认不忽略。
- 配置：库代码避免 `ConfigureAwait(false)` 除非明确无上下文需求；应用层通常不用。
- 不要 `async` + 立即返回 `Task.CompletedTask` 的空壳；同步逻辑不要强制异步。

## 五、空值与可空性（Null Safety）

- 启用 `<Nullable>enable</Nullable>`（可为 null 引用类型）。
- 不可为 null 的字段/属性必须有初始化或构造函数赋值。
- 外部输入（API/数据库/反序列化）一律视为可能为 null，先做 null 检查。
- 优先 `??=`/`??`/`?.`：`name ?? "default"`、`dict.TryGetValue`。
- 不要用 `NullReferenceException` 控制流程；用 `ArgumentNullException.ThrowIfNull(arg)`（.NET 6+）。
- 避免 `string.IsNullOrEmpty`/`IsNullOrWhiteSpace` 误用：白名单校验优先于黑名单。

## 六、异常处理（Exception Handling）

- 只捕获你能处理的异常；不要 `catch (Exception)` 吞掉后忽略。
- 用具体异常类型（`ArgumentException`、`InvalidOperationException`），不用通用 `Exception`。
- 用 `throw;` 保留堆栈；不要 `throw ex;` 重置堆栈。
- 不要在循环里 try-catch 整个循环；在边界（API/任务）统一处理。
- 不要在 `finally` 中抛异常。
- 自定义异常以 `Exception` 结尾，提供 `Message` 与必要上下文；不暴露内部敏感信息。
- 不要用异常做流程控制（用 `TryParse`、`TryGetValue`）。

## 七、集合与 LINQ

- 优先不可变/明确集合类型：方法返回 `IReadOnlyList<T>` 而非 `List<T>`；接收参数用 `IEnumerable<T>` 或 `IReadOnlyList<T>`。
- 大数据流用 `IAsyncEnumerable<T>` 而非一次性 `ToList`。
- 避免 N+1：用 `Include` / `Select` 投影，而非循环查库。
- LINQ 可读优先：`Where/Select/GroupBy`；复杂逻辑用具名方法而非超长 lambda。
- 判断包含用 `HashSet`；频繁查找用 `Dictionary`。
- 不要对 `IEnumerable` 多次枚举（多次 `foreach` 会重复执行）——先 `ToList()` 或 `ToArray()`。

## 八、依赖注入与架构

- 构造函数注入依赖，不在方法内 `new` 服务（除非工厂/本地对象）。
- 接口优先，便于测试与替换；服务注册放在 `Program`/`Startup` 统一处。
- 单一职责：一个类只做一件事；方法不要太长（> 60 行考虑拆分）。
- 领域模型与 DTO 分层；API 入参用 DTO 并校验（FluentValidation 或 DataAnnotations）。
- 不要在静态类里保存可变状态（除非明确无状态工具类）。

## 九、性能（Performance）

- 热路径避免装箱（`object` 装箱、非泛型集合）；用 `Span<T>`/`Memory<T>`/`stackalloc` 处理切片。
- 字符串格式化用 `string.Format`/`$`/`StringBuilder`；高频拼接避免 `string.Join` 循环内拼接。
- 避免 `async` 方法中同步阻塞（`lock` 重锁、`Task.Result`）。
- 缓存：重复计算/外部调用加缓存（`IMemoryCache`/`MemoryCache`）；注意过期与失效。
- 使用 `ArrayPool<T>` / `StringBuilder` 池化大对象。
- 优先 `readonly struct`/`record struct` 减少分配。

## 十、安全（Security）

- 任何拼接 SQL 用参数化查询（`SqlParameter` / EF Core 参数化），禁止字符串拼接 SQL（防注入）。
- 用户输入展示到前端先转义（防 XSS）；HTML 用 `HtmlEncoder`。
- 密钥、连接串写入配置/环境变量（`IConfiguration` / Secrets），不要硬编码。
- 文件路径用 `Path.Combine`，不要字符串拼路径，防路径穿越。
- 文件/命令/反序列化等敏感操作来自定义工具或受控能力时，先做安全审计。

## 十一、代码审查自查清单（每次写完必过）

- [ ] 命名符合规范、无拼写错误
- [ ] 所有 `using` 必要且无冗余
- [ ] 必要字段已 null 检查 / 启用 nullable
- [ ] 异步代码无 `async void`、无 `.Result`
- [ ] 异常捕获具体、未吞掉异常
- [ ] 无硬编码密钥/SQL 拼接
- [ ] 边界条件（空集合、空值、异常输入）已处理
- [ ] 类型可编译通过、命名清晰
- [ ] 用户可见字符串已抽到 `Strings`/常量类，未硬编码在业务逻辑中

## 十二、用户可见文本统一常量（UI 文案管理）

任何会展示给用户的字符串字面量（按钮/标题文本、状态栏消息、占位提示、ToolTip、对话框标题与 Filter、日志/输出文案），**禁止硬编码在 `.cs`/`.xaml` 业务逻辑里**，应集中到常量类统一管理，便于维护与未来本地化。

- 建立 `static class Strings`（按 `#region` 分区：`标题`/`按钮`/`状态消息`/`占位提示`/`对话框`/`日志` 等），常量用 `public const string`。
- 带占位符的字符串用 `{0}`/`{1}` 格式，调用处 `string.Format(Strings.Xxx, arg)`。
- C# 引用：`Strings.BtnExport`；XAML 引用：`{x:Static local:Strings.BtnExport}`（`local` 指向常量类所在命名空间）。
- **不纳入**（保留字面量）：代码注释、外部契约字符串（如 JSON 配置字段名）、运行时命令/进程参数等纯内部实现细节、`Debug.WriteLine` 内部调试日志。
- 新增用户可见文本时：先加常量，再引用；重构既有硬编码文案时同步抽到常量类。

## 交付约定

- 用户要求运行命令、检查数据、审查代码时，重要细节在回复中直接说明，不依赖折叠输出。
- 多部分任务逐条回答；产生的可查看交付物用结果卡片呈现。
- 涨→红、跌→绿（CNY 默认货币符号 ¥），仅在金融工具场景适用。

## 反思提示

完成多步 C# 任务后，若发现更优工作流（编译器/分析器版本、常见坑、命令、决策规则），请回来修正本技能。
