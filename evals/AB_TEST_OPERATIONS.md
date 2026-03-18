# Aether Skill AB 测试运维手册

> **版本**: 2.0.0 | **状态**: Active | **生效日期**: 2026-03-17
> **参考**: Aria AB_TEST_OPERATIONS.md v1.0.0 (跨项目对齐)

---

## 目的

本文档定义了 Aether Plugin Skill 的常态化 AB 测试流程。
所有 Skill 的质量验证通过 **"有 Skill 执行 vs 无 Skill 执行"** 的对比测试完成。
测试结果随时间积累，为优化决策提供数据支撑。

---

## 核心理念

### 为什么用 AB 测试而不是评分

经过 4 轮实验验证 (BENCHMARK_SPEC v1→v4)：

| 方法 | 实验结果 | 判定 |
|------|---------|------|
| 五维百分制评分 | Agent 给 88.8% → AB 显示 WITHOUT 赢 | **废弃** |
| 关键字 grep 检测 | output_quality=100% → 与实际无关 | **废弃** |
| run_eval.py 触发测试 | 0% 触发率 (机制不兼容) | **废弃** |
| 自研 regex runner (Aria 教训) | 花费 $11 → 全部回滚 | **废弃** |
| AB 对比 + blind compare | WITH 胜率 67%，发现真实价值点 | **采用** |

---

## 架构

### 目录结构

```
aether-plugin/evals/
├── AB_TEST_OPERATIONS.md        # 本文档
├── BENCHMARK_SPEC.md            # 基准测试总规范
├── OVERALL_BENCHMARK_SUMMARY.md # 综合报告 (人类可读)
│
├── ab-suite/                    # 固定测试集 (版本化)
│   ├── version.yaml             # 测试集版本 + changelog
│   ├── aether-status.json
│   ├── aether-deploy.json
│   ├── aether-doctor.json
│   ├── aether-rollback.json
│   ├── aether-init.json
│   ├── aether-deploy-watch.json
│   ├── aether-setup.json
│   ├── aether-dev.json
│   └── aether-volume.json
│
├── ab-results/                  # 历史测试结果
│   ├── YYYY-MM-DD/              # 每次完整运行
│   │   ├── summary.yaml         # 总览
│   │   ├── benchmark.json       # 机器可读 (兼容 skill-creator)
│   │   └── {skill-name}/       # 每个 Skill
│   │       └── eval-{N}-{name}/
│   │           ├── with_skill/outputs/report.md
│   │           ├── without_skill/outputs/report.md
│   │           ├── timing.json
│   │           └── grading_and_comparison.json
│   └── latest -> YYYY-MM-DD    # 指向最新
│
└── scripts/
    └── static-benchmark.sh      # 守门层: 成本守卫
```

---

## Skill 分级与测试优先级

> 借鉴 Aria Tier 分级，按 Skill 重要性决定测试频率

### Tier 1: 核心 (每次发版必测)

| Skill | 类型 | 理由 |
|-------|------|------|
| aether-deploy | 流程 | 生产部署，安全关键 |
| aether-rollback | 流程 | 生产回滚，安全关键 |
| aether-status | 诊断 | 最高频使用 |
| aether-doctor | 诊断 | 环境诊断，首次使用入口 |

### Tier 2: 辅助 (相关 Skill 修改时测)

| Skill | 类型 | 触发条件 |
|-------|------|----------|
| aether-init | 流程 | 初始化流程修改时 |
| aether-deploy-watch | 诊断 | 部署监控修改时 |
| aether-setup | 流程 | 配置流程修改时 |
| aether-dev | 流程 | dev 环境流程修改时 |
| aether-volume | 流程 | volume 管理修改时 |

### Tier 3: 特殊 (架构变更时)

| Skill | 类型 | 说明 |
|-------|------|------|
| aether-cli-guard | Hook | 不适用 AB 测试，单独验证拦截逻辑 |

### 测试频率

| 场景 | Tier 1 | Tier 2 | Tier 3 |
|------|--------|--------|--------|
| 发版前 | **必测** | 推荐 | 相关时 |
| 单 Skill 优化后 | 该 Skill | — | — |
| 框架级变更 | **必测** | **必测** | **必测** |

---

## Eval Case 编写规范

### 格式 (兼容 skill-creator + Aria 标准)

```json
{
  "skill_name": "aether-deploy",
  "version": "1.0.0",
  "evals": [
    {
      "id": 1,
      "name": "standard-prod-deploy",
      "category": "standard",
      "prompt": "50+ 字的真实复杂任务描述...",
      "expected_output": "预期结果的文字描述",
      "expectations": [
        {
          "text": "在执行部署前要求用户确认",
          "priority": "critical"
        },
        {
          "text": "提到了配置对比或 diff 步骤",
          "priority": "critical"
        },
        {
          "text": "提到了回滚方案",
          "priority": "high"
        },
        {
          "text": "使用了 nomad 或 curl 命令",
          "priority": "high"
        }
      ]
    }
  ]
}
```

