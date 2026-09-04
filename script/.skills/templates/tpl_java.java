// 更新时间: 2026-09-04
// Java 最小模板（ScriptManager）
// 文件名须与 public class 名完全一致（如 MyScript.java → class MyScript）
// 参数用 _p{NAME} 占位符，运行前由程序替换（需 Java 11+ 单文件启动）
public class MyScript {
    public static void main(String[] args) {
        System.out.println("===== Hello, World =====");
        System.out.println("Hello, _p{NAME}!");
    }
}
