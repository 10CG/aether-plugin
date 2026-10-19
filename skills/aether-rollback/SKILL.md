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
    min_version: "1.23.0"
---

# Aether 生产回滚 (aether-rollback)

> **版本**: 0.5.1 | **更新**: 2026-10-19 | **优先级**: P1

## 前置检查

**⚠️ 此 Skill 需要 aether CLI ≥ 1.23.0**：回滚的健康检查按 revert 产生的版本及其 deployment 判定（1.22.15 起）；
方案 B 用 `aether deploy` 的 Nomad plan 与 `--check-index`（1.23.0 起）。

```bash
# 使用共享检测脚本
source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
require_aether_cli || exit 1
aether version    # 低于 1.23.0 先升级 (/aether:aether-doctor)
```

版本历史与标准回滚都用 `aether rollback`：它执行 Nomad revert 后，按 revert 产生的版本带超时做健康检查，不用手写等待循环。

## 快速开始

### 使用场景

- 新版本部署后出现问题，需要快速回退
- 紧急恢复服务可用性
- 回滚到之前的稳定版本

## 执行流程

### Step 1: 获取版本历史

```bash
/aether:aether-rollback my-project
```

查询 Nomad Job 版本历史：

```bash
# 每个版本对应的镜像与 Nomad 的 Stable 标记（cli ≥1.23.2 起 --list 自带 Stable 字段）
aether rollback --list my-project --json | jq '.data.Versions[] | {Version, Image, Stable, DeployedAt}'
```

`--list` 的 `Status` 只按顺序标 current / previous / stable（第 3 个起都叫 stable，Aether #493），不代表那个版本部署成功过；
推荐回滚目标看同一输出里的 `Stable` 字段（cli <1.23.2 的 `--list` 不带 Stable，改查 `curl -s "${NOMAD_ADDR}/v1/job/my-project/versions"` 里的 `Stable`）。

刚部署失败、而 job 的 `update` 开了 `auto_revert` 时，Nomad 可能已经自动退回（`aether deploy` 的 message 含 `rolling back to job version N`）：
最新版本是退回产生的，与 version N 相同；紧邻的上一个版本是刚失败的那个，`Stable` 为 false。退回后的版本健康，就不需要再回滚。

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
回滚方案: A (aether rollback)

确认执行回滚？ [y/N]
```

使用 AskUserQuestion 获取确认。用户未确认则终止。

### Step 3: 执行回滚

根据当前 Job 状态，选择合适的回滚方案：

#### 方案 A: aether rollback（推荐，标准路径）

适用于：Job 存在、版本历史完整、标准回滚场景。

```bash
# 先预览，不改集群
aether rollback my-project --to <version> --dry-run --json
# 执行：Nomad revert + 带超时的健康检查（默认 3 分钟）
aether rollback my-project --to <version> --yes --json [--timeout 5m]
```

按 `.data.status` 判定（`--json` 下只要拿到回滚结果，外层 `status` 就是 `ok`，失败也一样，不能当结论；失败的退出码自 cli 1.23.12 起是 1，更早版本是 0（Aether #493））：

| 结果 | 下一步 |
|------|--------|
| `rolled_back` 且 `.data.health_check.passed == true` | 回滚完成 → Step 5 |
| `failed`，`error_code: ROLLBACK_FAILED` | revert 本身失败 → 方案 B |
| `failed`，`error_code: ROLLBACK_HEALTH_CHECK_FAILED` | 已 revert，但 revert 产生的版本没通过：超时，或它的 deployment 失败 / 暂停 / 在等 promote，`.data.message` 写明是哪种 → 「回滚失败处理」 |
| `failed`，`error_code: JOB_MODIFIED_CONCURRENTLY` | 已 revert，紧接着又有别的注册，认不出 revert 产生的版本：先看 `nomad job history -address="$NOMAD_ADDR" my-project`，不要再执行回滚 |
| 外层 `status == "error"` | job 或目标版本不存在等，读 `.error.message` |

这是最安全的标准路径。Nomad 保留完整的版本历史，revert 以目标版本的 Job spec 提交一个**新**版本（版本号递增，镜像与目标版本相同）。
`.data.health_check.job_version` 就是这个新版本号（不是 `--to` 的目标版本号）；`deployment_id` / `deployment_status` 是 CLI 判定所依据的 deployment，为空表示该版本没有 deployment。

#### 方案 B: 从 Git 重提交 Job Spec

适用于：Job 配置已损坏、当前版本的 Job spec 有问题、或版本历史不可信。

```bash
# 1. 从 Git 历史取已知正常的 Job spec（/aether:aether-init 生成的生产 spec 是 deploy/nomad-prod.hcl）
git log --oneline -- deploy/nomad-prod.hcl
git show <commit>:deploy/nomad-prod.hcl > /tmp/my-project.nomad.hcl