### 断言优先级 (借鉴 Aria)

| 优先级 | 含义 | 影响 |
|--------|------|------|
| **critical** | Skill 的核心价值点 | 失败 = 整个 eval 判 FAIL |
| **high** | 重要但非核心 | 失败 = 降低 pass_rate 但不自动判 FAIL |

**判断标准**: 如果 WITHOUT skill 也能轻松通过 → 不应是 critical。

### 每个 Skill 需要 2 个 Eval Case

| 类型 | 目的 | 示例 |
|------|------|------|
| 标准场景 | Skill 在典型任务中的价值 | deploy: 标准生产部署 |
| 压力/边缘场景 | Skill 在复杂/紧急场景中的表现 | deploy: 紧急部署+回滚需求 |

### Prompt 编写原则

- 50+ 字，含完整上下文 (IP、端口、服务名、镜像、文件路径)
- 多步骤任务，不是一句话指令
- 包含足够信息让 WITHOUT skill 也能尝试执行
- 用中文 (匹配真实用户)

### 版本管理

```yaml
# ab-suite/version.yaml
version: "1.0.0"
created: "2026-03-17"
last_modified: "2026-03-17"
skills_covered: 9
total_eval_cases: 18
changelog:
  - version: "1.0.0"
    date: "2026-03-17"
    changes: "Initial eval suite for 9 skills"
```

**规则**: 修改 eval case → 升 MINOR 版本 → 旧数据不可直接比较。

---

## 执行流程

### 场景 1: 单 Skill 优化后验证 (最常用)

```
触发: 修改了某个 Skill 的 SKILL.md 内容
命令: /skill-benchmark --ab --skill <name>

流程:
  1. 读取 ab-suite/{skill}.json
  2. 每个 eval case spawn 2 个 subagent (with/without)
  3. Grader + Blind Comparator 评分
  4. 与 ab-results/latest/{skill}/ 比对
  5. 输出差异报告

产出: ab-results/YYYY-MM-DD/{skill}/
验收: WITH skill 胜率 ≥ 上次
```

### 场景 2: 发版前全量回归

```
触发: 准备发布新版本
命令: /skill-benchmark --full-ab --compare-last

流程:
  1. 按 Tier 分波执行 (Tier 1 先行)
  2. 每波 2 个 Skill，间隔 30s
  3. 全量 grading + comparison
  4. 汇总 summary.yaml + benchmark.json
  5. 更新 OVERALL_BENCHMARK_SUMMARY.md
  6. 与 latest 逐 Skill 比对

产出: ab-results/YYYY-MM-DD/
验收: 无 WITHOUT_BETTER verdict
```

### 场景 3: 新建 Skill 首次基线

```
触发: 创建新 Skill
命令: /skill-benchmark --ab --skill <new-skill>

流程:
  1. 编写 evals.json (至少 2 个 eval case)
  2. 执行 AB 测试
  3. 确认 WITH skill 有正向 delta
  4. 添加到 ab-suite/

验收: WITH 胜率 > 50%
```

---

## 执行细节

### Subagent Prompt 模板

**With Skill**:
```
Execute this task WITH the skill loaded:
- Skill: Read {skill_path}/SKILL.md first, then follow its instructions.
- Task: "{eval_prompt}"
- Save output to: {output_dir}/with_skill/outputs/report.md

Read the SKILL.md first and follow its instructions/format.
If API calls fail, document what you WOULD do and produce
a realistic output following the skill's format.
```

**Without Skill**:
```
Execute this task WITHOUT any skill guidance:
- Task: "{eval_prompt}"
- Save output to: {output_dir}/without_skill/outputs/report.md

Do NOT read any skill files. Use your own knowledge.
If API calls fail, produce the best output you can.
```

### Grader + Comparator 模板

```
You are Grader and Blind Comparator.

Eval prompt: "{eval_prompt}"
Output A: {with_skill_path}
Output B: {without_skill_path}

Part 1: Grade expectations (PASS/FAIL + evidence)
  Mark critical vs high priority.
  If any critical fails → verdict = FAIL.

Part 2: Blind comparison
  Content rubric (correctness, completeness, accuracy) 1-5
  Structure rubric (organization, formatting, usability) 1-5
  Winner: A, B, or TIE

Save to: grading_and_comparison.json
```

### 并发控制

