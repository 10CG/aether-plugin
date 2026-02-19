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
---

# Aether 生产部署 (aether-deploy)

> **版本**: 0.1.0 | **优先级**: P1

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

```bash
# 检查镜像是否存在于 Registry
IMAGE="forgejo.10cg.pub/org/my-project:v1.2.3"
docker manifest inspect ${IMAGE}
```

如果镜像不存在，报错并终止。

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

## 环境变量

```bash
export NOMAD_ADDR=http://192.168.69.70:4646
export CONSUL_HTTP_ADDR=http://192.168.69.70:8500
```