# 2. 用 aether deploy 提交这份 spec：解析 HCL、把镜像设为指定 tag、验证镜像、Nomad plan 预演；
#    确认后带上 plan 的 job_modify_index 提交，并做健康检查
aether deploy my-project <已知正常的 tag> --job-file /tmp/my-project.nomad.hcl --dry-run --json [--image-repo <org>/my-project]
aether deploy my-project <已知正常的 tag> --job-file /tmp/my-project.nomad.hcl --yes --check-index <.data.plan.job_modify_index> --json [--image-repo <org>/my-project]
```

结果按 `/aether:aether-deploy` 的 Step 2 / Step 4 判定（看 `.data.status`）。dry-run 的 `.data.plan.changes` 就是这份 Git spec 与线上 job 的全部差异，确认前给用户看。
不要直接 `nomad job run` 这份文件：
init 生成的模板里镜像是 `__IMAGE__` 占位符，原样提交会把字面量当镜像。
与方案 A 一样会产生新版本号；区别是 spec 来自 Git 而不是 Nomad 版本历史，后续若需再次回滚，版本号会不同。

#### 方案 C: 紧急部署旧版镜像

适用于：Job 完全丢失、namespace 问题导致 revert 失败、或需要绕过 Nomad 版本管理。

```bash
# 1. 查询 Registry 中可用的镜像版本
#    外网 forgejo.10cg.pub 在 Cloudflare Access 之后，裸 curl 拿到的是登录页；走内网并带 registry 凭据
#    （token 从文件读进 curl 配置文件，不进 argv，用完即删）
umask 077; printf 'user = "%s:%s"\n' "<registry-user>" "$(cat <token 文件>)" > /tmp/curlrc.$$
curl -s -K /tmp/curlrc.$$ "http://192.168.69.200:3000/v2/<org>/my-project/tags/list" | jq '.tags'
rm -f /tmp/curlrc.$$

# 2. 确认目标镜像可用（本机有 docker 且能访问 registry 时）
docker pull <registry>/<org>/my-project:<old-tag>

