# Skill Benchmark Specification

> **版本**: 4.0.0 | **状态**: Active | **生效日期**: 2026-03-17

---

## 设计原则

经过 4 轮实验验证（静态评分、run_eval.py 触发测试、Agent 专家评审、AB 对比测试），
确立一条核心原则：

> **只保留能被 L3 AB 测试验证的评估方法。打分不如检查，检查不如实测。**

实验证据：
- L2 给 aether-status 打 88.8% → L3 显示 WITHOUT skill 赢了 eval-1
- L1 给 output_quality 100% (grep 到代码块) → 与实际输出质量无关
- L2 给 error_handling 92% → 从未在 L3 中验证过
- L3 揭示的真正价值点 (deploy 的 config diff + 用户确认) — L1/L2 完全无法检测

---

## 两层体系 (精简版)

```
┌─────────────────────────────────────────────────────────────┐
│  守门层: 自动化成本守卫 + 风险检查清单                         │
│  工具: ./evals/scripts/static-benchmark.sh                   │
│  成本: 零 | 耗时: <1秒 | 何时: 每次提交前                     │
│  作用: 防止 SKILL.md 膨胀 + 确认关键安全步骤不缺失            │
├─────────────────────────────────────────────────────────────┤
│  验证层: AB 对比测试                                          │
│  方法: spawn with/without skill subagent + blind comparison   │
│  成本: ~40K tokens × 2 per case | 何时: 内容变更 / 发版前     │
│  作用: 唯一能验证 "Skill 是否真的有用" 的方法                  │
└─────────────────────────────────────────────────────────────┘
```

**移除的内容**:
- ~~五维百分制评分~~ (与 L3 弱相关，产生虚假信心)
- ~~触发准确率评分~~ (Plugin Skill 无法运行时测试)
- ~~output_quality 关键字检测~~ (grep 代码块 ≠ 输出质量)
- ~~error_handling 关键字检测~~ (grep "错误" ≠ 错误处理有效)

---

## 守门层: 自动化成本守卫 + 风险检查清单

### 成本守卫 (自动化)

唯一可靠的自动化指标——防止 SKILL.md 无限膨胀：

```bash
./evals/scripts/static-benchmark.sh --skill <name>
```

| 指标 | 警告 | 阻断 |
|------|------|------|
| SKILL.md 行数增长 | +30% 或超过 400 行 | +50% 或超过 500 行 |
| references/ 总词数 | 超过 3000 词 | 超过 5000 词 |

### 风险检查清单 (人工)

修改 Skill 时，逐项确认。这些是 L3 AB 测试验证了的真正价值点：

**流程型 Skill (deploy, rollback, init, setup)**:
- [ ] 危险操作前有用户确认步骤？
- [ ] 有配置对比/diff 步骤？
- [ ] 有回滚方案或失败后的恢复指引？
- [ ] 有前置检查（CLI 存在、集群可达、配置有效）？
- [ ] 步骤是否有明确的顺序编号？

**诊断型 Skill (status, doctor, deploy-watch)**:
- [ ] 是否覆盖了用户问题的所有维度？（不遗漏子问题）
- [ ] 指令是否过度约束？（L3 证明：探索型任务中过严格的指令降低诊断深度）
- [ ] 有降级策略？（部分 API 不可达时仍能输出有用信息）
- [ ] 输出格式是否引导结构化呈现？（表格 > 纯文本）

**Hook 型 Skill (cli-guard)**:
- [ ] 拦截条件是否精确？（不误拦、不漏拦）
- [ ] 拦截信息是否可操作？（告诉用户怎么修）

---

## 验证层: AB 对比测试

### 何时运行

| 场景 | 必须 AB 测试？ |
|------|---------------|
| SKILL.md 内容重写/重构 | **是** |
| 新建 Skill | **是** |
| 错误处理/输出格式改进 | 推荐 (至少 1 个 case) |
| 发版前质量关卡 | 推荐 (每个 Skill 抽 1 case) |
| 纯格式/注释修改 | 否 `[skip-benchmark]` |

### 完整流程

```
Step 1: 编写 eval case (evals/evals.json)
────────────────────────────────────────
  {
    "prompt": "50+ 字真实任务，含 IP、路径、服务名等上下文",
    "expected_output": "预期结果的文字描述",
    "expectations": ["可验证的断言1", "断言2", ...]
  }

  原则:
  - prompt 必须是真实复杂任务，不是"部署到生产"这种短句
  - expectations 必须测试 Skill 的关键价值点
    (如 deploy: "在执行前要求用户确认")
  - 避免 trivial expectations (如 "使用了 Bash 工具")

Step 2: Spawn 2 个 subagent (限速，避免 529)
────────────────────────────────────────
  with_skill:    "先读 SKILL.md，然后执行任务"
  without_skill: "不读任何 skill，直接执行任务"
  输出保存到: workspace/iteration-N/eval-{name}/{with,without}_skill/outputs/

Step 3: 记录 timing (从 task notification 捕获)
────────────────────────────────────────
  保存 total_tokens 和 duration_ms 到 timing.json

Step 4: Grading + Blind Comparison (1 个 Agent)
────────────────────────────────────────
  - 逐条验证 expectations (PASS/FAIL + 证据)
  - 两个输出标记 A/B，盲测评分
  - Content rubric (correctness, completeness, accuracy) 1-5
  - Structure rubric (organization, formatting, usability) 1-5
  - 宣布 winner + reasoning
  保存到: grading_and_comparison.json

Step 5: 决策
────────────────────────────────────────
  WITH 赢:    Skill 有价值 → 合并
  WITHOUT 赢: Skill 可能过度约束 → 精简指令后重测
  平局:       Skill 无正面/负面影响 → 可合并
  WITH expectations 更高但 rubric 输了:
              Skill 确保关键步骤但限制了深度 → 根据任务类型决定
```

