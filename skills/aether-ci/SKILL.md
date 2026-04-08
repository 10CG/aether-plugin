---
name: aether-ci
description: |
  CI/CD 状态查询与失败诊断工具。三层策略链：API → SSH 日志 → 本地复现。
  自动检测 Forgejo Actions 运行状态，展示 run 列表，读取远程日志，
  本地复现错误并提供修复建议。覆盖 15 种失败模式。

  使用场景："查看 CI 状态"、"CI 失败了"、"检查构建结果"、"CI 挂了"、
  "push 后检查"、"为什么 CI 红了"、"检查测试是否通过"、"查看 CI 日志"、
  "CI run 列表"、"读取 CI 日志"、"CI 诊断"
argument-hint: "[sha] [--watch] [--reproduce]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
dependencies:
  cli:
    required: false
    note: "通过 forgejo CLI wrapper 查询 API，本地复现使用 Go 工具链"
---

# Aether CI 状态查询与诊断 (aether-ci)

> **版本**: 2.1.0 | **优先级**: P1

## 快速开始

### 使用场景

- 查看最近 CI runs 的状态列表（表格化输出）
- CI 失败后自动诊断原因（15 种失败模式识别）
- 读取远程 CI 日志（SSH 策略链，授权开发机）
- 本地复现 CI 失败的测试/lint/docker 错误
- push 后主动检查 CI 结果

### 命令参数

| 参数 | 说明 | 示例 |
|------|------|------|
| 无参数 | 查看 HEAD 的 CI 状态 | `/aether:aether-ci` |
| `[sha]` | 指定 commit SHA | `/aether:aether-ci abc1234` |
| `--watch` | 持续监控直到 CI 完成 | `/aether:aether-ci --watch` |
| `--reproduce` | 跳过状态查询，直接本地复现 | `/aether:aether-ci --reproduce` |

---

## 执行流程

### Step 1: 检测仓库信息

从 git remote 自动提取 owner/repo：

```bash
REMOTE_URL=$(git remote get-url origin)
# 支持格式:
#   ssh://forgejo@host/OWNER/REPO.git
#   git@host:OWNER/REPO.git
#   https://host/OWNER/REPO.git
OWNER_REPO=$(echo "$REMOTE_URL" | sed 's/\.git$//' | sed -E 's#.*/([^/]+/[^/]+)$#\1#')
```

### Step 2: 查询 CI 状态

**优先方式** — 使用 `aether ci` CLI（v1.5.0+，自动处理 API 调用和认证）：

```bash
# 结构化 JSON 输出
aether ci status --json

# 按分支过滤
aether ci status --json --branch master
```

**JSON 返回字段：**

| 字段 | 含义 |
|------|------|
| `data.runs[].id` | Task ID（用于 Step 2a 日志读取） |
| `data.runs[].status` | `success` / `failure` / `running` |
| `data.runs[].name` | Job 名称 (test, lint) |
| `data.runs[].branch` | 分支名 |
| `data.runs[].commit_sha` | 触发 commit |
| `data.runs[].duration_seconds` | 耗时（秒） |

**Run list 格式化输出**

将 JSON 渲染为对齐表格，便于快速扫读：

```bash
aether ci status --json | jq -r '
  ["Run ID", "Status", "Branch", "Commit", "Duration", "Triggered"],
  (.data.runs[] | [
    .id, .status, .branch, (.commit_sha[:8]),
    (if .duration_seconds then "\(.duration_seconds)s" else "-" end),
    .name
  ]) | @tsv' | column -t -s $'\t'
```

示例输出：

```
Run ID  Status   Branch   Commit    Duration  Triggered
1042    success  master   a3f9c12b  192s      test
1041    failure  master   a3f9c12b  47s       lint
1039    success  feat/x   9d1b4e7a  210s      test
```

**Fallback** — CLI 未安装时，直接调 commit status API：

```bash
SHA="${1:-$(git rev-parse HEAD)}"
forgejo GET "/repos/${OWNER_REPO}/commits/${SHA}/status"
```

### Step 2a: 日志获取策略链

CI 失败时，按以下优先级获取日志，任一层成功即停止：

