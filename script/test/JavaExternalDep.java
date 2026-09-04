// 更新时间: 2026-09-04
// Java 外部依赖测试：验证 lib 目录下的第三方 jar（如 hutool-all）能否被自动加载。
// 运行时由 RuntimeResolver 把 SCRIPT_MANAGER_LIB 下的所有 *.jar 自动拼成 --class-path，
// 故无需在脚本内手动指定 -cp，直接 import 即可。
// 约定：Java 11+ 单文件源码执行（java JavaExternalDep.java）。
import cn.hutool.core.date.DateUtil;
import cn.hutool.core.util.StrUtil;

public class JavaExternalDep {
    public static void main(String[] args) {
        String name = "_p{NAME}";

        // 调用 hutool 工具类，证明外部 jar 已成功进入 classpath
        String hello = StrUtil.format("Hello, {}! 来自 Hutool 外部依赖。", name);
        System.out.println(hello);

        // 用 hutool 取当前时间并格式化
        String now = DateUtil.now();
        System.out.println("Hutool DateUtil.now() => " + now);

        // 用 hutool 做简单字符串处理验证 API 可用
        String reversed = StrUtil.reverse(name);
        System.out.println("StrUtil.reverse(\"" + name + "\") => " + reversed);

        System.out.println("外部依赖测试完成：Hutool 加载成功 ✔");
    }
}
