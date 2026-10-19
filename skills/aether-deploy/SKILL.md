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
    min_version: "1.23.0"
---

# Aether 生产部署 (aether-deploy)

> **版本**: 0.6.1 | **更新**: 2026-10-19 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI ≥ 1.23.0**：镜像校验、Nomad plan 预览、按预览过的那一版提交、按新版本判定健康，都由 `aether deploy` 完成。
更早的 CLI：dry-run 没有 `.data.plan`，也不认 `--check-index`（1.23.0 起）；健康检查不分新旧版本（1.22.15 起才按新版本判）；
本机没有 docker、经 Cloudflare Access 访问 registry 时，会把 CF 登录页当成镜像存在（1.22.14 起修复）。

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
aether version    # 低于 1.23.0 先升级 (/aether:aether-doctor)
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

### Step 2: 预览（镜像验证 + Nomad plan）

镜像验证是部署安全门控，**不可跳过**。`--dry-run` 依次做：拒绝 `latest` → 验证镜像在 registry 中存在 → 读取当前 job →
把 `--job-file`（默认 `deploy/nomad-prod.hcl`）换上目标镜像，交给 Nomad plan 预演，不改动集群。

```bash
aether deploy my-project v1.2.3 --dry-run --json [--job-file deploy/nomad-prod.hcl] [--image-repo 10cg/my-project]
```

按 `.data.status` 判定。`--json` 下只要拿到部署结果，外层 `status` 就是 `ok`，失败也一样，不能当结论；失败的退出码自 cli 1.23.12 起是 1（更早版本是 0，Aether #493），同样不能代替它：

| 结果 | 含义 | 下一步 |
|------|------|--------|
| `.data.status == "dry_run"`，有 `.data.plan` | 镜像已确认存在，plan 已做 | Step 3 |
| `.data.status == "dry_run"`，`.data.plan_error` 非空 | 镜像在，plan 没做成：job 文件找不到 / 解析不过 / Nomad plan 失败，原因就在这一项 | 解决后重跑 Step 2。`--yes` 提交的是同一份文件，会在同一处失败；`.data.diff` 只比较镜像 tag，不能代替 plan 去确认 |
| `.data.status == "failed"`，`error_code: IMAGE_NOT_FOUND` | 镜像无法确认存在 | **停止部署**，按 Step 2.1 诊断 |
| 外层 `status == "error"` | 读取 job 失败等，原因在 `.error.message` | 报告原因；job 还不存在时，首次部署需手动 `nomad job run` |

`dry_run` 却既没有 `.data.plan` 也没有 `.data.plan_error`，说明 CLI 早于 1.23.0：先升级。

### Step 2.1: 镜像验证失败诊断

当镜像验证失败时，不要仅报错终止 — 读 `.data.message` 引导用户排查根因：

| `.data.message` 含 | 根因 | 排查 / 修复 |
|---|---|---|
| `not found in registry` | 镜像不存在或 tag 写错 | `aether ci status` 看构建是否成功；核对推送的 tag 与 `--image-repo` |
| `requires authentication` | registry 凭据缺失或无效 | 设置 `FORGEJO_USER` / `FORGEJO_TOKEN`（该用哪个 token 见 `/aether:aether-forgejo-creds`） |
| `did not return a manifest` / `CF Access login` | 请求被 Cloudflare Access 拦截 | 设置 `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` 后重试 |
| `cannot verify image` | 网络或 registry 不可达 | 先确认连通性，再重试 |

诊断完成后，向用户报告根因并建议修复方案，**不要跳过验证直接部署**。

### Step 3: 显示变更并确认

`.data.plan` 是 Nomad 对「`--yes` 将要注册的那份 spec」的预演：

