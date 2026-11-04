# 本地验证记录 · 2026-11-04

环境：Windows；moonc 0.10.17+d971670cd，moon 0.1.20261023。工具链使用已有安装，未修改全局默认工具链。

| 检查 | 结果 |
|---|---|
| `moon fmt --check` | 通过 |
| `moon check --target js --deny-warn` | 通过 |
| `moon test --target js --deny-warn` | 16 / 16 |
| `moon test --target native --deny-warn` | 16 / 16 |
| `moon test --target wasm-gc --deny-warn` | 16 / 16 |
| JS 构建、公开接口生成 | 通过 |
| 命令行：相同记录、错解漏过、HTML、参数不足、文件不存在、格式错误 | 前六项断言通过 |
| 命令行：畸形 JSON、缺失结果文件 | 临时文件准备时被阻止，尚未执行 |

`scripts/check_cli.py` 未完整通过，不计为 8 项通过。默认系统临时目录创建后的文件写入报 PermissionError (Errno 13)，路径为：

```
C:\Users\29955\AppData\Local\Packages\sandbox.{bc963d22-8b86-4396-9552-bba04ea7be1f}\AC\Temp\moonverdict-cli-tgyvujhu\invalid.json
```

Python TemporaryDirectory 的自动清理也遇到 WinError 5。此后停止了该脚本，未手动更改权限或重试该路径。错误为文件系统权限拒绝，未出现平台网络安全审查提示。

本轮更新：测试改用仓库内固定的畸形 JSON 和缺项样例，移除了系统临时目录写入与自动清理。未重试原受拒目录或调整其权限。18 项核心测试在 JS、Windows native、wasm-gc 后端全部通过；12 项命令行检查全部通过，包括四项文件核验检查。原始字节核验已实现，历史运行来源绑定仍未完成。

真实 Polygon 导出、Linux 执行、远程 CI 成功、浏览器视觉检查和外部试用的状态，需以各自独立记录为准；本地通过不代表云端通过。
