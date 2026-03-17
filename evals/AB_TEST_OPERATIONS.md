# Aether Skill AB 测试运维手册

> **版本**: 1.0.0 | **状态**: Active | **生效日期**: 2026-03-17

---

## 目的

本文档定义了 Aether Plugin Skill 的常态化 AB 测试流程。
所有 Skill 的质量验证通过 **"有 Skill 执行 vs 无 Skill 执行"** 的对比测试完成。
测试结果随时间积累，为优化决策提供数据支撑。

---

## 核心理念

### 为什么用 AB 测试而不是评分

经过 4 轮实验验证 (BENCHMARK_SPEC v1→v4)，得出核心结论：

| 方法 | 实验结果 | 判定 |
|------|---------|------|
| 五维百分制评分 | Agent 给 88.8% → AB 测试显示 WITHOUT 赢 | **废弃** (虚假信心) |
| 关键字 grep 检测 | output_quality=100% → 与实际无关 | **废弃** (假信号) |
| run_eval.py 触发测试 | 0% 触发率 (机制不兼容) | **废弃** (不适用 Plugin) |
| AB 对比 + blind compare | WITH 胜率 67%，发现真实价值点 | **采用** (唯一可信) |

### AB 测试能回答的问题

- 这个 Skill 是否真的让 Agent 表现更好？
- 优化后的 Skill 是否比优化前更好？
- Skill 在哪类任务上有价值、哪类上是负担？

### AB 测试不能回答的问题

- Skill 的 description 是否准确触发 (需要 Claude Code 未来支持)
- Skill 在生产中的用户满意度 (需要用户反馈数据)

---

## 架构

### 目录结构

```
aether-plugin/
├── evals/
│   ├── AB_TEST_OPERATIONS.md     # 本文档
│   ├── BENCHMARK_SPEC.md         # 基准测试总规范
│   │
│   ├── ab-suite/                 # 固定测试集 (版本化)
│   │   ├── version.yaml          # 测试集版本号
│   │   ├── aether-status.json    # 每个 Skill 的 eval cases
│   │   ├── aether-deploy.json
│   │   ├── aether-doctor.json
│   │   ├── aether-rollback.json
│   │   ├── aether-init.json
│   │   ├── aether-deploy-watch.json
│   │   ├── aether-setup.json
│   │   ├── aether-dev.json
│   │   └── aether-volume.json
│   │
│   ├── ab-results/               # 历史测试结果
│   │   ├── YYYY-MM-DD/           # 每次完整运行
│   │   │   ├── summary.yaml      # 总览报告
│   │   │   ├── aether-status/
│   │   │   │   ├── eval-1-{name}/
│   │   │   │   │   ├── with_skill/outputs/report.md
│   │   │   │   │   ├── without_skill/outputs/report.md
│   │   │   │   │   ├── timing.json
│   │   │   │   │   └── grading_and_comparison.json
│   │   │   │   └── eval-2-{name}/
│   │   │   ├── aether-deploy/
│   │   │   └── ...
│   │   └── latest -> YYYY-MM-DD  # 指向最新一次完整运行
│   │
│   ├── scripts/
│   │   └── static-benchmark.sh   # 守门层: 成本守卫
│   │
│   ├── cases/                    # 旧版 eval cases (归档参考)
│   ├── runtime/                  # 旧版运行时测试 (归档参考)
│   ├── baseline.yaml             # 旧版基准线 (归档参考)
│   └── config.yaml               # 旧版配置 (归档参考)
```

### 固定测试集 vs 临时测试

| 类型 | 存储位置 | 用途 | 规则 |
|------|---------|------|------|
| 固定测试集 | `evals/ab-suite/` | 常态化比对 | 修改需升版本号，旧数据不可比 |
| 临时测试 | `skills/{name}/{name}-workspace/` | 开发中验证 | 随时可改，不计入基线 |

---

## Eval Case 编写规范

### 格式

```json
{
  "skill_name": "aether-deploy",
  "version": "1.0.0",
  "evals": [
    {
      "id": 1,
      "name": "standard-deploy",
      "prompt": "50+ 字的真实复杂任务描述...",
      "expected_output": "预期结果的文字描述",
      "expectations": [
        "可验证的断言1 (测试 Skill 的关键价值点)",
        "可验证的断言2"
      ]
    }
  ]
}
```

### 每个 Skill 需要 2 个 Eval Case

| 类型 | 目的 | 示例 |
|------|------|------|
| 标准场景 | 验证 Skill 在典型任务中的价值 | deploy: 标准生产部署 |
| 压力/边缘场景 | 验证 Skill 在复杂/紧急场景中的表现 | deploy: 紧急部署 + 回滚需求 |

### Prompt 编写原则

**必须**:
- 50 字以上，包含完整上下文
- 包含具体参数 (IP、端口、服务名、镜像地址、文件路径)
- 描述多步骤任务 (不是一句话指令)
- 用中文 (匹配真实用户)

