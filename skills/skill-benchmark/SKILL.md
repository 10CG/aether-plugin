---
name: skill-benchmark
description: |
  Aether Plugin Skill 基准测试与回归检测工具。对所有 Skill 进行触发准确率、输出质量、
  工具使用、错误处理、Token 效率五维评估，与存储的基准线对比并生成差异报告。

  使用场景：Skill 优化后验证改进效果、发版前回归检测、首次建立基准线、
  查看历史评估趋势。当用户提到"基准测试"、"benchmark"、"评估 skill"、
  "skill 质量"、"回归测试"、"跑 eval"时触发。
argument-hint: "[--skill <name>] [--update-baseline] [--report-only]"
user-invocable: true
allowed-tools: Bash, Read, Write, Glob, Grep, Agent, Edit
---

# Skill Benchmark Framework

> 对 Aether Plugin 的所有 Skill 进行系统化质量评估，支持基准对比和回归检测。

## 核心概念

**基准线 (Baseline)**: 一组已确认的评估结果快照，作为后续优化的参考点。
**评估用例 (Eval Case)**: 针对特定 Skill 的测试场景，包含输入、期望输出和断言。
**回归 (Regression)**: 优化后某项指标低于基准线超过允许阈值。

---

## 执行流程

### 参数解析

```
/skill-benchmark                    → 评估所有 Skills，与基准线对比
/skill-benchmark --skill aether-status → 只评估指定 Skill
/skill-benchmark --update-baseline   → 评估后更新基准线
/skill-benchmark --report-only       → 只查看上次评估报告，不重新运行
```

### Phase 1: 加载配置

1. 读取 `evals/config.yaml` 获取评估维度、阈值和权重
2. 读取 `evals/baseline.yaml` 获取当前基准线（如果存在）
3. 确定评估范围（全部 Skills 或指定 Skill）

### Phase 2: 发现与加载 Eval Cases

```
evals/cases/{skill-name}/*.yaml
```

为每个目标 Skill 加载所有 eval case 文件。每个 case 定义：

```yaml
name: "descriptive-test-name"
skill: "aether-status"
category: "trigger-accuracy"    # 五维之一
input: "用户输入的提示词"
context:                         # 可选：模拟环境
  files: []
  env: {}
expected:
  triggered: true                # 是否应该触发此 Skill
  tools_used: ["Bash"]           # 期望使用的工具
  output_contains: ["keyword"]   # 输出应包含的关键字
  output_not_contains: []        # 输出不应包含的内容
  output_structure: "table"      # 期望的输出结构
  error_handled: false           # 是否测试错误处理
tags: ["p0", "smoke"]
```

### Phase 3: 执行评估

对每个 eval case：

1. **触发准确率 (Trigger Accuracy)**
   - 正向测试：给定输入是否正确触发目标 Skill
   - 负向测试：不相关输入是否正确跳过
   - 评估方法：检查 Skill description 与输入的语义匹配度

2. **输出质量 (Output Quality)**
   - 关键字覆盖：输出是否包含 `expected.output_contains` 中所有关键字
   - 结构检查：输出格式是否符合 `expected.output_structure`
   - 完整性：是否覆盖了用户请求的所有方面

3. **工具使用 (Tool Usage)**
   - 正确性：是否使用了 `expected.tools_used` 中指定的工具
   - 效率：是否有不必要的工具调用
   - 安全性：是否避免了危险操作

4. **错误处理 (Error Handling)**
   - 对缺失配置、网络错误、权限问题的处理
   - 错误信息的清晰度和可操作性
   - 降级策略是否合理

5. **Token 效率 (Token Efficiency)**
   - SKILL.md 加载 token 数（文件大小）
   - references/ 按需加载是否合理
   - 指令的简洁性和信息密度

### Phase 4: 基准对比

将当前评估结果与 `evals/baseline.yaml` 逐项对比：

