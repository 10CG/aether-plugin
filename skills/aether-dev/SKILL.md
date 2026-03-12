---
name: aether-dev
description: |
  开发环境部署与测试工具。支持手动部署分支到 dev、运行临时测试 Job、
  绕过 CI 直接部署、查看 dev 环境日志等开发阶段操作。

  使用场景："部署这个分支到 dev"、"跑个测试 job"、"手动部署到开发环境"、"查看 dev 日志"
argument-hint: "<action> [args]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
dependencies:
  cli:
    required: true
    min_version: "0.7.0"
---

# Aether 开发环境工具 (aether-dev)

> **版本**: 0.3.0 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI**

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
```

## 快速开始

### 使用场景

- 部署当前分支到 dev 环境（不经过 CI）
- 运行临时测试 Job 验证功能
- CI 故障时手动部署到 dev
- 查看 dev 环境服务日志
- 清理 dev 环境中的测试 Job

### 不使用场景

- 部署到生产 → 使用 `/aether:deploy`
- 查看集群整体状态 → 使用 `/aether:status`
- 新项目接入 → 使用 `/aether:init`

## 子命令

### 1. `deploy` — 部署到 dev

```bash
/aether:dev deploy [service-name]
```

**流程：**

1. 检测当前项目的部署配置（`deploy/nomad.hcl` + `Dockerfile`）
2. 确定部署模式（Docker / exec）
3. Docker 模式：
   - 在本地或 Runner 上构建镜像
   - 推送到 Registry（tag 使用分支名或 commit SHA）
   - 替换 nomad.hcl 中的镜像占位符
4. exec 模式：
   - 同步文件到 NFS 共享路径
5. 提交 Job 到 Nomad
6. 等待部署完成

```bash
# 实际执行的核心命令
# Docker 模式
IMAGE="forgejo.10cg.pub/${ORG}/${PROJECT}:dev-$(git rev-parse --short HEAD)"
docker build -t ${IMAGE} .
docker push ${IMAGE}
sed "s|__IMAGE__|${IMAGE}|g" deploy/nomad.hcl | nomad job run -

# exec 模式
rsync -avz --exclude '.git' ./ root@192.168.69.90:/opt/apps/${PROJECT}/
nomad job run deploy/nomad.hcl
```

**与 CI 部署的区别：**

| 维度 | CI 自动部署 | /aether:dev deploy |
|------|-----------|-------------------|
| 触发 | push 到 main | 手动，任意分支 |
| 镜像 tag | commit SHA | `dev-<short-sha>` |
| 审批 | 无 | 无 |
| 用途 | 正式 dev 部署 | 临时测试、分支验证 |

### 2. `run` — 运行临时测试 Job

```bash
/aether:dev run [--docker|--exec] <command>
```

快速在集群上运行一个一次性任务，无需手写 nomad.hcl。

**示例：**

```bash
# 在 heavy 节点上运行 Docker 容器
/aether:dev run --docker "nginx:alpine"

# 在 light 节点上运行命令
/aether:dev run --exec "/opt/apps/my-script/test.sh"

# 运行带端口映射的容器
/aether:dev run --docker "my-api:dev-abc123" --port 3000
```

**生成的临时 Job：**

```hcl
job "dev-temp-<timestamp>" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${node.class}"
    value     = "<heavy_workload|light_exec>"
  }

  group "task" {
    task "run" {
      driver = "<docker|exec>"

      config {
        image   = "<image>"     # Docker 模式
        command = "<command>"   # exec 模式
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
```

Job 名称带 `dev-temp-` 前缀，便于识别和清理。

### 3. `logs` — 查看 dev 服务日志

```bash
/aether:dev logs <service-name>
```

**流程：**

```bash
# 获取最新的 allocation ID
ALLOC_ID=$(curl -s "${NOMAD_ADDR}/v1/job/${SERVICE}/allocations" | \
  jq -r '[.[] | select(.ClientStatus == "running")] | sort_by(.CreateTime) | last | .ID')

# 获取日志
nomad alloc logs ${ALLOC_ID}

# 如果有 stderr
nomad alloc logs -stderr ${ALLOC_ID}
```

### 4. `clean` — 清理临时 Job

```bash
/aether:dev clean
```

清理所有 `dev-temp-*` 前缀的临时 Job：

```bash
# 列出所有临时 Job
curl -s "${NOMAD_ADDR}/v1/jobs" | jq -r '.[] | select(.Name | startswith("dev-temp-")) | .Name'

# 逐个停止并清除
for JOB in $(curl -s "${NOMAD_ADDR}/v1/jobs" | jq -r '.[] | select(.Name | startswith("dev-temp-")) | .Name'); do
  nomad job stop -purge ${JOB}
done
```

### 5. `restart` — 重启 dev 服务

```bash
/aether:dev restart <service-name>
```

重启服务的所有 allocation（不重新部署）：

```bash
# 获取所有 running allocation
ALLOCS=$(curl -s "${NOMAD_ADDR}/v1/job/${SERVICE}/allocations" | \
  jq -r '.[] | select(.ClientStatus == "running") | .ID')

# 逐个重启
for ALLOC in ${ALLOCS}; do
  nomad alloc restart ${ALLOC}
done
```

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
  AETHER_REGISTRY=$(yq '.endpoints.registry' ~/.aether/config.yaml)
fi

# 3. 未配置则提示
if [ -z "$NOMAD_ADDR" ]; then
  echo "请先运行 /aether:setup 配置集群"
  exit 1
fi
```

## 与其他 Skills 的关系

```
/aether:setup   → 配置集群入口（首次使用）
       ↓
开发阶段                          生产阶段
─────────                        ─────────
/aether:init    → 项目接入
/aether:dev     → 开发测试部署
/aether:status  → 状态查询        → 状态查询
                                  /aether:deploy  → 生产部署
                                  /aether:rollback → 生产回滚
```
