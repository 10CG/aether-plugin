# Skill Benchmark Specification

> **版本**: 3.0.0 | **状态**: Active | **生效日期**: 2026-03-17

---

## 目的

本规范定义了 Aether Plugin Skill 优化升级的质量保障流程。
基于 AB 对比实验验证，采用三层评估体系确保 Skill 质量。

---

## 三层评估体系

### 实验验证结论 (2026-03-17)

通过 3 组 AB 测试 (6 个 subagent 执行 + 3 个 blind comparison) 验证：

| 发现 | 结论 |
|------|------|
| With Skill 胜率 2/3 | Skill 对流程型任务价值明确 (deploy +40% expectations) |
| Without Skill 赢 1/3 | Skill 可能限制探索型任务的诊断深度 |
| Token 开销持平 | Skill 不增加成本 (36.6K vs 38.0K tokens) |
| `run_eval.py` 0% 触发 | Command-file 机制不适用 Plugin Skill |

### 三层体系

```
┌─────────────────────────────────────────────────────────────┐
│  L1: 自动化静态分析 (每次提交)                                 │
│  工具: ./evals/scripts/static-benchmark.sh                   │
│  成本: 零 | 耗时: <1秒 | 可复现: 100%                        │
│  覆盖: Token 效率 + 结构完整性                                │
├─────────────────────────────────────────────────────────────┤
│  L2: Agent 专家评审 (内容变更时)                               │
│  工具: /skill-benchmark                                      │
│  成本: 中 | 耗时: ~2分钟 | 一致性: 高                        │
│  覆盖: 五维评分 (触发/输出/工具/错误/效率)                     │
├─────────────────────────────────────────────────────────────┤
│  L3: AB 对比测试 (重大变更 / 发版前)                           │
│  方法: spawn with/without skill subagent + blind comparison   │
│  成本: 高 (~40K tokens × 2 per case) | 耗时: ~5分钟/case     │
│  覆盖: Skill 实际价值验证 (expectations + rubric + winner)    │
└─────────────────────────────────────────────────────────────┘
```

---

## L1: 自动化静态分析

### 何时运行
- **每次提交前** (必须)
- CI/CD pre-commit hook

### 工具
```bash
./evals/scripts/static-benchmark.sh                    # 全部
./evals/scripts/static-benchmark.sh --skill aether-status  # 单个
```

### 自动评估项
- Token 效率: 行数/词数 → 自动评分
- 结构完整性: 输出格式、代码示例、错误处理、祈使指令、场景说明

---

## L2: Agent 专家评审

### 何时运行
- 修改 SKILL.md 内容时 (非纯格式)
- 新增/修改 eval cases 时

### 工具
```
/skill-benchmark --skill <name>
```

### 五维评估
| 维度 | 权重 | 方法 |
|------|------|------|
| 触发准确率 | 25% | Agent 分析 description 与 eval cases 匹配度 |
| 输出质量 | 25% | Agent 评估指令完整性、示例、格式 |
| 工具使用 | 20% | Agent 检查 allowed-tools 精确性 |
| 错误处理 | 15% | Agent 检查错误场景覆盖 |
| Token 效率 | 15% | L1 自动评分复用 |

### 回归阈值
| 维度 | 警告 | 阻断 |
|------|------|------|
| 触发准确率 | -5% | -15% |
| 输出质量 | -10% | -20% |
| 工具使用 | -5% | -15% |
| 错误处理 | -10% | -20% |
| Token 效率 | +20% 行增长 | +50% 行增长 |

---

## L3: AB 对比测试

### 何时运行
- 重大 Skill 重写/重构
- 发版前质量关卡
- 对 Skill 价值有疑问时

### 流程

```
Step 1: 编写 eval case
  - 真实复杂任务 prompt (50+ 字，含上下文)
  - expectations: 可验证的断言列表

Step 2: Spawn 2 个 subagent
  - with_skill: 先读 SKILL.md 再执行任务
  - without_skill: 不读任何 skill 直接执行

Step 3: 记录 timing
  - 从 task notification 捕获 total_tokens 和 duration_ms

Step 4: Grader 评分
  - 逐条验证 expectations (PASS/FAIL + 证据)

Step 5: Blind Comparator
  - 两个输出标记 A/B，不知道哪个用了 skill
  - Content rubric (correctness, completeness, accuracy) 1-5
  - Structure rubric (organization, formatting, usability) 1-5
  - 宣布 winner + reasoning

Step 6: 揭盲分析
  - 对比 with/without 的差异
  - 识别 Skill 的价值贡献点
  - 生成改进建议
```