```
╔══════════════════════════════════════════════════════════════╗
║                SKILL BENCHMARK REPORT                        ║
╚══════════════════════════════════════════════════════════════╝

📊 Overall Score: 87.3% (baseline: 82.1%, +5.2%)

┌─────────────────┬────────┬──────────┬────────┬────────┐
│ Skill           │ Score  │ Baseline │ Delta  │ Status │
├─────────────────┼────────┼──────────┼────────┼────────┤
│ aether-status   │ 92.0%  │ 88.0%    │ +4.0%  │ ✅ UP  │
│ aether-deploy   │ 85.0%  │ 85.0%    │  0.0%  │ ── OK  │
│ aether-init     │ 78.0%  │ 82.0%    │ -4.0%  │ ⚠️ DOWN│
│ ...             │        │          │        │        │
└─────────────────┴────────┴──────────┴────────┴────────┘

📈 维度详情 (aether-status)
───────────────────────────────────────────────────────────
  触发准确率:  95% (baseline: 90%, +5%)  ✅
  输出质量:    90% (baseline: 88%, +2%)  ✅
  工具使用:    92% (baseline: 85%, +7%)  ✅
  错误处理:    88% (baseline: 85%, +3%)  ✅
  Token 效率:  95% (baseline: 92%, +3%)  ✅

⚠️ 回归检测
───────────────────────────────────────────────────────────
  aether-init: 输出质量下降 4.0% (阈值: -10%) → 在阈值内
  无阻断性回归
```

### Phase 5: 报告与决策

1. 生成报告到 `evals/results/{date}.yaml`
2. 如果使用了 `--update-baseline`，确认后更新 `evals/baseline.yaml`
3. 如果检测到阻断性回归（超过阈值），明确标记并建议修复

---

## 评估方法详解

### 触发准确率评估

不需要实际运行 Skill，而是分析 Skill 的 `description` 字段：

1. 读取 SKILL.md 的 frontmatter 中 `description` 字段
2. 对每个 eval case 的 `input`，判断该描述是否能让 Claude 正确决定触发/不触发
3. 评分标准：
   - 正向用例正确触发: +1
   - 负向用例正确跳过: +1
   - 正向用例未触发: -1 (严重)
   - 负向用例误触发: -0.5

### 输出质量评估

通过静态分析 SKILL.md 的指令质量：

1. **清晰度**: 指令是否无歧义
2. **完整性**: 是否覆盖主要使用场景
3. **示例**: 是否包含足够的示例
4. **结构**: 输出格式是否有明确定义
5. **错误路径**: 是否定义了失败时的行为

### Token 效率评估

```bash
# 计算 SKILL.md token 数（近似）
wc -w skills/{skill-name}/SKILL.md

# 计算 references 总量
wc -w skills/{skill-name}/references/*.md 2>/dev/null

# 信息密度 = 覆盖的功能数 / token 数
```

参考标准（来自 references/scoring-rubric.md）。

---

## 基准线管理

### 首次建立基准线

```
/skill-benchmark --update-baseline
```

首次运行时 baseline.yaml 不存在，评估完成后自动创建。

### 更新基准线

只有在确认改进有效后才更新：

```yaml
# evals/baseline.yaml
version: "2026-03-17"
overall_score: 87.3
skills:
  aether-status:
    trigger_accuracy: 95.0
    output_quality: 90.0
    tool_usage: 92.0
    error_handling: 88.0
    token_efficiency: 95.0
    overall: 92.0
  aether-deploy:
    # ...
```

### 历史追踪

每次评估结果保存到 `evals/results/{date}.yaml`，可回溯查看趋势。

---

## 配置说明

详细的评估配置、阈值定义和评分标准见：
- `references/scoring-rubric.md` — 五维评分细则
- `evals/config.yaml` — 阈值和权重配置

---

## 与优化流程的集成

每次 Skill 优化升级必须遵循以下流程：

```
1. 修改前运行基准测试 → 记录当前状态
2. 实施优化修改
3. 修改后运行基准测试 → 与修改前对比
4. 确认无回归后 → 更新基准线
5. 提交变更（包含评估报告）
```

这个流程通过 `evals/config.yaml` 中的 `require_comparison: true` 强制执行。
