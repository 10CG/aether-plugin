---
name: aether-ci
description: |
  CI/CD 状态查询与失败诊断工具。自动检测 Forgejo Actions 运行状态，
  获取失败信息，本地复现错误并提供修复建议。

  使用场景："查看 CI 状态"、"CI 失败了"、"检查构建结果"、"CI 挂了"、
  "push 后检查"、"为什么 CI 红了"、"检查测试是否通过"
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

> **版本**: 1.0.0 | **优先级**: P1

## 快速开始

### 使用场景

- 查看最近一次 CI 运行状态
- CI 失败后自动诊断原因
- 本地复现 CI 失败的测试/lint 错误
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

使用 commit status API 获取聚合状态：

```bash
SHA="${1:-$(git rev-parse HEAD)}"

# 聚合状态（去重，每个 context 只保留最新）
forgejo GET "/repos/${OWNER_REPO}/commits/${SHA}/status"
```

**返回字段解读：**

| 字段 | 含义 | 值 |
|------|------|-----|
| `state` | 聚合状态 | `pending` / `success` / `failure` / `error` |
| `total_count` | 检查项总数 | 通常 2 (test + lint) |
| `statuses[].context` | Job 名称 | `CI / test (push)`, `CI / lint (push)` |
| `statuses[].status` | 单项状态 | `pending` / `success` / `failure` |
| `statuses[].description` | 耗时描述 | `Failing after 12m27s` |
| `statuses[].target_url` | 运行链接 (相对路径) | `/10CG/Aether/actions/runs/160/jobs/0` |

**注意**: `target_url` 是相对路径，需要拼接 Forgejo 基地址：
```
https://forgejo.10cg.pub${target_url}
```

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

**为什么本地复现而非拉日志**: Forgejo 11.0.6 没有 job 日志 API 端点。但 CI 命令可在本地执行，输出更丰富且 AI 可直接分析。

**4.1 识别失败 Job**

从 `statuses` 数组过滤 `status == "failure"` 的条目，获取 `context` 字段。

**4.2 执行对应复现命令**

| Job Context | 本地复现命令 | 工作目录 |
|-------------|-------------|---------|
| `CI / test (push)` | `go test -v -race ./...` | `aether-cli/` |
| `CI / lint (push)` | `golangci-lint run --timeout=5m` | `aether-cli/` |

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

| 错误模式 | 匹配特征 | 原因 | 建议 |
|----------|---------|------|------|
| 测试失败 | `--- FAIL:` | 测试断言不通过 | 定位失败测试，修复逻辑 |
| 编译错误 | `cannot\|undefined\|undeclared` | 代码语法/类型错误 | 修复编译错误 |
| 数据竞争 | `DATA RACE` | 并发安全问题 | 添加同步机制 |
| Lint 错误 | 文件名:行号:列号 格式 | 代码风格/质量问题 | 按 lint 建议修复 |
| 超时 | `timeout\|deadline exceeded` | 测试/lint 超时 | 优化性能或增加超时 |
| 依赖缺失 | `missing go.sum entry` | Go module 问题 | 运行 `go mod tidy` |

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

```markdown
## CI 诊断报告

**Commit**: abc1234 — "feat: add volume backup"
**状态**: ✗ 失败 (1/2 jobs failed)
**链接**: https://forgejo.10cg.pub/10CG/Aether/actions/runs/160

### 失败 Job: CI / test (push)

**耗时**: 12m27s
**错误类型**: 测试失败

**本地复现输出** (关键段落):

--- FAIL: TestVolumeCreate (0.05s)
    manager_test.go:45: expected volume "data" to exist, got nil
FAIL    github.com/10CG/aether-cli/internal/volume  0.312s

**修复建议**:
1. 检查 `internal/volume/manager.go` 中 volume 创建逻辑
2. 确认测试 fixture 是否正确初始化
3. 修复后运行 `cd aether-cli && go test -v -race ./internal/volume/...` 验证
```

---

## 补充信息: Actions Tasks API

除 commit status API 外，可用 actions/tasks 获取更多运行信息：

```bash
forgejo GET "/repos/${OWNER_REPO}/actions/tasks?limit=5&page=1"
```

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

`scripts/ci-watch-hook.sh` 在每次 Bash 工具执行后运行，检测 `git push` 命令。

**触发条件**: Bash 命令包含 `git push` 且非 `--dry-run`
**自动操作**: 提取 SHA/repo → 写入状态文件 → 输出 systemMessage → Claude 启动 CronCreate 轮询

```
git push → Hook 检测 → systemMessage → Claude 创建 CronCreate
  → 每 60s 轮询 commit status API
  → pending: 继续等待
  → success: 通知用户，CronDelete
  → failure: 自动 --reproduce 诊断
```

### Hook 触发后 Claude 应执行的操作

1. 通知用户 CI 监控已激活
2. 使用 CronCreate 创建轮询任务（见下节）
3. 继续当前对话，不阻塞用户

---

## CronCreate 自动轮询

当 Hook 触发或用户指定 `--watch` 时，使用 CronCreate 创建轮询任务。

### 轮询 Prompt 模板

```
Auto CI check for commit {SHA} in {OWNER_REPO}:
1. Run: forgejo GET /repos/{OWNER_REPO}/commits/{SHA}/status | jq '{state, total_count}'
2. Read .aether/ci-watch.state, increment poll_count, write back
3. If state == "success": notify "CI passed ✓", CronDelete this job, delete state file
4. If state == "failure": notify "CI failed ✗", CronDelete, run /aether:aether-ci {SHA} --reproduce
5. If state == "pending" and poll_count < 15: update state file, wait for next poll
6. If poll_count >= 15: notify "CI timeout (~15 min)", CronDelete, suggest manual check
7. If API error (non-200): increment error_count, if >= 3 consecutive: notify + CronDelete
```

### CronCreate 参数

- **cron**: `*/1 * * * *` (每分钟，实际间隔 ~60s + jitter)
- **recurring**: `true`
- **prompt**: 上述模板（替换实际 SHA 和 OWNER_REPO）

### 终止条件

| 条件 | 动作 |
|------|------|
| CI 成功 | 通知用户 + CronDelete + 删除状态文件 |
| CI 失败 | 诊断报告 + CronDelete |
| 超过 15 次轮询 (~15 min) | 超时警告 + CronDelete |
| API 连续 3 次失败 | 错误报告 + CronDelete |
| 新的 git push (Hook 再次触发) | CronDelete 旧任务，启动新轮询 |

---

## 状态管理与容错

### 状态文件 `.aether/ci-watch.state`

```yaml
sha: abc1234...
repo: 10CG/Aether
branch: master
started: 2026-03-23T10:00:00Z
poll_count: 3
```

由 Hook 写入，CronCreate prompt 每次轮询时读取并更新 `poll_count`。

### 多次 Push 处理

当 Hook 再次触发时（状态文件已存在且 SHA 不同）：
1. CronDelete 旧的轮询 cron（使用 CronList 找到旧任务）
2. 状态文件被 Hook 覆盖为新 SHA
3. 新的 CronCreate 自动启动

### 认证失败处理

API 返回 401/403 或 HTTP 302 (Cloudflare redirect)：
- 停止轮询 + CronDelete
- 提示检查 `FORGEJO_TOKEN`、`CF_ACCESS_CLIENT_ID`、`CF_ACCESS_CLIENT_SECRET`

### 会话结束清理

CronCreate 任务在会话结束时自动销毁（session-only）。状态文件保留但无害。

---

**Skill 版本**: 1.1.0
**最后更新**: 2026-03-23
**维护者**: 10CG Infrastructure Team
