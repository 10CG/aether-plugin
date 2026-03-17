# Skill Benchmark Specification

> **版本**: 2.0.0 | **状态**: Active | **生效日期**: 2026-03-17

---

## 目的

本规范定义了 Aether Plugin Skill 优化升级的质量保障流程。
每次 Skill 变更必须通过基准测试对比，确保改进可量化、回归可检测。

---

## 两层评估体系

基于实验验证，Aether Plugin 采用 **自动化静态分析 + Agent 专家评审** 的两层体系：

| 层级 | 方法 | 可复现 | 成本 | 适用维度 |
|------|------|--------|------|----------|
| L1: 自动化 | `static-benchmark.sh` | 100% | 零 | Token 效率、结构完整性 |
| L2: 专家评审 | Agent 五维评估 | 一致性高 | 中 | 触发准确率、输出质量、工具使用、错误处理 |

### 为什么不用运行时触发测试 (run_eval.py)?

经实验验证 (2026-03-17):
- skill-creator 的 `run_eval.py` 为 `.claude/commands/` 命令文件设计
- Plugin Skills 通过 plugin.json 注册，发现机制不同
- `claude -p` 对短查询不触发 skill (设计如此)
- 每次调用成本 ~$0.11，70 次查询 = ~$7.70
- **结论**: 当前不适用于 Plugin Skill 触发测试

### 何时重新评估运行时测试

- Claude Code 支持 plugin skill 的 `--test-trigger` 模式时
- `run_eval.py` 支持 plugin skill 注册机制时
- 成本降至 <$0.01/查询时

---

## L1: 自动化静态分析

### 工具

```bash
# 评估所有 Skills
./evals/scripts/static-benchmark.sh

# 评估单个 Skill
./evals/scripts/static-benchmark.sh --skill aether-status
```

### 自动评估维度

**Token 效率 (精确评分)**:
- 基于 SKILL.md 行数: <200=100, <300=90, <400=80, <500=70, >500=60
- 自动计算 words、references words

**结构完整性检查**:
- 输出格式定义: 是否存在格式/模板
- 代码示例: 是否包含 ``` 代码块
- 错误处理: 是否包含错误/故障处理 section
- 祈使指令: 是否使用动词引导 (使用/执行/检查)
- 场景说明: 是否有使用/不使用场景

### 适用场景

- **每次提交前**: 必须运行 L1 检查
- **CI/CD 集成**: 可作为 pre-commit hook
- **快速验证**: 修改后立即确认无结构性回归

---

## L2: Agent 专家评审

### 触发条件

- L1 检查通过后
- 涉及内容质量变更 (非纯格式)
- 发版前全量评审

### 评估维度 (五维)

| 维度 | 权重 | 评估方法 |
|------|------|----------|
| 触发准确率 | 25% | Agent 分析 description 与 eval cases 的匹配度 |
| 输出质量 | 25% | Agent 评估指令完整性、示例质量、格式清晰度 |
| 工具使用 | 20% | Agent 检查 allowed-tools 精确性和使用引导 |
| 错误处理 | 15% | Agent 检查错误场景覆盖和降级策略 |
| Token 效率 | 15% | L1 自动评分 (直接复用) |

### 评审流程

1. 启动评估 Agent (使用 /skill-benchmark skill)
2. Agent 读取 SKILL.md + eval cases + scoring-rubric.md
3. Agent 逐维度评分并生成报告
4. 与 baseline.yaml 对比
5. 输出回归/改进报告

---

## 强制流程

### 每次 Skill 优化必须执行以下步骤：

```
Step 1: 修改前
  运行 L1: ./evals/scripts/static-benchmark.sh --skill <name>
  运行 L2: /skill-benchmark --skill <name> (Agent 评审)
  产出: evals/results/{date}-{skill}-pre.yaml

Step 2: 实施修改

Step 3: 修改后
  运行 L1: ./evals/scripts/static-benchmark.sh --skill <name>
  运行 L2: /skill-benchmark --skill <name>
  产出: evals/results/{date}-{skill}-post.yaml

Step 4: 回归判定
  ✅ 通过: L1 无回归 + L2 所有维度在阈值内
  ⚠️ 警告: L1 通过 + L2 单维度下降 ≤ 警告阈值
  ❌ 阻断: L1 或 L2 任一维度超过阻断阈值

Step 5: 提交
  消息中包含评分变化和层级:
  feat(plugin/status): 优化错误处理
  Benchmark L1: token 80→70 (lines 367→475)
  Benchmark L2: error 65%→92% (+27%), overall 86.3%→88.8%

Step 6: 更新基准线
  /skill-benchmark --update-baseline
```

---

## 回归阈值

| 维度 | 警告阈值 | 阻断阈值 |
|------|----------|----------|
| 触发准确率 | -5% | -15% |
| 输出质量 | -10% | -20% |
| 工具使用 | -5% | -15% |
| 错误处理 | -10% | -20% |
| Token 效率 (L1) | +20% 行数增长 | +50% 行数增长 |

---

## 豁免条件

以下情况可跳过基准测试 (提交标注 `[skip-benchmark]`):
- 纯 Markdown 格式调整
- 注释/文档链接更新
- VERSION / plugin.json 版本号变更

---

## 工具清单

```
evals/
├── scripts/
│   ├── static-benchmark.sh    # L1: 自动化静态分析
│   └── runtime-benchmark.sh   # 运行时测试 (备用,当前不推荐)
├── cases/                     # 按 Skill 分组的 eval cases
├── runtime/                   # 运行时测试 JSON 格式
├── baseline.yaml              # 当前基准线
├── config.yaml                # 评估配置
├── results/                   # 历史评估结果
└── BENCHMARK_SPEC.md          # 本文档
```

---

## 版本历史

### v2.0.0 (2026-03-17)
- 引入两层评估体系 (L1 自动化 + L2 专家评审)
- 添加 static-benchmark.sh 自动化脚本
- 记录 run_eval.py 不适用于 plugin skills 的实验结论
- 添加运行时测试备用脚本 runtime-benchmark.sh

### v1.0.0 (2026-03-17)
- 初始版本: 五维评估体系 + 回归阈值

---

**维护者**: Aether Team
**审查周期**: 每季度
