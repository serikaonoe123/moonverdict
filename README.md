# MoonVerdict

MoonVerdict 是面向算法竞赛出题人的验题记录比较工具，以 MoonBit 实现分析核心。

当前版本为 **0.0.1 原型**。已实现标准 JSON 快照导入、输入校验、解法和测试内容身份匹配、测试增删改清单、失败证据追踪、判定比较、原始文件摘要核对，以及 JSON / 离线 HTML 报告。

## 运行

本地验证工具链：moonc `0.10.17+d971670cd`、moon `0.1.20261023`，另需 Node.js。工具链不打包进仓库。若使用多个工具链，应使 `MOON_HOME` 和所调用的 `moon` 对应。

```powershell
moon check --target js --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon run cmd/moonverdict --target js -- examples/before.json examples/after.json
moon run cmd/moonverdict --target js -- examples/before.json examples/after.json html > report.html
```

最后两条命令发现需审查变化时退出码为 1，这是预期结果。仅测试数据变化而没有判定回归，也会返回 1。相同完整记录比较退出码为 0，输入或读取错误为 2。PowerShell 重定向 HTML 时使用 UTF-8 编码；也可直接运行构建后的 Node 程序。

当前文件命令行使用 JS/Node 后端。核心支持 native、JS 和 wasm-gc；原生命令行尚未实现。HTML 目前为可离线阅读的结构化结果，交互报告待开发。

## 快照 v1

字段示例见 [examples/before.json](examples/before.json)。必填字段：

- `schema_version`：目前为 1。
- `problem`、`revision`：题目标识和版本标签。
- `semantics`、`environment`、`checker`：比较前提的标识，变化时需要复核。
- `finished`：采集方声明的运行结束状态；仍须检查矩阵是否完整。
- `tests`：`id` 和 64 位小写十六进制 `digest`。
- `solutions`：`id`、`digest`、`expected`（`pass` / `fail` / `unspecified`）。
- `runs`：`solution`、`test_id`、`verdict`。支持 AC、WA、PE、TLE、MLE、RE，以及 SKIPPED、UNKNOWN、ERROR。

未知字段、重复 ID、重复单元格、悬空引用、空测试集合和不支持的判定均被拒绝。缺失单元格允许导入，但标记为不完整。解法按两侧唯一摘要匹配，重复摘要不会自动配对。

`KNOWN_FAILURE_LOST` 表示在所提供的元数据前提下，同一个仍应失败的解法从有失败记录变为所有必需测试通过。环境、题意或判题器标识改变时，只报告待复核转换。它不证明所有错误解法均能被数据拦住。

## 证据边界

常规比较的 `digest` 仅检查格式；`environment` 等也是输入方声明。比较报告仍带有 `supplied-metadata-unverified`。示例是合成的预期判定，不是 Polygon 导出或真实验题成果。

可额外核对原始文件：

```powershell
moon run cmd/moonverdict --target js -- verify examples/evidence/snapshot.json examples/evidence/bundle.json
```

此命令以清单所在目录为根，读取原始输入、答案和解法文件，用 SHA-256 核对内容。详见 [证据格式](docs/EVIDENCE.md)。核对通过仅说明当前文件内容与所提供摘要相符，不证明历史运行记录的来源；输出保留 `run_binding_verified: false`。

测试内容匹配与失败证据清单的规则见 [测试变化说明](docs/TEST-CHANGES.md)。编译及资源条件结构化建模、Polygon 真实导出验收、运行来源绑定和用户试用待完成。自动测试配置已加入仓库，云端结果以实际运行记录为准。这个原型不宣称完成计划书验收。

离线导入不需要线上凭证。Polygon 包验证导入器已实现，处理 RJ/NO/TS、缺项、包级诊断及材料 ID 不匹配；已用文档格式样例验证，真实导出验收尚待完成。使用命令和本机只读采集步骤见 [Polygon 导入与采集说明](docs/POLYGON.md)。

## 开发

使用 `moon fmt`、`moon info` 更新格式与公开接口。`compare_test.mbt` 覆盖错解漏过、未知状态、内容身份变化、歧义、预期标签变化和 HTML 转义等判断边界。

许可证：MIT。全部初始源码与合成样例为本项目编写；仅依赖 MoonBit 标准库和 Node 内置文件接口。设计参考资料未复制实现代码。