```
Tier 1: Forgejo API 原生日志（Phase 2/3，API 就绪后启用）
         → 无机器限制，任何环境均可用
         → 当前状态: 等待上游 API 支持 (Aether#8)

Tier 2: SSH via `aether ci logs`（Phase 1，当前实现）
         → 通过配置的 ci.ssh_host 读取服务端日志
         → 受限于授权开发机；CLI 内部处理 SSH 连接和超时

Tier 3: 本地复现（最终回退）
         → 在本地执行相同命令复现 CI 环境
         → 详见 Step 4
```

**Tier 2 执行流程（当前优先路径）：**

**2a-1. 探测 CLI 可用性**

```bash
aether ci status --json
```

命令成功（exit 0）→ CLI 可用，继续 2a-2。失败或未安装 → 跳至 Step 4（本地复现）。

**2a-2. 读取日志**

```bash
# 从 Step 2 获取失败 run 的 task ID
TASK_ID=$(aether ci status --json | jq -r '.data.runs[] | select(.status=="failure") | .id' | head -1)

# 读取完整日志
aether ci logs $TASK_ID

# 读取最近 200 行（通常足够定位错误）
aether ci logs $TASK_ID -n 200

# 快速定位错误行（推荐先用此命令缩小范围）
aether ci logs $TASK_ID --search "ERROR"
aether ci logs $TASK_ID --search "FAIL:"
```

**约束**:
- Skill 不得自行构造日志路径（路径规则封装在服务端）
- SSH 超时由 CLI 内部控制（默认 5s），Skill 无需额外超时设置
- 日志解压（zstd）在服务端完成，客户端不需要 zstd 二进制
- API 返回 500/429 或网络超时，统一视为"不可用"

**2a-3. 降级行为**

当 `aether ci logs` 返回非零退出码时，输出提示（非错误）：`"完整日志需在授权开发机上查看。当前进行本地复现..."`，然后继续 Step 4，不中断诊断流程。

### Step 3: 状态判断与响应

```
state == "success"  → 输出简短成功消息，结束
state == "pending"  → 输出等待消息；如有 --watch 则进入 Step 3a (轮询)
state == "failure"  → 进入 Step 4 (失败诊断)
state == "error"    → 提示 CI 系统错误，给出 Web UI 链接
total_count == 0    → 该 commit 无 CI 运行记录（可能未触发或 SHA 错误）
```

### Step 3a: 持续监控 (--watch)

当 CI 仍在 pending 时，循环轮询：

- **轮询间隔**: 45 秒
- **最大次数**: 20 次 (~15 分钟)
- **每次轮询**: 查询 `/commits/${SHA}/status`，检查 `state`
- **终止条件**: state 变为 `success`/`failure`/`error`，或超过最大次数

超时后提示可能原因：
- Runner 队列积压
- Job 卡死
- 建议直接查看 Web UI

### Step 4: 失败诊断 — 本地复现

**本地复现作为 Tier 3 回退**: 当策略链的 Tier 1/2 均不可用（API 未就绪、SSH 未配置、连接失败）时执行。也可通过 `--reproduce` 参数直接触发，跳过日志读取。

**4.1 识别失败 Job**

从 `statuses` 数组过滤 `status == "failure"` 的条目，获取 `context` 字段。

**4.2 执行对应复现命令**

| Job Context | 本地复现命令 | 工作目录 |
|-------------|-------------|---------|
| `CI / test (push)` | `go test -v -race ./...` | `aether-cli/` |
| `CI / lint (push)` | `golangci-lint run --timeout=5m` | `aether-cli/` |
| `CI / build (push)` | `docker build -f Dockerfile .` | 项目根目录 |
| 依赖异常 | `go mod download && go mod verify` | `aether-cli/` |

```bash
# 示例: test 失败时
cd aether-cli && go test -v -race ./... 2>&1

# 示例: lint 失败时
cd aether-cli && golangci-lint run --timeout=5m 2>&1
```

**4.3 注意事项**:
- CI 使用 Go 1.22，确保本地版本一致
- CI 使用 `-race` flag，本地复现也应加上
- 如果本地通过但 CI 失败，可能是环境差异 — 提示用户检查

### Step 5: 错误分析与修复建议

