# Polygon 离线导入与真实记录采集

## 当前范围

支持将已保存的 `problem.invocation` 成功响应转换为标准快照，首版限于普通非交互、通过／失败题型，以及带 packageId 的包验证运行。当前样例均为本项目按[官方接口说明](https://codeforces.github.io/polygon-misc/API#probleminvocation)编写的合成数据，尚未完成真实账号导出验收。

```powershell
moon run cmd/moonverdict --target js -- import-polygon examples/polygon/invocation.json examples/polygon/context.json
```

输出为标准快照 JSON。可保存后交给现有比较命令。导入完整且没有待审查信息时退出 0；记录缺项、跳过、未结束或带验证诊断时，仍输出快照并退出 1；无法解析或材料绑定不匹配时退出 2。

context 是采集者准备的材料说明，格式见 `examples/polygon/context.json`：包含题目标识、包 ID/版本/状态/备注、运行 ID、测试集、比较条件、测试编号到内容摘要的映射，以及解法名称到源码摘要的映射。必须使用对应包版本的原始输入、答案和完整解法文件计算摘要，不能用当前工作副本冒充历史材料。

包 ID、运行 ID 和测试集必须匹配，材料必须覆盖此次调用的完整测试及解法集合。包版本来自保存的包元数据，由采集者声明；运行响应自身没有材料摘要，匹配这些编号不等于证明运行来源。

## 状态与诊断

运行矩阵缺失的格子保留为缺失。RJ 视为跳过，NO/TS 为未知，CE/FL/IL 为执行错误，均不能视为通过。未知的新判定代码拒绝导入，避免猜测含义。

MA/OK 标签映射为应通过；WA/PE/TL/ML/RE/TM/RJ 映射为应失败。TO、NR、缺失标签或尚未支持的测试集/分组标签保留为未指定，并附诊断；不能根据这些标签随意推断全部测试应该通过或失败。

包状态、包备注、invocation 的 violateTag 及每条 run 的 violateTag 均保留为待审查信息。FINISHED 仍须逐格检查；没有逐格 violateTag 也不代表包验证成功。

重复运行 ID 或一个单元格的多份记录拒绝导入，不自动挑选“最新结果”。缺少解法名称的运行不分配给其他解法，而是留下诊断和矩阵缺项。JSON 重复键拒绝；数值 ID 保留原始十进制表示，避免大整数被浮点舍入。

快照的 source 保留包、运行和测试集标识，import_notes 在后续比较中继续呈现。报告同时保留两侧 source。证据级别仍为 supplied-metadata-unverified。

## 使用你的账号采集

先在 Polygon 中选一道你有权使用的非交互题，保留对应包版本的材料。以下脚本仅读取官方 API，不编译程序、不发起验题、不创建或修改题目。

在 Polygon 设置页生成 API key/secret 后，在你自己的终端运行。脚本会通过隐藏输入在本机询问凭证，凭证不保存进输出，也不需要发送到聊天中。

第一步列出可用运行，将 `123456` 替换为题目 ID：

```powershell
python scripts/export_polygon.py --problem-id 123456 --out results/polygon-list
```

从输出中选择一个带包 ID、状态为 FINISHED 的运行，使用一个新的输出目录保存完整记录；`7890` 替换为运行 ID：

```powershell
python scripts/export_polygon.py --problem-id 123456 --invocation-id 7890 --out results/polygon-capture
```

脚本保存 packages.json、invocations.json、invocation.json、selected-package.json 和采集说明；前三项保留 API 原始响应结构。已经存在的输出目录不覆盖。请求遭拒或失败即停止，保留已写文件，不自动重试。当前脚本不支持题目 pin，也不读取其他用户的工作副本。

随后在 Polygon 中保存 selected-package.json 指向的同一包 ID、同一 revision 的题目包，放入 results/ 下。先告诉维护者本机保存目录，再核对材料并生成 context；无需分享账号凭证。未公开题目和真实导出保留在被 Git 忽略的 results/ 或 private/ 目录，不能把其中内容直接加入公开样例。

导出脚本已做假传输、假凭证的离线测试，尚未代表官方服务实测成功。真实验收还需至少两份可关联的版本记录，核对导入、比较、诊断和实际题目变化是否一致。

## 请求失败后的诊断

HTTP 400 本身不足以确定原因。早期脚本只保留状态码，没有保存错误响应内容，因而无法追溯该次失败的具体原因。修订版读取同一次失败响应的有限内容，仅输出固定的 reason 分类，并在输出目录保存 failure.json：请求方法、HTTP 状态、类别、响应采样字节数及摘要。不会保存原始错误正文、请求签名或凭证。

| reason | 表示服务端错误文字涉及的方向 |
|---|---|
| AUTH_KEY | API key |
| AUTH_SIGNATURE | 请求签名 |
| AUTH_TIME | 请求时间 |
| PIN_REQUIRED_OR_INVALID | 题目 pin；当前脚本不支持输入 pin |
| ACCESS_OR_NOT_FOUND | 权限或题目不可见 |
| RATE_LIMIT | 请求频率或尝试次数限制 |
| REQUEST_FORMAT | 方法或参数 |
| NON_JSON_OR_TRUNCATED_RESPONSE / NO_ERROR_BODY / UNCLASSIFIED | 可用响应不足，无法进一步分类 |

分类只是对错误文字的归纳，不是自动修复，也不是独立验证的故障根因。脚本不会据此更换凭证、改变接口、调整权限或自动重发请求。失败前已成功保存的记录保留。要再次采集，需由操作者明确重新运行，并选用新的输出目录。

如果终端拒绝凭证首尾空白，说明脚本在联网前就已停止；不会偷偷修改凭证后发送。排查时只需提供 reason 和失败的方法，不需要分享 key、secret 或完整错误响应。