**示例 (好)**:
```
my-api 的 v1.2.3 版本已经在 dev 环境跑了两天没问题，
镜像地址是 forgejo.10cg.pub/10CG/my-api:v1.2.3。现在要
部署到生产环境。Nomad 地址 http://192.168.69.80:4646，
生产 HCL 文件在 deploy/nomad-prod.hcl。帮我走标准部署流程。
```

**示例 (差)**:
```
部署到生产
```

### Expectations 编写原则

**必须测试 Skill 的关键价值点**，不是通用能力:

| 好的 Expectation | 差的 Expectation |
|-----------------|-----------------|
| "在执行部署前要求用户确认" | "使用了 Bash 工具" |
| "提到了配置对比或 diff 步骤" | "输出包含文字" |
| "提到了回滚方案" | "输出有格式" |
| "对异常给出了建议" | "执行了命令" |

**判断标准**: 如果 WITHOUT skill 也能轻松通过这个 expectation，那它没有区分度，应该替换。

### 版本管理

```yaml
# evals/ab-suite/version.yaml
version: "1.0.0"
created: "2026-03-17"
last_modified: "2026-03-17"
changelog:
  - version: "1.0.0"
    date: "2026-03-17"
    changes: "Initial eval suite for all 9 skills"
```

**修改 eval case 的规则**:
1. 修改任何 eval case → 升 MINOR 版本 (1.0.0 → 1.1.0)
2. 新版本的结果与旧版本 **不可直接比较**
3. 需在 summary.yaml 中标注 `eval_suite_version` 以追溯

---

## 执行流程

### 场景 1: 首次建立基线

```
/skill-benchmark --full-ab

流程:
  1. 读取 evals/ab-suite/ 下所有 eval cases
  2. 按波次执行 (每波 2 个 Skill，间隔 30s，避免 529)
  3. 每个 eval case spawn 2 个 subagent:
     - with_skill: "先读 SKILL.md，然后执行任务"
     - without_skill: "不读任何 skill，直接执行任务"
  4. 记录 timing (从 task notification 捕获 tokens + duration)
  5. Grading + Blind Comparison (每个 eval case 1 个 grader agent)
  6. 汇总 summary.yaml
  7. 创建 latest symlink

产出: evals/ab-results/2026-03-17/
```

### 场景 2: 优化 Skill 后验证

```
/skill-benchmark --ab --skill aether-status

流程:
  1. 只读取 evals/ab-suite/aether-status.json
  2. 执行 2 组 AB 测试
  3. 与 evals/ab-results/latest/aether-status/ 比对
  4. 输出差异报告:
     - expectations 通过率变化
     - blind comparison winner 变化
     - token/时间变化
```

### 场景 3: 发版前全量回归

```
/skill-benchmark --full-ab --compare-last

流程:
  1. 执行全量 AB 测试 (同场景 1)
  2. 自动与 evals/ab-results/latest/ 逐 Skill 比对
  3. 输出回归报告:
     - 哪些 Skill 变好了 (WITH 胜率上升)
     - 哪些 Skill 变差了 (WITH 胜率下降或 WITHOUT 开始赢)
     - 哪些持平
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
If API calls fail (cluster not reachable), document what you WOULD do
and produce a realistic output following the skill's format.
```

**Without Skill**:
```
Execute this task WITHOUT any skill guidance:
- Task: "{eval_prompt}"
- Save output to: {output_dir}/without_skill/outputs/report.md

Do NOT read any skill files. Use your own knowledge to complete the task.
If API calls fail, produce the best output you can.
```

### Grader + Comparator Prompt 模板

```
You are performing TWO roles: Grader and Blind Comparator.

## Context
Eval prompt: "{eval_prompt}"
Output A: {with_skill_output_path}
Output B: {without_skill_output_path}

## Part 1: Grade BOTH outputs against expectations
{expectations_list}
For each: PASS/FAIL with evidence.

## Part 2: Blind Comparison
Judge purely on quality. Content rubric (1-5) + Structure rubric (1-5).
Determine winner: A, B, or TIE.

## Output
Save JSON to: {grading_output_path}
```

### 并发控制

| 参数 | 推荐值 | 理由 |
|------|--------|------|
| 每波 Skill 数 | 2 | 4 个 subagent 并行，不触发 529 |
| 波次间隔 | 30s | 让 API 限流窗口重置 |
| Grading 并行 | 3 | Grader 较轻量 |
| 单 subagent 超时 | 5 min | 允许充分执行 |

### Timing 数据捕获

**关键**: Task notification 中的 `total_tokens` 和 `duration_ms` 是唯一的获取时机。
必须在收到通知时立即保存，事后无法恢复。

```json
// timing.json
{
  "with_skill": {
    "total_tokens": 49405,
    "duration_ms": 194205
  },
  "without_skill": {
    "total_tokens": 56247,
    "duration_ms": 118665
  }
}
```

---

## 结果格式

### summary.yaml (每次运行的总览)