解析本地复现输出，匹配错误模式：

| 类别 | 错误模式 | 匹配特征 | 原因 | 建议 |
|------|----------|---------|------|------|
| compile | 编译错误 | `cannot\|undefined\|undeclared` | 代码语法/类型错误 | 修复编译错误 |
| test | 测试失败 | `--- FAIL:` | 测试断言不通过 | 定位失败测试，修复逻辑 |
| test | 数据竞争 | `DATA RACE` | 并发安全问题 | 添加同步机制 |
| test | 测试超时 | `test timed out after\|context deadline` | 单测或集成测试超时 | 优化性能或增加 `-timeout` |
| lint | Lint 错误 | 文件名:行号:列号 格式 | 代码风格/质量问题 | 按 lint 建议修复 |
| lint | Lint 超时 | `deadline exceeded.*golangci` | golangci-lint 超时 | 增加 `--timeout` 或排查大文件 |
| dep | 依赖缺失 | `missing go.sum entry\|go mod download` | Go module 问题 | 运行 `go mod tidy` |
| dep | 依赖安装失败 | `npm ERR!\|pip.*error\|apt-get.*Unable` | 包管理器失败 | 检查包名、版本、网络 |
| docker | Docker 构建失败 | `docker: Error\|COPY failed\|cannot connect to.*Docker` | Dockerfile 或 daemon 问题 | 检查 Dockerfile 语法和 Docker 服务 |
| infra | Job 超时 | `panic: test timed out\|killed.*timeout\|Job was cancelled` | CI runner 强制终止 | 检查 runner 资源，分拆耗时任务 |
| infra | Runner 离线 | `runner.*offline\|no suitable runner\|Job timed out` | 无可用 runner | 检查 runner 状态，联系 infra 团队 |
| config | Secret/配置缺失 | `secret.*not found\|variable.*undefined\|env.*not set` | 环境变量未配置 | 检查 CI secrets 和 Nomad Variables |
| config | 网络超时 | `dial tcp.*i/o timeout\|TLS handshake timeout` | 外部网络不可达 | 检查代理配置和外部服务可用性 |
| config | Registry 认证失败 | `unauthorized.*registry\|authentication required\|403 Forbidden.*pull` | Registry token 过期 | 刷新 registry credentials |
| resource | OOM/资源耗尽 | `signal: killed\|out of memory\|cannot allocate` | 内存不足 | 降低并发度，检查 runner 内存限制 |

---

## 输出格式

### 成功

```
CI 状态: ✓ 通过
Commit: abc1234 — "feat: add volume backup"
Jobs: 2/2 passed (test: 3m12s, lint: 1m45s)
链接: https://forgejo.10cg.pub/10CG/Aether/actions/runs/161
```

### 失败 (含诊断)

```
CI 诊断报告
Commit: abc1234 — "feat: add volume backup"
状态: ✗ 失败 (1/2 jobs failed)
失败 Job: CI / test (push) | 耗时: 12m27s | 类别: test failure

--- FAIL: TestVolumeCreate (0.05s)
    manager_test.go:45: expected volume "data" to exist, got nil

修复建议: 检查 internal/volume/manager.go 中 volume 创建逻辑
```

---

## 补充信息: Actions Tasks API (CLI Fallback)

当 `aether ci` CLI 不可用时，直接调用 actions/tasks 端点并渲染 run list：

```bash
TASKS=$(forgejo GET "/repos/${OWNER_REPO}/actions/tasks?limit=5&page=1")
STATUS=$?

if [ $STATUS -ne 0 ] || echo "$TASKS" | jq -e '.workflow_runs == null' > /dev/null 2>&1; then
  echo "CI run list 不可用: API 返回异常 (可能是 500/429/超时)"
  echo "请检查 forgejo 连通性或直接访问 Web UI"
fi

echo "$TASKS" | jq -r '
  ["Run ID", "Status", "Branch", "Commit", "Triggered"],
  (.workflow_runs[] | [
    (.run_number | tostring), .status, (.head_sha[:8]),
    .display_title[:40], .name
  ]) | @tsv' | column -t -s $'\t'
```

**错误处理规则**:

