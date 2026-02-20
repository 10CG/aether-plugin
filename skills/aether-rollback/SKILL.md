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
---

# Aether 生产回滚 (aether-rollback)

> **版本**: 0.1.0 | **优先级**: P1

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

### Step 3: 执行回滚

```bash
# 使用 Nomad revert 命令
nomad job revert my-project <version>

# 或使用 API
curl -s -X POST "${NOMAD_ADDR}/v1/job/my-project/revert" \
  -d '{"JobID": "my-project", "JobVersion": <version>}'
```

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

## 紧急回滚（跳过确认）

如果需要最快速度回滚，可以直接指定版本：

```bash
/aether:rollback my-project --to v2
```

这将跳过版本选择步骤，直接执行回滚。

## 回滚失败处理

如果回滚后仍然不健康：

1. 检查目标版本是否真的稳定
2. 尝试回滚到更早的版本
3. 使用 `/aether:status my-project` 查看详细状态
4. 使用 `deploy-doctor` agent 诊断问题

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:setup`。

### 配置读取

```bash
# 1. 检查项目 .env
if [ -f ".env" ]; then source .env; fi

# 2. 检查全局配置
if [ -z "$NOMAD_ADDR" ] && [ -f "$HOME/.aether/config.yaml" ]; then
  NOMAD_ADDR=$(yq '.endpoints.nomad' ~/.aether/config.yaml)
  CONSUL_HTTP_ADDR=$(yq '.endpoints.consul' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```
