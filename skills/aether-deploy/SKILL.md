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
    min_version: "1.22.14"
---

# Aether 生产部署 (aether-deploy)

> **版本**: 0.5.0 | **更新**: 2026-10-11 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI ≥ 1.22.14**：镜像校验、部署、健康检查都由 `aether deploy` 完成。
更早的 CLI 在本机没有 docker、经 Cloudflare Access 访问 registry 时，会把 CF 登录页当成镜像存在（假绿）。

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
aether version    # 低于 1.22.14 先升级 (/aether:aether-doctor)
```

## 快速开始

### 使用场景

- 将服务部署到生产环境
- 从开发环境提升到生产
- 部署指定版本的镜像

### 不使用场景

- 开发环境部署 → push 到 main 自动触发
- 回滚 → 使用 `/aether:aether-rollback`

## 执行流程

### Step 1: 解析参数

```bash
/aether:aether-deploy my-project v1.2.3
```

提取：
- 服务名 (Nomad job 名): `my-project`
- 目标版本: `v1.2.3`（必须是明确的 tag，`latest` 直接拒绝）

镜像路径带 org 时（如 `forgejo.10cg.pub/10cg/my-project`），后面每条命令都加 `--image-repo 10cg/my-project`；
不加时 CLI 按 `<registry>/<job 名>:<版本>` 拼路径，会去校验一个不存在的镜像。

### Step 2: 预览（含镜像验证）

镜像验证是部署安全门控，**不可跳过**。`--dry-run` 依次做：拒绝 `latest` → 验证镜像在 registry 中存在 →
读取当前 job → 计算差异，不改动集群。

```bash
aether deploy my-project v1.2.3 --dry-run --json [--image-repo 10cg/my-project]
```

按 `.data.status` 判定。`--json` 下只要拿到部署结果，外层 `status` 就是 `ok`、退出码是 0，失败也一样（Aether #493），都不能当结论：

| 结果 | 含义 | 下一步 |
|------|------|--------|
| `.data.status == "dry_run"` | 镜像已确认存在 | Step 3 |
| `.data.status == "failed"`，`error_code: IMAGE_NOT_FOUND` | 镜像无法确认存在 | **停止部署**，按 Step 2.1 诊断 |
| 外层 `status == "error"` | 读取 job 失败等，原因在 `.error.message` | 报告原因；job 还不存在时，首次部署需手动 `nomad job run` |

dry-run 的 `.data.diff` 只比较线上 job 与目标镜像的 tag。`--yes` 注册的是本地 `--job-file` 的整份 spec，镜像以外的差异 dry-run 看不到，由 Step 3 的 `nomad job plan` 补上。

### Step 2.1: 镜像验证失败诊断

当镜像验证失败时，不要仅报错终止 — 读 `.data.message` 引导用户排查根因：

| `.data.message` 含 | 根因 | 排查 / 修复 |
|---|---|---|
| `not found in registry` | 镜像不存在或 tag 写错 | `aether ci status` 看构建是否成功；核对推送的 tag 与 `--image-repo` |
| `requires authentication` | registry 凭据缺失或无效 | 设置 `FORGEJO_USER` / `FORGEJO_TOKEN`（该用哪个 token 见 `/aether:aether-forgejo-creds`） |
| `did not return a manifest` / `CF Access login` | 请求被 Cloudflare Access 拦截 | 设置 `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` 后重试 |
| `cannot verify image` | 网络或 registry 不可达 | 先确认连通性，再重试 |

诊断完成后，向用户报告根因并建议修复方案，**不要跳过验证直接部署**。

### Step 3: 提交前核对，显示差异并确认

确认单之前先做四项只读核对。`NOMAD_ADDR` / `CONSUL_HTTP_ADDR` 按文末「前置条件」与 CLI 同一规则取；那段片段不 `export`，nomad CLI 读不到它，所以下面的 `nomad` 命令都显式带 `-address`。

1. **全量差异**：`nomad job plan -address="$NOMAD_ADDR" deploy/nomad-prod.hcl`（与 `--job-file` 同一份文件）。镜像那一行显示的是文件里的值（init 生成的文件是 `__IMAGE__`），以 dry-run 的 target 为准；**除镜像外的每一处变更都会随 `--yes` 一起提交**，逐条列进确认单。退出码 0 = 不动实例，1 = 会新建 / 替换实例（升级的常态），255 = 出错 → 停。记下输出里的 `Job Modify Index`。
2. **在飞的部署**：`curl -s "$NOMAD_ADDR/v1/job/my-project/deployment" | jq '{JobVersion, Status, StatusDescription}'`。`Status` 为 `running` / `paused` 时先不要提交（新注册会取代它），等它结束或问用户。
3. **回滚目标还在**：`aether deploy my-project <当前版本> --dry-run --json [--image-repo …]`，`.data.status == "dry_run"` 说明当前版本的镜像仍在 registry（registry 会按时间清理旧镜像）。失败，或当前版本读不出（`.data.current.version` 为 `unknown` / `latest`），都在确认单里写明，由用户决定是否继续。
4. **更新策略**：plan 或线上 job 的 `update` 块。`canary` > 0 且没开 `auto_promote` 时，部署会停在等待 promote，在 Step 5 处理。

然后用 dry-run 与上面四项的结果输出：

```
部署确认
========
服务: my-project
当前版本: v1.2.2（状态 running，2 个实例）     ← .data.current.{version,status,count}
目标版本: v1.2.3                              ← .data.target.{version,image}

