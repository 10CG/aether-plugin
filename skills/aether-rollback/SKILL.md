---
name: aether-rollback
description: |
  生产环境快速回滚。列出版本历史，选择目标版本，执行回滚并验证。
  紧急场景下的快速恢复工具。

  使用场景："回滚服务"、"恢复到上一个版本"、"紧急回退"
argument-hint: "<service>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, AskUserQuestion
dependencies:
  cli:
    required: true
    min_version: "0.7.0"
---

# Aether 生产回滚 (aether-rollback)

> **版本**: 0.4.0 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
```

## 快速开始

### 使用场景

- 新版本部署后出现问题，需要快速回退
- 紧急恢复服务可用性
- 回滚到之前的稳定版本

## 执行流程

### Step 1: 获取版本历史

```bash
/aether:rollback my-project
```

查询 Nomad Job 版本历史：

```bash
curl -s "${NOMAD_ADDR}/v1/job/my-project/versions" | jq '[.Versions[] | {version: .Version, stable: .Stable, submitTime: .SubmitTime}]'
```

### Step 2: 显示版本列表

```
回滚: my-project
================
版本历史:
  v3 (当前) - abc123 - 2h ago   - 2/2 unhealthy ⚠️
  v2         - def456 - 1d ago  - 已替换 (上次稳定)
  v1         - ghi789 - 3d ago  - 已替换

推荐回滚到: v2 (最近的稳定版本)

选择回滚目标版本？ [v2 (推荐) / v1 / 输入版本号]
```

使用 AskUserQuestion 获取选择。

### Step 2.5: 确认执行

选择方案后，显示执行摘要并确认：

```
回滚确认
========
服务: my-project
当前版本: v3 (abc123) - unhealthy
目标版本: v2 (def456)
回滚方案: A (Nomad Job Revert)

确认执行回滚？ [y/N]
```

使用 AskUserQuestion 获取确认。用户未确认则终止。

### Step 3: 执行回滚

根据当前 Job 状态，选择合适的回滚方案：

#### 方案 A: Nomad Job Revert（推荐，标准路径）

适用于：Job 存在、版本历史完整、标准回滚场景。

```bash
# 使用 Nomad revert 命令
nomad job revert my-project <version>

# 或使用 API
curl -s -X POST "${NOMAD_ADDR}/v1/job/my-project/revert" \
  -d '{"JobID": "my-project", "JobVersion": <version>}'