### eval case 编写原则

skill-creator 文档明确指出简短查询不触发 skill。AB 测试的 prompt 必须：

| 要求 | 示例 |
|------|------|
| 50+ 字 | "我的 Aether 集群..." (带完整上下文) |
| 包含具体参数 | IP、端口、镜像地址、HCL 路径 |
| 多步骤任务 | "先验证镜像，再对比配置，确认后部署" |
| 有明确预期 | "如果有异常请标出并给建议" |

### 结果解读

| With Skill 赢 | Without Skill 赢 | 平局 |
|---------------|------------------|------|
| Skill 有价值 → 继续优化 | Skill 可能过度约束 → 精简指令 | Skill 无正面/负面影响 |

### 工作区结构

```
skills/{skill}/
├── evals/
│   └── evals.json              # eval cases 定义
└── {skill}-workspace/
    └── iteration-{N}/
        └── eval-{name}/
            ├── with_skill/outputs/    # with skill 的输出
            ├── without_skill/outputs/ # without skill 的输出
            ├── timing.json            # 执行时间
            └── grading_and_comparison.json  # 评分 + 盲测结果
```

---

## 强制流程总览

### 场景 → 层级映射

| 场景 | 必须 | 推荐 |
|------|------|------|
| 纯格式/注释修改 | 豁免 `[skip-benchmark]` | — |
| SKILL.md 内容微调 | L1 | L2 |
| 错误处理/输出格式改进 | L1 + L2 | — |
| Skill 重写/新建 | L1 + L2 | L3 |
| Plugin 发版前 | L1 + L2 | L3 (抽样) |

### 提交规范

```
feat(plugin/status): 优化错误处理

L1: token_efficiency 80→70 (lines 367→475)
L2: error_handling 65%→92%, overall 86.3%→88.8%
L3: AB win (with_skill 4/4 vs 3/4)  # 仅重大变更时
```

---

## 当前基准线 (2026-03-17)

### L2 基准 (五维评分)

| Skill | Overall | Trigger | Output | Tool | Error | Token |
|-------|---------|---------|--------|------|-------|-------|
| aether-doctor | 95.0 | 100 | 90 | 95 | 95 | 95 |
| aether-deploy | 91.3 | 100 | 84 | 95 | 75 | 100 |
| aether-cli-guard | 91.0 | 100 | 75 | 95 | 88 | 100 |
| aether-init | 90.8 | 100 | 80 | 90 | 95 | 90 |
| aether-setup | 90.8 | 100 | 90 | 95 | 92 | 70 |
| aether-dev | 89.3 | 100 | 84 | 85 | 95 | 80 |
| aether-deploy-watch | 88.8 | 100 | 96 | 90 | 75 | 70 |
| aether-status | 88.8 | 100 | 86 | 90 | 92 | 70 |
| aether-volume | 86.9 | 86 | 90 | 90 | 85 | 80 |
| aether-rollback | 86.8 | 83 | 84 | 90 | 80 | 100 |
| **平均** | **90.0** | **96.9** | **85.9** | **91.5** | **87.2** | **85.5** |

### L3 基准 (AB 对比)

| Skill | Eval | Expectations W/S | Winner | Score W/S |
|-------|------|-----------------|--------|-----------|
| aether-status | 集群健康 | 5/5 vs 5/5 | WITHOUT | 4.25 vs 4.65 |
| aether-status | 服务诊断 | 4/4 vs 3/4 | WITH | 4.50 vs 4.00 |
| aether-deploy | 标准部署 | 5/5 vs 3/5 | WITH | 5.00 vs 4.00 |
| **汇总** | | **14/14 vs 11/14** | **WITH 67%** | |

---

## 版本历史

### v3.0.0 (2026-03-17)
- 引入三层评估体系 (L1 + L2 + L3)
- L3 AB 对比测试：基于 skill-creator blind comparison 方法
- AB 实验数据: With Skill 胜率 67%, 流程型任务价值明确
- 完整 eval case 编写原则和工作区结构

### v2.0.0 (2026-03-17)
- 两层体系 (L1 + L2)
- 记录 run_eval.py 不适用 Plugin Skills

### v1.0.0 (2026-03-17)
- 初始版本: 五维评估 + 回归阈值

---

**维护者**: Aether Team
**审查周期**: 每季度