### eval case 质量标准

L3 的可靠性完全取决于 eval case 质量。差的 eval case 比没有更糟。

**好的 eval case**:
```json
{
  "prompt": "my-api 的 v1.2.3 在 dev 跑了两天没问题，镜像 forgejo.10cg.pub/10CG/my-api:v1.2.3。部署到生产，Nomad http://192.168.69.80:4646，HCL 在 deploy/nomad-prod.hcl。走标准流程。",
  "expectations": [
    "在执行部署前要求用户确认",
    "提到了配置对比或 diff 步骤",
    "提到了回滚方案"
  ]
}
```
测试的是 Skill 的**关键价值点** (安全步骤)。

**差的 eval case**:
```json
{
  "prompt": "部署到生产",
  "expectations": [
    "使用了 Bash 工具",
    "输出包含文字"
  ]
}
```
Prompt 太短 (claude -p 不触发 skill)，expectations 无区分度 (有无 skill 都会通过)。

---

## 提交规范

```
feat(plugin/deploy): 添加回滚确认步骤

守门层: 166→185 行 (+11%)，风险清单全部通过
AB 测试: WITH 5/5 vs WITHOUT 3/5, blind winner=WITH (5.0 vs 4.0)
```

如果跳过 AB 测试（小改动）:
```
fix(plugin/status): 修正 API 超时值

守门层: 475→478 行 (+0.6%)，风险清单通过
[skip-ab-test] 仅修改超时常量，非内容变更
```

---

## 已验证的基准数据

### AB 测试基准 (2026-03-17, 3 组实验)

| Skill | Eval | Expectations | Rubric Score | Winner | 关键发现 |
|-------|------|-------------|-------------|--------|---------|
| status | 集群健康 | 5/5 vs 5/5 | 4.25 vs 4.65 | WITHOUT | Skill 约束了探索深度 |
| status | 服务诊断 | 4/4 vs 3/4 | 4.50 vs 4.00 | WITH | Skill 确保日志维度不遗漏 |
| deploy | 标准部署 | 5/5 vs 3/5 | 5.00 vs 4.00 | WITH | Skill 确保 diff+确认安全步骤 |

**结论**: WITH Skill 胜率 2/3。流程型任务价值明确，探索型任务需警惕过度约束。

### 成本基准

| 配置 | 平均 tokens | 平均耗时 |
|------|------------|---------|
| With Skill | 36.6K | 146s |
| Without Skill | 38.0K | 113s |
| 差异 | -3.7% tokens | +29% 时间 |

Skill 不增加 token 成本，但执行时间略长（读 SKILL.md 的开销）。

---

## 废弃记录

以下方法经实验验证无效或产生误导，已废弃：

| 方法 | 废弃原因 | 实验证据 |
|------|---------|---------|
| 五维百分制评分 (L2 v1-v3) | 与 AB 结果弱相关，产生虚假信心 | L2=88.8% 但 L3 显示 WITHOUT 赢 |
| run_eval.py 触发测试 | Command-file 机制不适用 Plugin Skill | 0% 触发率，含详细查询 |
| output_quality 关键字检测 | grep 代码块 ≠ 输出质量 | L1=100% 与 L3 无相关性 |
| error_handling 关键字检测 | grep "错误" ≠ 错误处理有效 | 从未在 L3 中验证 |

---

## 工具清单

```
evals/
├── scripts/
│   └── static-benchmark.sh        # 守门层: 成本守卫 (行数/词数)
├── cases/                          # eval cases (YAML, 用于 L2 风险检查参考)
├── runtime/                        # 运行时测试 JSON (备用)
├── baseline.yaml                   # 历史基准快照
├── config.yaml                     # 阈值配置
├── results/                        # 历史评估结果
└── BENCHMARK_SPEC.md               # 本文档

skills/{skill}/
├── evals/evals.json                # AB 测试用例
└── {skill}-workspace/              # AB 测试工作区
    └── iteration-{N}/
        └── eval-{name}/
            ├── with_skill/outputs/
            ├── without_skill/outputs/
            ├── timing.json
            └── grading_and_comparison.json
```

---

## 版本历史

### v4.0.0 (2026-03-17)
- **重大简化**: 移除五维百分制评分体系
- 守门层精简为: 成本守卫 (自动) + 风险检查清单 (人工)
- AB 测试成为唯一的质量验证手段
- 记录废弃方法及实验证据

### v3.0.0 (2026-03-17)
- 三层体系 (L1+L2+L3)，AB 测试首次引入

### v2.0.0 (2026-03-17)
- 两层体系 (L1+L2)，记录 run_eval.py 不适用

### v1.0.0 (2026-03-17)
- 初始版本: 五维评估 + 回归阈值

---

**维护者**: Aether Team
**审查周期**: 每季度
