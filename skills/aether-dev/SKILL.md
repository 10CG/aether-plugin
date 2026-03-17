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

## 错误处理

### Docker 构建失败

```bash
# 检查 Dockerfile 存在
if [ ! -f "Dockerfile" ]; then
  echo "错误: 当前目录未找到 Dockerfile"
  echo "修复:"
  echo "  1. 运行 /aether:init 生成 Dockerfile"
  echo "  2. 或手动创建: touch Dockerfile"
  exit 1
fi

# 构建镜像并捕获错误
if ! docker build -t "${IMAGE}" . 2>&1; then
  echo ""
  echo "错误: Docker 镜像构建失败"
  echo "常见原因:"
  echo "  - Dockerfile 语法错误（检查 FROM/RUN/COPY 指令）"
  echo "  - 依赖下载失败（检查网络连接或镜像源）"
  echo "  - COPY 的文件不存在（检查 .dockerignore 是否排除了必要文件）"
  echo "修复: docker build -t ${IMAGE} . --no-cache --progress=plain"
  exit 1
fi
```

### Docker 推送失败

```bash
# 推送镜像并捕获错误
PUSH_OUTPUT=$(docker push "${IMAGE}" 2>&1)
PUSH_EXIT=$?

if [ $PUSH_EXIT -ne 0 ]; then
  if echo "$PUSH_OUTPUT" | grep -qi "unauthorized\|authentication\|denied"; then
    echo "错误: Registry 认证失败 (${AETHER_REGISTRY})"
    echo "修复:"
    echo "  docker login ${AETHER_REGISTRY}"
    echo "  # 或检查凭据: cat ~/.docker/config.json"
  elif echo "$PUSH_OUTPUT" | grep -qi "timeout\|connection refused\|no such host"; then
    echo "错误: 无法连接到 Registry (${AETHER_REGISTRY})"
    echo "修复:"
    echo "  1. 检查 Registry 是否运行: curl -s https://${AETHER_REGISTRY}/v2/"
    echo "  2. 检查 DNS 解析: nslookup ${AETHER_REGISTRY}"
    echo "  3. 检查网络连通: ping ${AETHER_REGISTRY}"
  else
    echo "错误: 镜像推送失败"
    echo "详情: ${PUSH_OUTPUT}"
  fi
  exit 1
fi
```

### Nomad Job 提交失败

```bash
# 提交 Job 并捕获错误
JOB_OUTPUT=$(nomad job run deploy/nomad.hcl 2>&1)
JOB_EXIT=$?

if [ $JOB_EXIT -ne 0 ]; then
  if echo "$JOB_OUTPUT" | grep -qi "connection refused"; then
    echo "错误: 无法连接到 Nomad (${NOMAD_ADDR})"
    echo "修复: 检查 Nomad 服务状态或运行 /aether:setup 重新配置"
  elif echo "$JOB_OUTPUT" | grep -qi "403\|permission\|token"; then
    echo "错误: Nomad ACL 认证失败"
    echo "修复: 检查 NOMAD_TOKEN 环境变量是否正确"
  elif echo "$JOB_OUTPUT" | grep -qi "constraint"; then
    echo "错误: 没有节点满足 Job 约束条件"
    echo "修复:"
    echo "  1. 检查节点状态: nomad node status"
    echo "  2. 检查 nomad.hcl 中的 constraint 配置"
  elif echo "$JOB_OUTPUT" | grep -qi "invalid\|parse error\|syntax"; then
    echo "错误: nomad.hcl 配置文件语法错误"
    echo "修复: nomad job validate deploy/nomad.hcl"
  else
    echo "错误: Job 提交失败"
    echo "详情: ${JOB_OUTPUT}"
  fi
  exit 1
fi
```

### 网络超时

```bash
# 带超时的 API 调用
api_call() {
  local url="$1"
  local result
  result=$(curl -s --connect-timeout 5 --max-time 15 "$url" 2>&1)

  if [ $? -ne 0 ]; then
    if echo "$result" | grep -qi "timed out"; then
      echo "错误: 请求超时 ($url)"
      echo "修复:"
      echo "  1. 检查网络连通: ping $(echo $url | sed 's|https\?://||;s|/.*||;s|:.*||')"
      echo "  2. 检查防火墙规则"
      echo "  3. 增加超时重试: curl --connect-timeout 10 $url"
    else
      echo "错误: 网络请求失败 ($url)"
      echo "详情: ${result}"
    fi
    return 1
  fi

  echo "$result"
}
```

### rsync/exec 模式部署失败

```bash
# rsync 文件同步
RSYNC_OUTPUT=$(rsync -avz --exclude '.git' ./ root@${TARGET_NODE}:/opt/apps/${PROJECT}/ 2>&1)
RSYNC_EXIT=$?

if [ $RSYNC_EXIT -ne 0 ]; then
  if echo "$RSYNC_OUTPUT" | grep -qi "permission denied\|ssh"; then
    echo "错误: SSH 连接失败 (${TARGET_NODE})"
    echo "修复:"
    echo "  1. 测试 SSH: ssh root@${TARGET_NODE} 'echo ok'"
    echo "  2. 检查密钥: ls -la ~/.ssh/id_ed25519"
    echo "  3. 检查权限: chmod 600 ~/.ssh/id_ed25519"
  elif echo "$RSYNC_OUTPUT" | grep -qi "No such file\|not found"; then
    echo "错误: 目标路径不存在 (/opt/apps/${PROJECT}/)"
    echo "修复: ssh root@${TARGET_NODE} 'mkdir -p /opt/apps/${PROJECT}'"
  elif echo "$RSYNC_OUTPUT" | grep -qi "No space left"; then
    echo "错误: 目标节点磁盘空间不足"
    echo "修复: ssh root@${TARGET_NODE} 'df -h /opt/apps/'"
  else
    echo "错误: 文件同步失败"
    echo "详情: ${RSYNC_OUTPUT}"
  fi
  exit 1
fi
```

---

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