| 字段 | 看什么 |
|---|---|
| `changes` | 逐字段的差异，一行一项，镜像那一行也在里面。**镜像以外的每一处都会随 `--yes` 一起提交**，逐条列进确认单 |
| `groups[]` | 每个 task group 的动作：`place` / `stop` / `destructive_update`（替换实例）/ `in_place_update` / `canary` / `ignore` |
| `failed_placements` | 非空 = 调度器放不下这些 group（资源不够、约束不满足）：停，不要提交 |
| `warnings` | Nomad 的警告，原样写进确认单 |
| `job_modify_index` | 记下来，Step 4 用它做 `--check-index` |

- `diff_type` 为 `None`（`changes` 为空）：文件与线上一致、镜像也没变，提交不会产生新版本。问用户还要不要继续。
- `groups` 里 `canary` > 0：这是 canary 部署。job 没开 `auto_promote` 时，canary 健康后部署会停下等人工 promote（Step 4 的 `DEPLOYMENT_AWAITING_PROMOTION`），在确认单里写明。

另做两项 CLI 不做的只读核对（`NOMAD_ADDR` 按文末「前置条件」取）：

1. **在飞的部署**：`curl -s "$NOMAD_ADDR/v1/job/my-project/deployment" | jq '{JobVersion, Status, StatusDescription}'`。`Status` 为 `running` / `paused` 时先不要提交（新注册会取代它），等它结束或问用户。
2. **回滚目标还在**：`aether deploy my-project <当前版本> --dry-run --json [--image-repo …]`，`.data.status == "dry_run"` 说明当前版本的镜像仍在 registry（registry 会按时间清理旧镜像）。失败，或当前版本读不出（`.data.current.version` 为 `unknown` / `latest`），都在确认单里写明，由用户决定是否继续。

然后输出：

```
部署确认
========
服务: my-project
当前版本: v1.2.2（状态 running，2 个实例）     ← .data.current.{version,status,count}
目标版本: v1.2.3                              ← .data.target.{version,image}

变更内容（Nomad plan）:
- 镜像: forgejo.10cg.pub/org/my-project:v1.2.2 → v1.2.3
- 其他变更: 无 / 逐条列出                      ← .data.plan.changes 里镜像以外的行
- 实例: group web 替换 2 个                    ← .data.plan.groups
- 放不下的 group / Nomad 警告: 无               ← .data.plan.failed_placements / warnings
- Lint 警告: （.data.lint_warnings 有内容时逐条列出）

回滚目标: v1.2.2 镜像仍在 / 已不存在
在飞的部署: 无 / <Status>

确认部署到生产环境？ [y/N]
```

使用 AskUserQuestion 获取确认。

### Step 4: 提交并等待健康

带上 Step 3 记下的 `job_modify_index`。其余参数（版本、`--job-file`、`--image-repo`）与 Step 2 完全相同，两步之间不要改 job 文件：

```bash
aether deploy my-project v1.2.3 --yes --check-index <job_modify_index> --json [--timeout 5m] [--job-file deploy/nomad-prod.hcl] [--image-repo 10cg/my-project]
```

`--check-index`：预览之后 job 被改过（别人部署了、有人改了 spec），Nomad 就拒绝这次注册，什么都不提交。
CLI 开头再验证一次镜像，然后解析 job 文件 → 设置镜像 → 注册 → 按**这次注册产生的 job version** 判健康：
该版本有 Nomad deployment 时以 deployment 为准（它已按 job 的 `update` 策略判过新实例），没有时数该版本的实例并查 Consul；
直到通过、到达终态，或超时（`--timeout`，默认 3 分钟）。