| 响应 | 行为 |
|------|------|
| 非 200 (含 500/429/timeout) | 输出"不可用"提示，不中断主流程 |
| `workflow_runs` 字段缺失 | 视为 API 异常，同上 |
| 空列表 | 输出"无近期 CI 运行记录" |

**注意**: 必须同时提供 `limit` 和 `page` 参数，否则返回全部记录。

**返回的 workflow_runs 字段：**

| 字段 | 含义 |
|------|------|
| `run_number` | 运行编号（同一次 push 的所有 job 共享） |
| `name` | Job 名称 (test, lint) |
| `status` | success / failure / cancelled / skipped |
| `url` | 完整 Web UI 链接 (绝对 URL) |
| `display_title` | Commit 信息 |
| `head_sha` | 触发 commit SHA |
| `created_at` | 创建时间 |

---

## 前置条件: API 配置

```bash
# 必需的环境变量（forgejo CLI wrapper 自动使用）
FORGEJO_API=https://forgejo.10cg.pub/api/v1    # Forgejo API 基地址
FORGEJO_TOKEN=<your-token>                      # API 认证 token
CF_ACCESS_CLIENT_ID=<cloudflare-access-id>      # Cloudflare Access 认证
CF_ACCESS_CLIENT_SECRET=<cloudflare-access-secret>
```

检测：如果环境变量未设置，提示用户参考 `/aether:aether-setup` 配置。

验证连通性：
```bash
forgejo GET "/repos/10CG/Aether" | jq '.full_name'
# 预期输出: "10CG/Aether"
```

---

## 与其他 Skills 的关系

```
aether-ci (CI 状态层)
    │
    ├── → aether-deploy (部署前检查 CI 状态)
    ├── → aether-deploy-watch (部署后监控 — 互补关系)
    └── ← aether-doctor (诊断 CI 配置问题)
```

**与 deploy-watch 的区别**:
- `aether-ci`: 关注 CI Pipeline 本身 (构建/测试/lint)
- `aether-deploy-watch`: 关注部署后的 Nomad 运行状态

---

## 故障处理

| 错误 | 原因 | 修复 |
|------|------|------|
| `forgejo: command not found` | CLI wrapper 未安装 | 检查 PATH 包含 `/home/dev/.npm-global/bin` |
| API 返回 401/403 | Token 过期或 CF Access 失效 | 刷新 `FORGEJO_TOKEN` 和 CF 凭据 |
| API 返回 404 | 仓库路径错误 | 检查 git remote，确认 owner/repo 正确 |
| `total_count: 0` | 该 commit 无 CI 记录 | 确认 commit 已 push 且触发了 CI |
| 本地复现结果与 CI 不同 | Go 版本或环境差异 | 对齐 Go 版本 (CI: 1.22)，加 `-race` flag |
| `jq: command not found` | jq 未安装 | `apt install jq` |

---

## 自动触发: Push 后自动监控

### PostToolUse Hook (`ci-watch-hook.sh`)

`scripts/ci-watch-hook.sh` 检测 `git push` → 写入 `.aether/ci-watch.state` → systemMessage 触发 CronCreate 轮询。

```
git push → Hook 检测 → CronCreate (每 60s 轮询)
  → success: 通知 + CronDelete + /aether:deploy-watch
  → failure: 诊断 + CronDelete
  → 15 次超时: 警告 + CronDelete
```

轮询使用 `aether ci status --json` 查询状态，终态时 CronDelete 清理。
多次 push 自动 CronDelete 旧任务并启动新轮询。会话结束时 cron 自动销毁。

---

## Related Issues

- [aether-plugin#7](https://forgejo.10cg.pub/10CG/aether-plugin/issues/7) — CI 日志读取 (Phase 1: SSH via CLI 完成; Phase 2/3: Forgejo API 待就绪)
- [Aether#8](https://forgejo.10cg.pub/10CG/Aether/issues/8) — Forgejo API 上游跟踪（Tier 1 日志策略的前置依赖）
- [US-024](../../../docs/requirements/user-stories/US-024.md) — `aether ci` CLI 命令

---

**Skill 版本**: 2.1.0
**最后更新**: 2026-04-08
**维护者**: 10CG Infrastructure Team
