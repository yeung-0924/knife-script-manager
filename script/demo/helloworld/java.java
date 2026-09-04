// 更新时间: 2026-09-04
// 单文件 Java 脚本（需 Java 11+，支持 `java java.java` 直接源码启动，无需先 javac）
// 简单演示：输出 Hello 并回显传入的参数。
public class java {
    public static void main(String[] args) {
        String name = "_p{NAME}";
        System.out.println("===== Hello, World =====");
        System.out.println("Hello, " + name + "!");
        System.out.println("接收参数 Name = " + name);

        System.out.println("===== 多色日志 =====");
        // 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
        System.out.println("\u001b[30m这是一行\"30\"日志（黑）\u001b[0m");
        System.out.println("\u001b[31m这是一行\"31\"日志（红）\u001b[0m");
        System.out.println("\u001b[32m这是一行\"32\"日志（绿）\u001b[0m");
        System.out.println("\u001b[33m这是一行\"33\"日志（黄）\u001b[0m");
        System.out.println("\u001b[34m这是一行\"34\"日志（蓝）\u001b[0m");
        System.out.println("\u001b[35m这是一行\"35\"日志（品红）\u001b[0m");
        System.out.println("\u001b[36m这是一行\"36\"日志（青）\u001b[0m");
        System.out.println("\u001b[37m这是一行\"37\"日志（白）\u001b[0m");
        System.out.println("\u001b[90m这是一行\"90\"日志（灰）\u001b[0m");
        System.out.println("\u001b[91m这是一行\"91\"日志（亮红）\u001b[0m");
        System.out.println("\u001b[92m这是一行\"92\"日志（亮绿）\u001b[0m");
        System.out.println("\u001b[93m这是一行\"93\"日志（亮黄）\u001b[0m");
        System.out.println("\u001b[94m这是一行\"94\"日志（亮蓝）\u001b[0m");
        System.out.println("\u001b[95m这是一行\"95\"日志（亮品红）\u001b[0m");
        System.out.println("\u001b[96m这是一行\"96\"日志（亮青）\u001b[0m");
        System.out.println("\u001b[97m这是一行\"97\"日志（亮白）\u001b[0m");
    }
}