```

这是最安全的标准路径。Nomad 保留完整的版本历史，revert 会原子性地恢复到目标版本的 Job spec。

#### 方案 B: 从 Git 重提交 Job Spec

适用于：Job 配置已损坏、当前版本的 Job spec 有问题、或版本历史不可信。

```bash
# 1. 从 Git 历史获取已知正常的 Job spec
git log --oneline -- deploy/*.nomad.hcl
git show <commit>:deploy/my-project.nomad.hcl > /tmp/my-project.nomad.hcl

# 2. 验证 Job spec 合法性
nomad job validate /tmp/my-project.nomad.hcl

# 3. Dry-run 检查差异
nomad job plan /tmp/my-project.nomad.hcl

# 4. 重新提交
nomad job run /tmp/my-project.nomad.hcl
```

注意：此方案会创建新版本（而非恢复旧版本），后续若需再次回滚，版本号会不同。

#### 方案 C: 紧急部署旧版镜像

适用于：Job 完全丢失、namespace 问题导致 revert 失败、或需要绕过 Nomad 版本管理。

```bash
# 1. 查询 Registry 中可用的镜像版本
curl -s "https://${REGISTRY}/v2/my-project/tags/list" | jq '.tags'

# 2. 确认目标镜像可用
docker pull ${REGISTRY}/my-project:<old-tag>

# 3. 修改当前 Job spec 的镜像版本并提交
# 将 image 字段改为旧版本镜像，然后:
nomad job run /tmp/my-project-emergency.nomad.hcl
```

此方案是最后手段。提交后应尽快通过正常部署流程恢复。

**方案选择指引**：

| 状况 | 推荐方案 |
|------|---------|
| 标准回滚（Job 正常，版本可用） | 方案 A |
| `nomad job revert` 报错 / Job spec 损坏 | 方案 B |
| Job 丢失 / namespace 错误 / revert 反复失败 | 方案 C |

### Step 4: 等待回滚完成

```bash
# 等待新 Allocation 启动
while true; do
  RUNNING=$(curl -s "${NOMAD_ADDR}/v1/job/my-project/allocations" | \
    jq '[.[] | select(.ClientStatus == "running" and .JobVersion == <target_version>)] | length')
  if [ "$RUNNING" -ge "$REPLICAS" ]; then
    break
  fi
  sleep 3
done
```

### Step 5: 验证健康状态

```bash
# Consul 健康检查
curl -s "${CONSUL_HTTP_ADDR}/v1/health/service/my-project?passing" | jq 'length'
```

### Step 6: 输出结果

```
回滚成功
========
服务: my-project
当前版本: v2 (def456)
实例: 2/2 running
健康检查: all passing

回滚完成，服务已恢复。
```

## 紧急回滚（快速路径）

如果需要快速回滚，可以直接指定版本跳过版本选择步骤：

```bash
/aether:rollback my-project --to v2
```

这将跳过版本列表展示，但仍需执行确认（Step 2.5）后才会执行回滚。

## 回滚失败处理

如果回滚后仍然不健康，按以下维度排查根因：

### 1. DB Schema 不兼容

新版本执行了数据库迁移（migration），旧版本代码无法操作新 schema。

```bash
# 检查最近的 migration 记录
# 确认是否有不可逆迁移（DROP COLUMN, 类型变更等）
```

对策：需要编写反向 migration 或部署兼容层，纯回滚无法解决。

### 2. 配置漂移

部署期间环境变量、Vault secrets、Consul KV 发生了变更，旧版本依赖的配置已不存在。

```bash
# 检查 Consul KV 变更
consul kv get -recurse service/my-project/

# 检查 Vault secrets（如有）
vault kv metadata get secret/my-project
```

对策：恢复旧版本的配置值，或确认新配置向后兼容。

### 3. 健康检查端点变更

新版本修改了健康检查路径（如 `/health` -> `/healthz`），回滚后 Nomad/Consul 仍在检查新路径。

```bash
# 查看当前注册的健康检查
curl -s "${CONSUL_HTTP_ADDR}/v1/agent/checks" | jq '.[] | select(.ServiceName == "my-project")'
```

对策：确认 Job spec 中的 check 定义与目标版本的端点一致。

### 4. 外部 API 版本变更

上游依赖（其他服务、第三方 API）已升级，旧版本的客户端不兼容。

对策：确认上游是否提供向后兼容，或需要同步回滚上游服务。

### 5. TLS/证书变更

部署期间轮换了证书，旧版本持有的证书引用已失效。

```bash
# 检查证书有效期
openssl s_client -connect my-project.service.consul:443 2>/dev/null | openssl x509 -noout -dates
```

对策：确认证书配置（Vault PKI 或文件路径）在回滚后仍有效。

**兜底手段**：如以上排查均无果，使用 `/aether:status my-project` 查看详细状态，或调用 `deploy-doctor` agent 进行深度诊断。

## 预防措施

在部署流程中加入以下实践，减少回滚需求和回滚失败的风险：

- **Canary 部署 + auto_revert**：在 Job spec 中配置 `canary = 1` 和 `auto_revert = true`，让 Nomad 在 canary 失败时自动回滚，无需人工介入。
- **部署前 DB Migration 验证**：确保每次 migration 都有对应的 rollback SQL，且在 staging 环境验证过反向迁移。
- **健康检查端点版本化**：使用稳定路径（如 `/health`），避免跨版本变更检查端点。
- **回滚手册维护**：每次部署后更新回滚手册，记录当前版本的外部依赖和配置变更，确保回滚时有据可查。

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:setup`。

### 配置读取

```bash
# 1. 检查项目配置
if [ -f ".aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' .aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' .aether/config.yaml)
fi

# 2. 检查全局配置
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```