| 结果 | 结论 / 下一步 |
|------|------|
| `.data.status == "deployed"` 且 `.data.health_check.passed == true` | 成功 → Step 5 |
| `JOB_MODIFIED_SINCE_PLAN` | 没有提交。回到 Step 2 重新预览，按新的 plan 重新确认；不要去掉 `--check-index` 硬提交 |
| `DEPLOYMENT_AWAITING_PROMOTION` | 不是故障：canary 已健康，旧版本照常服务，在等人工 promote。问用户：promote（`nomad deployment promote -address="$NOMAD_ADDR" <deployment_id>`），或放弃 canary、保留旧版本（`nomad deployment fail -address="$NOMAD_ADDR" <deployment_id>`）；promote 后用 `nomad deployment status -address="$NOMAD_ADDR" <deployment_id>` 核对它变为 `successful` |
| `DEPLOYMENT_FAILED`，`.data.message` 含 `rolling back to job version N` | Nomad 已按 `auto_revert` 自动退回：注册了一个与 version N 相同的新版本。**不要再回滚**：核对退回后的版本健康（`/aether:aether-status my-project`），再查失败原因（cli ≥1.23.2/#514 起 `suggested_action` 不再建议回滚、不带 `--to` 的默认回滚目标也按 Stable 选；1.23.0/1.23.1 里两者都指向刚失败的版本） |
| `DEPLOYMENT_FAILED`（没有自动退回）、`HEALTH_CHECK_TIMEOUT` | 报告 `.data.message`（最后一次检查看到的状态）与 `.data.allocations`，提示 `/aether:aether-rollback my-project`。超时时 deployment 可能还在进行（job 的 `progress_deadline` 可能比 `--timeout` 长），先用 `nomad deployment status -address="$NOMAD_ADDR" <deployment_id>` 看它的状态再定 |
| `DEPLOYMENT_PAUSED` / `DEPLOYMENT_CANCELLED` | 有人暂停了这次部署 / 部署期间又注册了更新的版本：报告，按 `.data.suggested_action` 问用户 |
| `JOB_MODIFIED_CONCURRENTLY` | 已注册，但紧接着又有别的注册，认不出这次产生的版本：先看 `nomad job history -address="$NOMAD_ADDR" my-project`，不要重试或回滚 |
| 其他 `failed` / 外层 `status == "error"` | 报告 `.data.message` / `.error.message` |

`.data.health_check.deployment_status` 为空、job 的 service 名又不等于 job 名时，CLI 在 Consul 里查不到实例，会一直等到超时（误报失败，#509）：用真实的服务名查 Consul 再下结论。

### Step 5: 核对并输出结果

`deployed` 时 CLI 已按新版本判过。报告它判的是什么：`.data.health_check.job_version`（这次注册产生的 Nomad job version）、
`deployment_id` / `deployment_status`（该版本的 deployment；为空 = 该版本没有 deployment）、`.data.allocations`（该版本的 desired / running / healthy）。

最后查一次 Consul，确认服务发现里是 passing（服务名以 job spec 的 `service` 块为准，不一定等于 job 名）：

```bash
curl -s "$CONSUL_HTTP_ADDR/v1/health/service/<service>?passing" | jq 'length'
```

数量应与 `.data.allocations.desired` 一致；多出来的多半是还没下线的旧实例，稍后再查。

```
部署成功
========
服务: my-project
版本: v1.2.3（Nomad job version 8，deployment successful）
实例: 2/2 running（均为 version 8）
健康检查: Consul 2/2 passing

Consul DNS: my-project.service.consul
```

## 安全机制

1. **版本必须明确**: 不允许使用 `latest` 标签
2. **镜像必须存在**: 部署前验证镜像（dry-run 和正式部署的调用都会验证）
3. **需要确认**: 确认单列出 Nomad plan 的全部变更（含镜像以外的），用户确认后才提交
4. **提交的就是确认过的**: `--check-index` 带上 plan 时的 job modify index，预览之后 job 被改过就拒绝提交
5. **回滚有退路**: 部署前确认回滚目标镜像仍在
6. **健康检查**: CLI 按这次注册产生的版本及其 deployment 判定（`--timeout` 控制上限）；canary 待 promote、deployment 失败 / 暂停 / 取消都会报出
7. **失败处理**: 先看 Nomad 是否已自动退回；没有才提示 `/aether:aether-rollback`

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