| 参数 | 推荐值 | 理由 |
|------|--------|------|
| 每波 Skill 数 | 2 | 4 subagent 并行，避免 529 |
| 波次间隔 | 30s | API 限流重置 |
| Grading 并行 | 3 | Grader 较轻量 |
| 单 subagent 超时 | 5 min | 允许充分执行 |

### Timing 数据捕获

Task notification 中的 `total_tokens` 和 `duration_ms` 是唯一获取时机，
收到通知时立即保存。

---

## 结果格式

### benchmark.json (兼容 skill-creator 格式)

```json
{
  "metadata": {
    "skill_name": "aether-deploy",
    "eval_suite_version": "1.0.0",
    "timestamp": "2026-03-17T12:00:00Z",
    "evals_run": [1, 2],
    "runs_per_configuration": 1
  },
  "summary": {
    "total_evals": 2,
    "with_skill": {
      "passed": 2,
      "failed": 0,
      "pass_rate": 1.0,
      "critical_passed": 4,
      "critical_total": 4,
      "avg_duration_ms": 134246,
      "avg_tokens": 29358
    },
    "without_skill": {
      "passed": 0,
      "failed": 2,
      "pass_rate": 0.6,
      "critical_passed": 2,
      "critical_total": 4,
      "avg_duration_ms": 147139,
      "avg_tokens": 33984
    }
  },
  "evals": [
    {
      "eval_id": 1,
      "eval_name": "standard-prod-deploy",
      "category": "standard",
      "with_skill": {
        "verdict": "pass",
        "pass_rate": 1.0,
        "critical_passed": 2,
        "critical_total": 2,
        "high_passed": 3,
        "high_total": 3,
        "duration_ms": 134246,
        "tokens": 29358
      },
      "without_skill": {
        "verdict": "fail",
        "pass_rate": 0.6,
        "critical_passed": 0,
        "critical_total": 2,
        "high_passed": 3,
        "high_total": 3,
        "duration_ms": 147139,
        "tokens": 33984
      },
      "blind_comparison": {
        "winner": "WITH",
        "score_with": 5.0,
        "score_without": 4.0,
        "reasoning": "..."
      }
    }
  ]
}
```

### summary.yaml (每次运行总览)

```yaml
date: "2026-03-17"
eval_suite_version: "1.0.0"
skills_tested: 9
total_eval_cases: 18
total_subagent_runs: 36

results:
  aether-deploy:
    tier: 1
    eval_count: 2
    with_skill:
      pass_rate: 1.0
      critical_pass_rate: 1.0
      avg_tokens: 29358
      avg_duration_ms: 134246
    without_skill:
      pass_rate: 0.6
      critical_pass_rate: 0.5
      avg_tokens: 33984
      avg_duration_ms: 147139
    delta_pass_rate: +0.4
    delta_critical: +0.5
    blind_winners: ["WITH", "WITH"]
    with_win_rate: 1.0
    verdict: "WITH_BETTER"
  # ... 其余 Skills

overall:
  with_wins: 0
  without_wins: 0
  ties: 0
  with_win_rate: 0.0
  avg_delta_pass_rate: 0.0
```

### Verdict 标准

| Verdict | 条件 | 行动 |
|---------|------|------|
| **WITH_BETTER** | WITH 胜率 > 70% 且 critical 全通过 | ✅ Skill 有价值 |
| **MIXED** | WITH 胜率 40-70% | ⚠️ 分析哪类场景有价值 |
| **EQUAL** | delta < 5% 或全部 TIE | ⚠️ Skill 可能冗余 |
| **WITHOUT_BETTER** | WITHOUT 胜率 > 50% | ❌ 必须修复或移除 |

---

## 非确定性分析

> 借鉴 Aria: 同配置 3 次运行出现 100%/88.9%/77.8% 的波动

### 波动来源

| 来源 | 影响 | 应对 |
|------|------|------|
| LLM 输出非确定性 | 同 prompt 不同输出 | 多次运行取平均 |
| API 超时 | 部分查询失败 | 增大 timeout |
| 集群状态变化 | 实时数据不同 | 记录快照时间 |
| Grader 主观性 | 同输出不同评分 | 使用 critical/high 硬指标 |

### 多次运行策略

| 场景 | 运行次数 | 理由 |
|------|----------|------|
| 日常验证 | 1 次 | 成本控制，看趋势 |
| 发版前 | 2-3 次 | 取中位数，排除偶发 |
| 结果争议 | 3 次 | 建立方差数据 |

---

## 历次比对

```yaml
comparison:
  current: "2026-03-24"
  previous: "2026-03-17"
  eval_suite_version_match: true

  changes:
    improved:
      - skill: "aether-status"
        before: "MIXED (0.5)"
        after: "WITH_BETTER (1.0)"
        reason: "减少过度约束后诊断深度提升"
    regressed:
      - skill: "aether-deploy"
        before: "WITH_BETTER (1.0)"
        after: "MIXED (0.5)"
        reason: "新步骤导致执行超时"
    stable:
      - skill: "aether-doctor"
        status: "WITH_BETTER → WITH_BETTER"
```

