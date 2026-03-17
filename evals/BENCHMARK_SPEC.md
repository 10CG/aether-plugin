# Skill Benchmark Specification

> **版本**: 1.0.0 | **状态**: Active | **生效日期**: 2026-03-17

---

## 目的

本规范定义了 Aether Plugin Skill 优化升级的质量保障流程。
每次 Skill 变更必须通过基准测试对比，确保改进可量化、回归可检测。

---

## 强制流程

### 每次 Skill 优化必须执行以下步骤：

```
Step 1: 修改前基准 (Pre-change Baseline)
───────────────────────────────────────
  运行: /skill-benchmark --skill <target-skill>
  产出: evals/results/{date}-pre.yaml
  目的: 记录修改前的五维评分

Step 2: 实施修改 (Implementation)
───────────────────────────────────────
  修改 SKILL.md / references / scripts
  记录变更内容和目的

Step 3: 修改后评估 (Post-change Evaluation)
───────────────────────────────────────
  运行: /skill-benchmark --skill <target-skill>
  产出: evals/results/{date}-post.yaml
  目的: 评估修改后的五维评分

Step 4: 差异报告 (Comparison Report)
───────────────────────────────────────
  自动生成: pre vs post 对比表
  检查项:
    - 是否有维度下降?
    - 下降是否超过阈值?
    - 综合评分是否提升?

Step 5: 决策 (Decision)
───────────────────────────────────────
  ✅ 通过: 无阻断性回归 → 可提交
  ⚠️ 警告: 有维度下降但在阈值内 → 标记并继续
  ❌ 阻断: 超过阻断阈值 → 必须修复后重新评估

Step 6: 更新基准线 (Update Baseline)
───────────────────────────────────────
  确认改进有效后:
  运行: /skill-benchmark --update-baseline
  产出: 更新 evals/baseline.yaml
```

---

## 回归阈值

| 维度 | 警告阈值 | 阻断阈值 | 说明 |
|------|----------|----------|------|
| 触发准确率 | -5% | -15% | 不允许大幅降低可发现性 |
| 输出质量 | -10% | -20% | 核心体验指标 |
| 工具使用 | -5% | -15% | 安全和效率相关 |
| 错误处理 | -10% | -20% | 可靠性指标 |
| Token 效率 | +20% | +50% | 成本控制 (方向相反) |

---

## 基准线快照格式

```yaml
# evals/baseline.yaml
version: "2026-03-17"
generated_by: "skill-benchmark v1.0.0"
overall_score: 0.0  # 首次运行后填充

skills:
  aether-status:
    trigger_accuracy: 0.0
    output_quality: 0.0
    tool_usage: 0.0
    error_handling: 0.0
    token_efficiency: 0.0
    overall: 0.0
    eval_count: 0
    last_evaluated: "2026-03-17"
```

---

## 评估结果格式

```yaml
# evals/results/{date}.yaml
date: "2026-03-17"
type: "full"          # full | single-skill | pre-change | post-change
scope: "all"          # all | skill-name

results:
  aether-status:
    trigger_accuracy:
      score: 95.0
      cases_passed: 3
      cases_total: 3
      details:
        - case: "trigger-positive"
          passed: true
          notes: ""
    output_quality:
      score: 90.0
      # ...
    overall: 92.0

comparison:           # 仅在有基准线时生成
  baseline_version: "2026-03-17"
  deltas:
    aether-status:
      trigger_accuracy: +5.0
      output_quality: +2.0
      overall: +3.0
  regressions: []     # 回归列表
  improvements:       # 改进列表
    - skill: "aether-status"
      dimension: "trigger_accuracy"
      delta: +5.0
```

---

## 提交检查清单

每次 Skill 相关变更提交时，确认以下项目：

- [ ] 修改前基准已记录
- [ ] 修改后评估已运行
- [ ] 无阻断性回归
- [ ] 警告级回归已标记说明
- [ ] 评估结果已保存到 `evals/results/`
- [ ] 基准线已更新（如果有改进）
- [ ] CHANGELOG 中记录了评分变化

---

## 豁免条件

以下情况可跳过基准测试：

1. **纯格式修改**: 仅调整 Markdown 格式，不改变内容
2. **注释更新**: 仅更新注释或文档链接
3. **依赖更新**: 仅更新 requirements.yaml 中的版本号

豁免时需在提交消息中注明: `[skip-benchmark]`

---

## 与 OpenSpec 的集成

当 OpenSpec 变更涉及 Skill 修改时：

1. **proposal.md** 中添加 "Benchmark Impact" 章节
2. 实施前运行基准测试作为参考
3. 实施后的评估报告附加到归档的 Spec 中

---

**维护者**: Aether Team
**生效日期**: 2026-03-17
**审查周期**: 每季度
