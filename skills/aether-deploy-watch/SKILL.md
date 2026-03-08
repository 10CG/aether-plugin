---
name: aether-deploy-watch
description: |
  部署监控与诊断工具。在 CI/CD 完成后自动检查 Nomad 部署状态，收集错误信息并提供修复建议。
  调用 aether-status 获取状态，专注于监控循环和错误诊断。

  使用场景："部署后检查"、"CI 成功但服务不可用"、"查看 allocation 状态"、"部署失败排查"
argument-hint: "[job-name] [--follow] [--timeout=60]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Aether 部署监控 (aether-deploy-watch)

> **版本**: 1.1.0 | **优先级**: P0

## 概述

**核心定位**：部署监控与诊断的**组合层** Skill

- 调用 `aether-status` 获取状态（基础层）
- 专注于持续监控循环
- 专注于错误模式匹配
- 专注于修复建议生成

**解决的问题**：CI 显示成功，不等于服务真正可用

---

## 与 aether-status 的关系

```
aether-status (基础层)
├── 提供核心状态查询
│   ├── 集群概览
│   ├── 服务详情
│   ├── --failed (失败详情)
│   ├── --recent (最近部署)
│   └── --logs (日志)
│
aether-deploy-watch (组合层)
├── 调用 aether-status 获取状态
├── 持续监控循环
├── 错误模式匹配
└── 修复建议生成
```

---

## 快速开始

### 基本用法

```
/aether:deploy-watch my-api
```

执行流程：
1. 调用 `/aether:status my-api` 获取当前状态
2. 分析状态（running/pending/failed）
3. 如果失败，4. 输出诊断结果

### 持续监控

```
/aether:deploy-watch my-api --follow
```

持续监控直到部署成功或明确失败。

### 自定义超时

```
/aether:deploy-watch my-api --follow --timeout=120
```

---

## 执行流程

### Phase 1: 获取状态（调用 aether-status）

```markdown
## 调用基础层 Skill

首先调用 `/aether:status my-api --failed` 获取失败信息。

如果没有失败，调用 `/aether:status my-api --recent` 获取最近部署状态。
```

**示例调用**：

```
/aether:status my-api

输出:
服务: my-api
================
Job: my-api (service, running, v3)
Allocations:
  abc12345 @ heavy-1 - running (v3)
  def67890 @ heavy-2 - failed (v3) ✗

状态: ⚠ 有失败 allocation
```

### Phase 2: 失败诊断

当发现 failed allocation 时，调用 `aether-status` 获取详情：

```bash
# 获取失败的 allocation 详情
/aether:status my-api --failed

# 获取日志
/aether:status my-api --logs
```

### Phase 3: 错误模式匹配

分析日志，匹配常见错误模式：

| 错误模式 | 正则表达式 | 可能原因 | 修复建议 |
|---------|-----------|---------|---------|
| 镜像拉取失败 | `image.*pull.*failed|failed to pull|unauthorized` | Registry auth 配置错误 | 检查 nomad job 中的 auth 配置 |
| 网络不可达 | `network.*unreachable|connection refused|timeout` | 网络策略/防火墙 | 检查 network mode 和防火墙规则 |
| 权限拒绝 | `permission denied|access denied` | 文件/目录权限 | 检查 volume 权限和用户配置 |
| 内存不足 | `OOMKilled|out of memory` | 内存限制太低 | 增加 memory 资源配置 |
| 健康检查失败 | `health check failed| unhealthy` | 服务启动失败 | 检查服务日志和健康检查配置 |
| 配置错误 | `config.*error|invalid.*config` | 配置文件问题 | 检查环境变量和配置文件 |

### Phase 4: 修复建议

根据错误类型给出具体修复建议：

```markdown
## 诊断结果

### 问题: 镜像拉取失败

**错误信息**:
```
failed to pull image forgejo.10cg.pub/my-api:abc123: unauthorized
```

**分析**:
Registry 认证失败，**可能原因**:
1. Job 文件中 auth 配置使用了错误的 secrets 名称
2. Registry token 已过期或无效
3. Cloudflare Access 保护导致认证失败

**修复建议**:

1. 检查 Nomad Job 文件中的 auth 配置
2. 验证 Secrets 配置
3. 检查 Cloudflare Access 设置

**快速修复命令**:
```bash
# 重新部署
nomad job run deploy/nomad-prod.hcl

