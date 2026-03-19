---
name: aether-deploy
description: |
  生产环境受控部署。从 dev 提升或部署指定版本到生产。
  包含镜像验证、配置差异对比、部署确认、健康检查等步骤。

  使用场景："部署到生产"、"发布新版本"、"从 dev 提升到 prod"
argument-hint: "<service> <version>"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, AskUserQuestion
dependencies:
  cli:
    required: true
    min_version: "0.7.0"
---

# Aether 生产部署 (aether-deploy)

> **版本**: 0.4.0 | **更新**: 2026-03-19 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1

# 获取 CLI 路径
CLI=$(get_aether_cli)
```

## 快速开始

### 使用场景

- 将服务部署到生产环境
- 从开发环境提升到生产
- 部署指定版本的镜像

### 不使用场景

- 开发环境部署 → push 到 main 自动触发
- 回滚 → 使用 `/aether:rollback`

## 执行流程

### Step 1: 解析参数

```bash
/aether:deploy my-project v1.2.3
```

提取：
- 服务名: `my-project`
- 目标版本: `v1.2.3`

### Step 2: 验证镜像存在

镜像验证是部署安全门控，**不可跳过**。提供两种验证方式，按优先级尝试：

**Primary: docker CLI**

```bash
IMAGE="forgejo.10cg.pub/org/my-project:v1.2.3"
docker manifest inspect ${IMAGE}
```

**Fallback: Registry v2 API (docker CLI 不可用时)**

```bash
REGISTRY="forgejo.10cg.pub"
REPO="org/my-project"
TAG="v1.2.3"
curl -sf "https://${REGISTRY}/v2/${REPO}/manifests/${TAG}" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json"
```

如需认证，先获取 token：

```bash
TOKEN=$(curl -sf "https://${REGISTRY}/v2/token?scope=repository:${REPO}:pull" | jq -r '.token')
curl -sf "https://${REGISTRY}/v2/${REPO}/manifests/${TAG}" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  -H "Authorization: Bearer ${TOKEN}"
```

**两种方式都失败时，必须 BLOCK 部署，不允许跳过。**

### Step 2.1: 镜像验证失败诊断

当镜像验证失败时，不要仅报错终止 — 引导用户排查根因：

1. **CI Pipeline 状态**: 构建是否成功完成？
   ```bash
   # 检查最近的 CI 构建状态 (Forgejo Actions)
   curl -sf "https://${REGISTRY}/api/v1/repos/${REPO}/actions/runs?limit=5" \
     -H "Authorization: token ${FORGEJO_TOKEN}" | jq '.[0] | {status, conclusion, created_at}'
   ```

2. **Registry 认证**: Token/凭据是否有效？
   ```bash
   # 验证 registry 连通性
   curl -sf "https://${REGISTRY}/v2/" && echo "Registry reachable" || echo "Registry unreachable"
   ```

3. **网络问题**: Cloudflare Access、代理、防火墙是否阻断？
   - Cloudflare Access 可能拦截非浏览器请求 — 检查返回是否为 HTML 登录页
   - 内网 registry 可能需要 VPN 或特定网段访问

诊断完成后，向用户报告根因并建议修复方案，**不要跳过验证直接部署**。

### Step 3: 获取当前状态

```bash
# 当前运行版本
curl -s "${NOMAD_ADDR}/v1/job/my-project" | jq -r '.TaskGroups[0].Tasks[0].Config.image'
```

### Step 4: 显示差异并确认

输出：

```
部署确认
========
服务: my-project
当前版本: v1.2.2 (abc123)
目标版本: v1.2.3 (def456)

变更内容:
- 镜像: forgejo.10cg.pub/org/my-project:v1.2.2 → v1.2.3

确认部署到生产环境？ [y/N]
```

使用 AskUserQuestion 获取确认。

### Step 5: 执行部署

```bash
# 更新 Job 镜像
# 方式 1: 修改 Job spec 并提交
# 方式 2: 使用 Nomad API 直接更新

curl -s -X POST "${NOMAD_ADDR}/v1/jobs" \
  -d @<(cat deploy/nomad.hcl | sed "s|__IMAGE__|${IMAGE}|g" | nomad job run -output -)
```

### Step 6: 等待健康检查

```bash
# 轮询检查部署状态
while true; do
  STATUS=$(curl -s "${NOMAD_ADDR}/v1/job/my-project/allocations" | jq '[.[] | select(.ClientStatus == "running")] | length')
  if [ "$STATUS" -eq "$REPLICAS" ]; then
    break
  fi
  sleep 5
done

# 检查 Consul 健康
curl -s "${CONSUL_HTTP_ADDR}/v1/health/service/my-project?passing" | jq 'length'
```

### Step 7: 输出结果

```
部署成功
========
服务: my-project
版本: v1.2.3
实例: 2/2 running
健康检查: all passing

Consul DNS: my-project.service.consul
```

## 安全机制

1. **版本必须明确**: 不允许使用 `latest` 标签
2. **镜像必须存在**: 部署前验证镜像
3. **需要确认**: 显示差异后需要用户确认
4. **健康检查**: 部署后等待健康检查通过
5. **自动回滚**: 如果健康检查失败，提示使用 `/aether:rollback`

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:setup`。

### 配置读取

```bash
# 1. 检查项目配置
if [ -f ".aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' .aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' .aether/config.yaml)
  AETHER_REGISTRY=$(yq '.cluster.registry' .aether/config.yaml)
fi

# 2. 检查全局配置 (项目配置优先)
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.cluster.nomad_addr' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.cluster.consul_addr' ~/.aether/config.yaml)
  AETHER_REGISTRY=$(yq '.cluster.registry' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```