---

## OVERALL_BENCHMARK_SUMMARY.md

每次全量运行后更新，人类可读的综合报告：

```markdown
# Aether Plugin Skills Benchmark Summary

> 测试日期: YYYY-MM-DD | Skills: 9 | Evals: 18 | 运行次数: N

## 最近运行记录

| 日期 | Skills | Evals | WITH 胜率 | 花费 | 备注 |
|------|--------|-------|----------|------|------|
| 2026-03-17 | 2 | 3 | 67% | ~$3 | 首次基线 (部分) |

## 各 Skill 结果

| Skill | Tier | Verdict | Delta | 关键发现 |
|-------|------|---------|-------|---------|
| aether-deploy | 1 | WITH_BETTER | +40% | 确保 config diff + 用户确认 |
| aether-status | 1 | MIXED | 0% | 探索型任务中 Skill 可能约束深度 |

## 关键洞察

- 流程型 Skill WITH 胜率 X%
- 诊断型 Skill WITH 胜率 X%
- Skill 平均不增加 token 成本
```

---

## 特殊处理

### aether-cli-guard (Hook)

Hook 不执行用户任务，AB 方法不适用。替代方案：
1. 模拟 CLI 未安装场景 → 验证拦截 + 可操作提示
2. 模拟 CLI 已安装场景 → 验证静默放行
单独维护，不纳入 ab-suite。

### 编排型 Skill (借鉴 Aria)

如果 Aether 未来有编排型 Skill (调用其他 Skill 的 Skill)：
- Prompt 要求"分析和规划"而非"执行"
- 测试决策质量而非执行结果

### 集群不可达

subagent 应记录尝试的命令和预期行为，生成模拟报告。
Grader 基于报告完整性评分。这仍然有效：测试的是 Skill 指令是否引导正确行为。

---

## 数据积累策略

### 短期 (1-3 个月)
- 建立首次全量基线
- 每次 Skill 优化跑单 Skill AB
- 每次发版跑 Tier 1 全量
- 积累 3-5 次全量数据

### 中期 (3-6 个月)
- 建立趋势：每个 Skill 的 WITH 胜率随时间变化
- 识别模式：哪类修改提升/降低 AB 表现
- 优化 eval cases (升版本号)
- 引入多次运行方差分析

### 长期 (6+ 个月)
- Skill 价值分级：
  - **高价值**: WITH 胜率 > 80%, delta > 30%
  - **中价值**: WITH 胜率 50-80%
  - **低价值**: WITH 胜率 < 50% → 精简或合并
- 探索 CI/CD 集成

---

## 跨项目对齐

| 规范项 | Aether | Aria | 状态 |
|--------|--------|------|------|
| 测试方法 | AB 对比 | AB 对比 | ✅ 对齐 |
| 结果格式 | benchmark.json | benchmark.json | ✅ 对齐 |
| Tier 分级 | 3 级 | 3 级 | ✅ 对齐 |
| 断言优先级 | critical/high | critical/high | ✅ 对齐 |
| 版本管理 | version.yaml | version.yaml | ✅ 对齐 |
| Verdict 标准 | 4 级 | 4 级 | ✅ 对齐 |
| 非确定性分析 | 支持 | 支持 | ✅ 对齐 |

---

## 检查清单

### Skill 优化后
- [ ] AB 测试已执行
- [ ] critical expectations 全通过
- [ ] WITH 胜率 ≥ 上次
- [ ] 结果已存入 ab-results/

### 发版前
- [ ] Tier 1 全量 AB 已执行
- [ ] 无 WITHOUT_BETTER verdict
- [ ] OVERALL_BENCHMARK_SUMMARY.md 已更新
- [ ] 与上次比对无回归

### 修改 eval case 前
- [ ] version.yaml 版本号已递增
- [ ] changelog 记录修改原因
- [ ] 理解：修改后旧数据不可比较

---

## 版本历史

### v2.0.0 (2026-03-17)
- 整合 Aria 最佳实践：Tier 分级、critical/high 断言、benchmark.json 标准格式
- 新增 OVERALL_BENCHMARK_SUMMARY.md 综合报告
- 新增非确定性分析和多次运行策略
- 新增跨项目对齐表

### v1.0.0 (2026-03-17)
- 初始版本：AB 测试流程、eval case 规范、数据积累策略

---

**维护者**: Aether Team
**审查周期**: 每季度
**跨项目对齐**: Aria AB_TEST_OPERATIONS.md v1.0.0