# 3. 把 Job spec 的镜像换成旧版本后提交（init 生成的模板里是 __IMAGE__ 占位符）
sed "s|__IMAGE__|<registry>/<org>/my-project:<old-tag>|g" deploy/nomad-prod.hcl > /tmp/my-project-emergency.nomad.hcl
nomad job run /tmp/my-project-emergency.nomad.hcl
```

此方案是最后手段。提交后应尽快通过正常部署流程恢复。

**方案选择指引**：

| 状况 | 推荐方案 |
|------|---------|
| 标准回滚（Job 正常，版本可用） | 方案 A |
| `aether rollback` 报 `ROLLBACK_FAILED` / Job spec 损坏 | 方案 B |
| Job 丢失 / namespace 错误 / revert 反复失败 | 方案 C |

### Step 4: 等待回滚完成

方案 A / B 的等待由 CLI 完成（`--timeout` 控制上限）：它只数 revert / 注册产生的那个版本的实例，不会把还没下线的旧实例算进去。
方案 C 手工提交后，用 `aether status my-project` 确认新 allocation 全部 running；等待要设上限（如 3 分钟），超时转「回滚失败处理」，不要无限等。
revert 产生的是新版本号，按「镜像等于目标版本的镜像」核对，不要按 `JobVersion == 目标版本号` 等待（永远等不到）。

### Step 5: 验证健康状态

方案 A / B：CLI 已按新版本判过，报告 `.data.health_check.job_version`、`deployment_status` 与 `.data.allocations`。
再查一次 Consul（服务名以 job spec 的 `service` 块为准，不一定等于 job 名），数量应与 `.data.allocations.desired` 一致：

```bash
curl -s "${CONSUL_HTTP_ADDR}/v1/health/service/<service>?passing" | jq 'length'
```

方案 C 没有 CLI 的判定：Step 4 确认新 allocation 全部 running 后，同样查上面的 Consul。

### Step 6: 输出结果

```
回滚成功
========
服务: my-project
当前版本: v2 (def456)，revert 产生的 Nomad job version 9
实例: 2/2 running
健康检查: deployment successful，Consul 2/2 passing

回滚完成，服务已恢复。
```

## 紧急回滚（快速路径）

如果需要快速回滚，可以直接指定版本跳过版本选择步骤：

```bash
/aether:aether-rollback my-project --to v2
```

这将跳过版本列表展示，但仍需执行确认（Step 2.5）后才会执行回滚。
`aether rollback --to` 接的是 Nomad job 版本号（整数，如 `--to 2`），不是镜像 tag。不带 `--to` 时默认目标按 `Stable` 选：
当前版本之前最新的 Stable 版本，跳过的不稳定版本写进 `target_reason`（cli ≥1.23.2，#514；更早版本退到紧邻的上一个版本，
刚 auto_revert 过时那就是失败的那个）。回滚目标仍按 Step 1 的 `Stable` 选，用 `--to` 显式指定。

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

**兜底手段**：如以上排查均无果，使用 `/aether:aether-status my-project` 查看详细状态，或调用 `deploy-doctor` agent 进行深度诊断。

## 预防措施

在部署流程中加入以下实践，减少回滚需求和回滚失败的风险：

- **Canary 部署 + auto_revert**：在 Job spec 中配置 `canary = 1` 和 `auto_revert = true`，让 Nomad 在 canary 失败时自动回滚，无需人工介入。
- **部署前 DB Migration 验证**：确保每次 migration 都有对应的 rollback SQL，且在 staging 环境验证过反向迁移。
- **健康检查端点版本化**：使用稳定路径（如 `/health`），避免跨版本变更检查端点。
- **回滚手册维护**：每次部署后更新回滚手册，记录当前版本的外部依赖和配置变更，确保回滚时有据可查。

## 前置条件：集群配置

执行前需要配置 Aether 集群入口，参考 `/aether:aether-setup`。

### 配置读取

CLI 先看环境变量，再读配置文件；配置文件只读找到的第一份（项目里有 `.aether/config.yaml` 时整份不读全局
`~/.aether/config.yaml`，缺的字段用默认值），不读 `.env`。直接查询 Nomad / Consul 时用同一规则取地址：

```bash
f=.aether/config.yaml; [ -f "$f" ] || f="$HOME/.aether/config.yaml"
NOMAD_ADDR=${NOMAD_ADDR:-$(yq '.cluster.nomad_addr // ""' "$f" 2>/dev/null)}
CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR:-$(yq '.cluster.consul_addr // ""' "$f" 2>/dev/null)}
[ -z "$NOMAD_ADDR" ] && { echo "未配置 cluster.nomad_addr（读的是 ${f}）：运行 /aether:aether-setup"; exit 1; }
```