变更内容:
- 镜像: forgejo.10cg.pub/org/my-project:v1.2.2 → v1.2.3
- 影响: Rolling update, 2 allocations will be replaced   ← .data.diff.impact
- 其他变更（nomad job plan，镜像以外）: 无 / 逐条列出
- Lint 警告: （.data.lint_warnings 有内容时逐条列出）

回滚目标: v1.2.2 镜像仍在 / 已不存在
在飞的部署: 无 / <Status>
更新策略: max_parallel=1, canary=0

确认部署到生产环境？ [y/N]
```

使用 AskUserQuestion 获取确认。

### Step 4: 执行部署并等待健康

提交前再读一次 `JobModifyIndex`。与 Step 3 记下的不同，说明预览之后有人改过 job：停下，重做 Step 2–3。
`aether deploy` 没有 `-check-index`，这一步只能把这个窗口缩到最小。

```bash
curl -s "$NOMAD_ADDR/v1/job/my-project" | jq .JobModifyIndex
aether deploy my-project v1.2.3 --yes --json [--timeout 5m] [--job-file deploy/nomad-prod.hcl] [--image-repo 10cg/my-project]
```

CLI 开头再验证一次镜像，然后读取 `--job-file`（默认 `deploy/nomad-prod.hcl`）→ 解析 HCL → 设置镜像 → 注册 job →
轮询健康检查，直到通过或超时（`--timeout`，默认 3 分钟）。

| 结果 | 结论 |
|------|------|
| `.data.status == "deployed"` 且 `.data.health_check.passed == true` | CLI 判通过，**还要过 Step 5 才算成功** |
| `.data.status == "failed"` | 健康检查未通过或超时：报告 `.data.message` 与 `.data.allocations`（desired / running / healthy / failed），提示 `/aether:aether-rollback my-project` |

### Step 5: 按新版本核对（不可跳过）

CLI 的健康检查不分新旧版本：它数所有 `DesiredStatus` 为 `run` 的实例，Consul 也只按服务名（默认等于 job 名）数 passing。
注册后紧接着的那次检查，旧实例往往还在跑，CLI 可能凭旧实例判通过。所以 `deployed` 之后按新版本核一遍：

```bash
# 1. 这次注册产生的 job version，以及最新一次 deployment
V=$(curl -s "$NOMAD_ADDR/v1/job/my-project" | jq .Version)
curl -s "$NOMAD_ADDR/v1/job/my-project/deployment" | jq '{ID, JobVersion, Status, StatusDescription, TaskGroups}'
# 2. 新版本的实例：running 的数量应等于期望实例数
curl -s "$NOMAD_ADDR/v1/job/my-project/allocations" \
  | jq --argjson v "$V" '[.[] | select(.JobVersion == $v and .ClientStatus == "running") | .ID]'
