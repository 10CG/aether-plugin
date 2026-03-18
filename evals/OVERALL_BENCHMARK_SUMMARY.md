# Aether Plugin Skills Benchmark Summary

> **测试日期**: 2026-03-17 | **Skills**: 9 | **Evals**: 18 | **Subagent 运行**: 36 | **Grading**: 18

---

## 总览

| 指标 | 数值 |
|------|------|
| WITH Skill 胜 | 8 / 18 (44%) |
| WITHOUT Skill 胜 | 7 / 18 (39%) |
| 平局 | 1 / 18 (6%) |
| 未评分 | 2 / 18 (11%) |
| **WITH 胜率 (已评分)** | **50%** |

---

## 各 Skill 结果

| Skill | Tier | e1 Winner | e2 Winner | Verdict | 关键发现 |
|-------|------|-----------|-----------|---------|---------|
| **aether-init** | 2 | WITH | WITH | **WITH_BETTER** | 两阶段确认流 + 冲突处理是核心价值 |
| **aether-dev** | 2 | WITH | WITH | **WITH_BETTER** | 实际执行完整部署, 忠实的 run/logs/clean 流程 |
| **aether-deploy** | 1 | WITH | WITHOUT | MIXED | 标准流程 WITH 赢 (安全步骤), 异常场景 WITHOUT 更深入 |
| **aether-rollback** | 1 | WITH | WITHOUT | MIXED | 用户确认是 WITH 核心价值, 复杂诊断 WITHOUT 更全面 |
| **aether-doctor** | 1 | TIE | WITH | MIXED | SSH 根因分析 WITH 更准, 全面诊断两者持平 |
| **aether-deploy-watch** | 2 | WITHOUT | WITH | MIXED | WITH 覆盖用户指定问题, WITHOUT 发现更多额外问题 |
| **aether-volume** | 2 | WITH | WITHOUT | MIXED | WITH 发现幂等性 bug, WITHOUT 调查更彻底 |
| **aether-status** | 1 | WITHOUT | WITHOUT | **WITHOUT_BETTER** | Skill 约束探索深度, WITHOUT 更深入 |
| **aether-setup** | 2 | WITHOUT | WITHOUT | **WITHOUT_BETTER** | **Skill 有 bug**: 错误的 config schema + 配置路径 |

---

## 核心发现

### 1. Skill 价值按类型分化

```
文件生成型 (init, dev):     WITH 100% 胜率
  → 两阶段流程、模板系统、占位符替换是不可替代的价值

流程安全型 (deploy, rollback): WITH 50% 胜率
  → 用户确认、config diff、安全检查有价值
  → 但异常/复杂场景中 Skill 可能约束诊断深度

诊断探索型 (status, doctor):  WITH 25% 胜率
  → WITHOUT 通常挖得更深
  → 但 WITH 在系统化步骤和根因分析上有优势

配置工具型 (setup):          WITH 0% 胜率
  → Skill 自身有 bug, 反而误导了 Agent
```

### 2. 发现了 3 个真实 Bug

| Bug | Skill | 严重性 |
|-----|-------|--------|
| config schema 用 `endpoints.*` 而非 `cluster.*` | aether-setup | **高** — 生成错误配置 |
| 项目配置写 `.env` 而非 `.aether/config.yaml` | aether-setup | **高** — 不符合配置优先级 |
| volume create 缺少幂等性检查,重复创建 host_volume | aether-volume (CLI) | **中** — 功能性 bug |

### 3. Token 成本分析

| 配置 | 平均 tokens | 平均耗时 |
|------|------------|---------|
| With Skill | 35.5K | 195s |
| Without Skill | 30.4K | 152s |
| 差异 | +17% | +28% |

Skill 增加了约 17% 的 token 成本 (读 SKILL.md + references 的开销)。

---

## 运行记录

| 日期 | Skills | Evals | WITH 胜率 | Bugs 发现 | 备注 |
|------|--------|-------|----------|-----------|------|
| 2026-03-17 | 9 | 18 | 50% | 3 | 首次全量基线 |

---

## 行动建议

### P0: 修复 Bug
- [ ] 修复 aether-setup config schema (endpoints → cluster)
- [ ] 修复 aether-setup 项目配置路径 (.env → .aether/config.yaml)
- [ ] 修复 aether-volume CLI 幂等性检查

### P1: 优化低表现 Skill
- [ ] aether-status: 减少约束,给 Agent 更多探索空间
- [ ] aether-setup: 修复 bug 后重新 AB 测试

### P2: 保持高表现 Skill
- [ ] aether-init: 保持两阶段流程不变
- [ ] aether-dev: 保持 subcommand 结构不变

### P3: 混合型 Skill 优化方向
- [ ] deploy/rollback: 保留安全步骤, 在异常路径增加诊断灵活性
- [ ] deploy-watch: 确保覆盖用户明确提到的问题
- [ ] volume: 添加 dry-run 幂等性提示

---

**最后更新**: 2026-03-17
**下次全量测试**: 修复 setup bug 后
