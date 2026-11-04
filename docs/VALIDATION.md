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

## 测试变化分析阶段

新增内容身份优先的测试匹配、增删改清单和失败证据追踪。修复新增或改动参考解失败被身份匹配逻辑跳过的问题。

28 项核心测试在 JS、Windows native、wasm-gc 后端全部通过；16 项命令行断言通过。完整本地脚本 scripts/ci.py 通过，包含格式、严格检查、构建、测试及公开接口一致性验证。新增场景涵盖编号互换、同名替换、重复内容歧义、删除失败证据、缺失新运行及纯数据变化退出码。

新字段中不存在的新测试或新判定显式序列化为 JSON null。JSON/HTML 示例报告已在 results/ 中重新生成。新提交的远端验收状态以对应 Actions 运行记录为准。


## Polygon 文档格式导入阶段

42 项核心测试在 JS、Windows native、wasm-gc 后端全部通过；21 项命令行断言通过；只读采集辅助脚本的 5 项假传输测试通过。完整 scripts/ci.py 在本机通过。覆盖标准判定、跳过和缺项、包及运行不匹配、重复记录、大整数 ID、重复 JSON 键、额外标签、来源缺失与包级诊断。

这些结果只证明当前实现对所列文档格式用例的行为，不等于真实 Polygon 服务调用或题目包版本绑定验收。导出脚本没有访问用户账号，未采集真实题目，也没有上传未公开材料。