# 3. Consul 里 passing 的实例：服务名以 job spec 的 service 块为准，不一定等于 job 名
curl -s "$CONSUL_HTTP_ADDR/v1/health/service/<service>?passing" | jq -r '.[].Service.ID'
```

Consul 的 service ID 形如 `_nomad-task-<alloc ID>-…`。passing 的实例要覆盖第 2 步的全部新 alloc；出现旧 alloc 的 ID，说明旧实例还没下线，等它下线再判。

| 核对结果 | 结论 |
|---|---|
| deployment 的 `JobVersion` = V 且 `successful`，新实例数 = 期望数，passing 覆盖全部新 alloc | 成功，Step 6 |
| deployment 为 `null` 或 `JobVersion` ≠ V（这次注册没产生 deployment） | 只按第 2、3 步判 |
| deployment `running`，task group 的 `DesiredCanaries` > 0 且 `Promoted` 为 false | 等待 promote：问用户后 `nomad deployment promote -address="$NOMAD_ADDR" <ID>`，再从第 1 步核起 |
| deployment `running`，没有待 promote 的 canary | 滚动更新还在进行：等它结束（不超过 job 的 `progress_deadline`）再核 |
| deployment `failed`、新实例不足，或 passing 对不上新 alloc | 按失败处理：报告各项结果，提示 `/aether:aether-rollback my-project` |

### Step 6: 输出结果

```
部署成功
========
服务: my-project
版本: v1.2.3（Nomad job version 8）
实例: 2/2 running（均为新版本）
健康检查: Consul 2/2 passing，对应新 alloc

Consul DNS: my-project.service.consul
```

## 安全机制

1. **版本必须明确**: 不允许使用 `latest` 标签
2. **镜像必须存在**: 部署前验证镜像（dry-run 和正式部署的调用都会验证）
3. **需要确认**: 显示差异后需要用户确认；差异含 `nomad job plan` 列出的镜像以外的变更
4. **提交的就是确认过的**: 提交前复核 `JobModifyIndex`，预览之后 job 被改过就重来
5. **回滚有退路**: 部署前确认回滚目标镜像仍在
6. **健康检查**: 部署后等待 CLI 的健康检查通过（`--timeout` 控制上限），再按新版本核对 deployment、实例与 Consul
7. **自动回滚**: 如果健康检查或核对失败，提示使用 `/aether:aether-rollback`

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:aether-setup`。CLI 先看环境变量，再读配置文件里的
`cluster.nomad_addr` / `consul_addr` / `registry`。配置文件只读找到的第一份：项目里有 `.aether/config.yaml`
时整份不读全局 `~/.aether/config.yaml`，缺的字段用默认值（Nomad 为 `127.0.0.1:4646`），所以项目级配置要写全入口地址；
不读 `.env`。缺 registry 时报 `MISSING_REGISTRY`。

需要直接查询 Nomad / Consul 排查时，用同一规则取地址：

```bash
f=.aether/config.yaml; [ -f "$f" ] || f="$HOME/.aether/config.yaml"
NOMAD_ADDR=${NOMAD_ADDR:-$(yq '.cluster.nomad_addr // ""' "$f" 2>/dev/null)}
CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR:-$(yq '.cluster.consul_addr // ""' "$f" 2>/dev/null)}
[ -z "$NOMAD_ADDR" ] && { echo "未配置 cluster.nomad_addr（读的是 ${f}）：运行 /aether:aether-setup"; exit 1; }
```
