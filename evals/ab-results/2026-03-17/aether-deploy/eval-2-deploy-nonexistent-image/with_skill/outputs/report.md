# Aether Deploy Report

## 部署中止 - 镜像验证失败

```
部署中止
========
服务:     payment-service
目标版本: v2.0.0-beta.3
镜像:     forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3
Nomad:    http://192.168.69.70:4646
目标节点: heavy-1, heavy-2, heavy-3
```

---

## Step 1: 参数解析

| 参数 | 值 |
|------|-----|
| 服务名 | payment-service |
| 目标版本 | v2.0.0-beta.3 |
| 镜像地址 | forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3 |
| Nomad 地址 | http://192.168.69.70:4646 |
| 目标节点 | heavy-1 (192.168.69.80), heavy-2 (192.168.69.81), heavy-3 (192.168.69.82) |

## Step 2: 镜像验证 - FAILED

在 heavy-1 节点上执行镜像验证：

```bash
$ ssh root@192.168.69.80 "docker manifest inspect forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3"
manifest unknown
```

**结果: 镜像不存在。** Registry 返回 `manifest unknown`，说明镜像 `forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3` 尚未成功构建或推送到 Registry。

这与用户提到的 "CI 日志显示可能有问题" 一致 -- CI 构建流程未成功完成，镜像未被推送到 `forgejo.10cg.pub`。

## Step 3: 当前状态检查

```bash
$ curl -s "http://192.168.69.70:4646/v1/job/payment-service"
job not found
```

Nomad 集群中当前不存在名为 `payment-service` 的 Job。这是一次全新部署（非版本升级）。

## 安全机制触发

根据 aether-deploy 安全机制第 2 条：**"镜像必须存在：部署前验证镜像"**

镜像验证失败，部署流程在 Step 2 **强制中止**。后续步骤（差异对比、用户确认、执行部署、健康检查）均未执行。

此决策基于以下风险评估：

1. **核心支付服务** -- 用户明确表示 "不能出问题"，服务关键性极高
2. **Beta 版本** -- `v2.0.0-beta.3` 是预发布版本，本身需要更谨慎的验证
3. **镜像不存在** -- 部署一个不存在的镜像会导致 Nomad allocation 立即失败，所有 3 个节点上的服务都将无法启动
4. **无现有服务可回退** -- Nomad 中不存在 payment-service 的历史版本，一旦部署失败无法自动回滚

---

## 建议操作

### 1. 排查 CI 构建失败原因

```bash
# 检查 Forgejo 上 payment-service 仓库的 Actions 运行记录
# 访问: https://forgejo.10cg.pub/10CG/payment-service/actions
# 找到 v2.0.0-beta.3 对应的构建，查看失败日志
```

### 2. 确认仓库和 Tag 是否存在

```bash
# 检查 payment-service 仓库是否存在
forgejo GET /repos/10CG/payment-service

# 检查 v2.0.0-beta.3 tag 是否存在
forgejo GET /repos/10CG/payment-service/tags
```

### 3. 手动触发构建或重新推送镜像

在 CI 问题修复后：

```bash
# 方式 1: 重新触发 CI 构建
# 在 Forgejo Actions 页面手动 re-run 失败的 workflow

# 方式 2: 本地构建并推送（如果 CI 持续有问题）
git clone https://forgejo.10cg.pub/10CG/payment-service.git
cd payment-service
git checkout v2.0.0-beta.3
docker build -t forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3 .
docker push forgejo.10cg.pub/10cg/payment-service:v2.0.0-beta.3
```

### 4. 镜像就绪后重新部署

镜像成功推送后，再次执行部署：

```bash
/aether:deploy payment-service v2.0.0-beta.3
```

### 5. 额外建议：Beta 版本生产部署注意事项

由于 `v2.0.0-beta.3` 是预发布版本，建议：
- 确认是否有通过完整的测试流程（集成测试、压力测试）
- 考虑先部署到单个节点进行金丝雀发布，确认无误后再扩展到全部 3 个节点
- 确保有回滚方案（准备好上一个稳定版本的镜像地址）

---

## 执行摘要

| 步骤 | 状态 | 说明 |
|------|------|------|
| Step 1: 解析参数 | DONE | payment-service v2.0.0-beta.3 |
| Step 2: 验证镜像 | FAILED | manifest unknown - 镜像不存在 |
| Step 3: 获取当前状态 | DONE | Nomad 中无该 Job（全新部署） |
| Step 4: 显示差异并确认 | SKIPPED | 镜像验证失败，流程中止 |
| Step 5: 执行部署 | SKIPPED | 镜像验证失败，流程中止 |
| Step 6: 健康检查 | SKIPPED | 镜像验证失败，流程中止 |
| Step 7: 输出结果 | N/A | 部署未执行 |

**最终结果: 部署中止。** 请先修复 CI 构建问题，确保镜像成功推送到 Registry 后再重新发起部署。