```yaml
date: "2026-03-17"
eval_suite_version: "1.0.0"
skills_tested: 9
total_eval_cases: 18
total_subagent_runs: 36

results:
  aether-status:
    eval_count: 2
    with_skill_expectations: 9/9
    without_skill_expectations: 8/9
    blind_winner: ["WITH", "WITHOUT"]  # 每个 eval 的 winner
    with_skill_win_rate: 0.5           # 1/2
    avg_tokens_with: 40268
    avg_tokens_without: 40019
    avg_duration_with_ms: 152306
    avg_duration_without_ms: 95900
    verdict: "MIXED"  # WITH_BETTER / WITHOUT_BETTER / MIXED / EQUAL

  aether-deploy:
    eval_count: 2
    with_skill_expectations: 10/10
    without_skill_expectations: 6/10
    blind_winner: ["WITH", "WITH"]
    with_skill_win_rate: 1.0
    verdict: "WITH_BETTER"

  # ... 其余 Skills

overall:
  total_with_wins: 12
  total_without_wins: 3
  total_ties: 3
  with_skill_win_rate: 0.667
  avg_tokens_with: 36000
  avg_tokens_without: 38000
  key_findings:
    - "流程型 Skill (deploy, rollback, init) WITH 胜率 85%"
    - "诊断型 Skill (status, doctor) WITH 胜率 50%"
    - "Skill 不增加 token 成本 (平均 -5%)"
```

### 历次运行比对

```yaml
# 自动生成的比对报告
comparison:
  current: "2026-03-24"
  previous: "2026-03-17"
  eval_suite_version_match: true  # 两次用的同一版本 eval cases

  changes:
    improved:
      - skill: "aether-status"
        before: "MIXED (0.5 win rate)"
        after: "WITH_BETTER (1.0 win rate)"
        reason: "优化后减少了过度约束"

    regressed:
      - skill: "aether-deploy"
        before: "WITH_BETTER (1.0)"
        after: "MIXED (0.5)"
        reason: "新增的步骤导致执行超时"

    stable:
      - skill: "aether-doctor"
        status: "WITH_BETTER (1.0) → WITH_BETTER (1.0)"
```

---

## 特殊处理

### aether-cli-guard (Hook 型)

cli-guard 是 PreToolUse Hook，不执行用户任务，而是拦截 `aether` 命令。
AB 测试的 "with/without skill 执行任务" 方法不适用。

**替代测试方案**:
1. 模拟 CLI 未安装场景
2. 验证 Hook 是否正确拦截并给出安装指引
3. 验证 CLI 已安装时是否静默放行

此测试单独维护，不纳入 ab-suite 常态化流程。

### 集群不可达时的处理

AB 测试中 subagent 会尝试连接真实 Nomad/Consul API。如果集群不可达：

- subagent 应记录尝试的命令和预期行为
- 生成"如果可达，输出应为..."的模拟报告
- Grader 基于报告的完整性和准确性评分
- 这仍然有效：测试的是 "Skill 指令是否引导 Agent 做正确的事"

### 环境变量

AB 测试的 subagent 运行在与主 Agent 相同的环境中。确保：
- `~/.aether/config.yaml` 存在且指向有效集群
- SSH 密钥可用 (volume/setup 相关测试)
- 网络可达 Nomad/Consul API

---

## 数据积累策略

### 短期 (1-3 个月)

- 每次 Skill 优化后跑单 Skill AB 测试
- 每次发版前跑全量 AB 测试
- 积累 3-5 次全量运行数据

### 中期 (3-6 个月)

- 建立趋势图：每个 Skill 的 WITH 胜率随时间的变化
- 识别模式：哪类修改提升了 AB 表现，哪类降低了
- 优化 eval cases：基于实际使用模式更新测试集 (升版本号)

### 长期 (6+ 个月)

- 建立 Skill 价值分级：
  - **高价值**: WITH 胜率 > 80%，expectations 差异 > 30%
  - **中价值**: WITH 胜率 50-80%
  - **低价值/负价值**: WITH 胜率 < 50%
- 对低价值 Skill 考虑精简或合并
- 将 AB 测试集成到 CI/CD (当成本可控时)

---

## 与其他文档的关系

| 文档 | 职责 |
|------|------|
| **本文档** (AB_TEST_OPERATIONS.md) | AB 测试的执行流程、格式、策略 |
| BENCHMARK_SPEC.md v4.0 | 总体基准测试规范 (守门层 + 验证层) |
| CLAUDE.md | 项目级规范引用 |
| skill-benchmark/SKILL.md | AB 测试编排 Skill |

---

## 检查清单

### 首次运行前
- [ ] `evals/ab-suite/` 下所有 eval JSON 已编写
- [ ] `evals/ab-suite/version.yaml` 已创建
- [ ] `evals/ab-results/` 目录已创建
- [ ] 集群 API 可达 (或接受模拟输出)

### 每次运行后
- [ ] summary.yaml 已生成并审查
- [ ] timing.json 已保存 (从 task notification 捕获)
- [ ] grading_and_comparison.json 已保存
- [ ] latest symlink 已更新
- [ ] 异常结果已标注原因

### 修改 eval case 前
- [ ] 确认需要修改 (不可随意改动)
- [ ] version.yaml 版本号已递增
- [ ] 在 changelog 中记录修改原因
- [ ] 理解: 修改后旧数据不可直接比较

---

**维护者**: Aether Team
**审查周期**: 每季度 (与 BENCHMARK_SPEC 同步)