# 然后运行
/aether:deploy-watch my-api
```
```

---

## 持续监控模式

当使用 `--follow` 参数时，进入持续监控循环：

```bash
/aether:deploy-watch my-api --follow --timeout=120

Aether 部署监控 (持续模式)
============================
Job: my-api
超时: 120 秒

[18:30:00] 检查 #1/aether:status my-api
    Allocations: 1 pending, 0 running
    状态: 等待调度...

[18:30:05] 检查 #2
    /aether:status my-api
    Allocations: 1 pending, 0 running
    状态: 等待调度...

[18:30:10] 检查 #3
    /aether:status my-api
    Allocations: 0 pending, 1 running (starting)
    状态: 服务启动中...

[18:30:15] 检查 #4
    /aether:status my-api
    Allocations: 0 pending, 1 running (healthy)
    健康检查: ✓ 通过

状态: ✓ 部署成功 (耗时: 15 秒)
```

---

## 完整输出示例

### 成功部署

```
Aether 部署监控
================
Job: my-api
时间: 2026-03-08 18:30:00

[✓] 状态检查
    /aether:status my-api
    Job: my-api (service, running, v3)
    Allocations:
      - 6c8f2a1d (running) - heavy-1 ✓
      - 7d9e3b2e (running) - heavy-2 ✓
    健康检查: 通过

状态: ✓ 部署成功
```

### 部署失败

```
Aether 部署监控
================
Job: my-api
时间: 2026-03-08 18:30:00

[!] 状态检查
    /aether:status my-api
    Job: my-api (service, running, v3)
    Allocations:
      - 6c8f2a1d (running) - heavy-1 ✓
      - 8e0f4c3f (failed)  - heavy-2 ✗

[✗] 失败诊断
    调用: /aether:status my-api --failed
    调用: /aether:status my-api --logs
    Allocation: 8e0f4c3f-abc1-def2-3ghi4
    节点: heavy-2
    Task: api
    状态: failed (exit code: 1)

    错误日志 (最后 10 行):
    ┌────────────────────────────────────────────────────────┐
    │ time="2026-03-08T18:29:55Z" level=error msg="pulling image failed" │
    │ time="2026-03-08T18:29:55Z" level=error msg="unauthorized" │
    │ time="2026-03-08T18:29:55Z" level=fatal msg="failed to pull image" │
    └────────────────────────────────────────────────────────┘

[!] 错误分析
    匹配模式: 镜像拉取失败 (unauthorized)

[→] 修复建议

    1. 检查 deploy/nomad-prod.hcl 中的 auth 配置
    2. 运行: /aether:doctor --ci 检查 CI 配置
    3. 修复后重新部署: nomad job run deploy/nomad-prod.hcl
    4. 再次监控: /aether:deploy-watch my-api

状态: ✗ 部署失败 - 需要修复

是否需要自动执行修复？ [Y/n]
```

---

## 与其他 Skills 的集成

### 在 aether-deploy 后自动调用

```markdown
## aether-deploy 中的集成

部署完成后，建议自动运行:

```bash
nomad job run deploy/nomad-prod.hcl
/aether:deploy-watch my-api --follow --timeout=60
```
```

### 与 aether-doctor 配合

```markdown
## 部署失败时的诊断流程

1. /aether:deploy-watch my-api  # 发现部署失败
2. /aether:doctor --ci           # 检查 CI 配置
3. /aether:doctor --ssh          # 检查 SSH 连接
4. 修复后重新部署
5. /aether:deploy-watch my-api --follow  # 验证修复
```

---

## 命令行等价操作

```bash
# 获取状态（等同于 aether-status）
nomad job status my-api

# 获取 allocations
nomad job allocs my-api

# 查看日志
nomad alloc logs -stderr $ALLOC_ID

# 实时监控
watch -n 5 'nomad job status my-api'
```

---

## 参考文档

- [aether-status Skill](../aether-status/SKILL.md) - 基础状态查询
- [aether-deploy Skill](../aether-deploy/SKILL.md) - 触发部署
- [aether-doctor Skill](../aether-doctor/SKILL.md) - 环境诊断

---

**Skill 版本**: 1.1.0
**最后更新**: 2026-03-08
**维护者**: 10CG Infrastructure Team
