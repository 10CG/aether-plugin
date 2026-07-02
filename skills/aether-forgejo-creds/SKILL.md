---
name: aether-forgejo-creds
description: |
  Aether 环境下 Forgejo 凭据的决策 / 诊断 / 轮换指南。回答"该用哪个 token"、
  拆解人机两账号模型 (simonfish 人 / 10cg-ci-bot 机)、辨别 CF Access 与 forgejo PAT
  两个凭据平面、诊断误导性 403 ("Only signed in user")、安全轮换 (先枚举全部 store)、
  凭据卫生红线。深度内容指向 docs/guides/forgejo-token-map.md +
  .aether/pat-inventory.yaml。

  使用场景: "该用哪个 forgejo token"、"which forgejo token"、"forgejo 401"、
  "forgejo 403"、"Only signed in user"、"docker login forgejo"、"CF Access 403"、
  "token rotation"、"凭据轮换"、"FORGEJO_TOKEN"、"forgejo credential"、
  "人机账号"、"registry pull 401"、"docker push unauthorized"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Aether Forgejo 凭据指南 (aether-forgejo-creds)

> **版本**: 0.1.0 | **优先级**: P1 | **事故根因**: H1 (#189, 2026-07-01 一 token N 用级联)
> **机读 SoT**: `.aether/pat-inventory.yaml` · **人读权威**: `docs/guides/forgejo-token-map.md`

## 核心原则 (先记这三条)

1. **人机分离**: 只有两个主账号 —— `simonfish`(人) / `10cg-ci-bot`(机器)。人的活用
   simonfish，机器的活 (CI / Nomad job / host config) 用 10cg-ci-bot。**绝不交叉**。
2. **两个平面**: 访问外网 `forgejo.10cg.pub` 要过两道**独立**的门 —— Cloudflare Access
   (CF header) + forgejo PAT (Authorization: token)。它们各自失效、各自诊断，别混。
3. **轮换前枚举全部 store**: 一处 fingerprint = 假完整。H1 就是只看一个 store 就 revoke，
   级联断了 8+ 仓 CI。

> 这是 investigation-first skill: 先判断"是决策 / 诊断 / 轮换 哪类问题"，再走对应段落。
> 不确定就读 `docs/guides/forgejo-token-map.md` (权威人读版) 或
> `.aether/pat-inventory.yaml` (机读 SoT)。**不要凭记忆编造 token/账号**。

---

## 1. 两账号模型 (who)

| 账号 | id | 身份 | 用途 | 绝不 |
|------|----|------|------|------|
| **`simonfish`** | 2 | 人 (org owner) | 交互 dev/AI 会话: 写 code、开 PR、发 issue、跑 `aether` 只读命令 | ❌ 进 CI / Nomad job / host config |
| **`10cg-ci-bot`** | 6 | 机器 | 一切自动化: CI、runtime 拉镜像、build push、issue 自动化 | ❌ 进人的 `~/.forgejo_env` / dev shell |

> `10cg-ci-bot` 是 `aria-runner-bot` 的新名 (renamed 2026-07-01)。任何地方再看到
> `aria-runner-bot` 用户名 = **stale，要改**。**不新增第三个主账号**(除非强隔离需求)；
> 专用永久 bot 令牌 (如 `ci-runner-image-mirror`，见 §3 T5) 另计。

**账号规则 (永远)**:
- `docker login` / basic-auth: **username 必须匹配 token 归属账号**。10cg-ci-bot 的 token
  → `-u 10cg-ci-bot`。账号切换必须**同步原子改 user + token** (H1 + heavy-node 两次踩坑)。
- `curl -H "Authorization: token …"` (拉 package / API): **只看 token 不看 user**。

---

## 2. 两个凭据平面 + 误导性 403 诊断

访问外网 URL `forgejo.10cg.pub` 要过两道独立的门:

| 平面 | 凭据 | header | 谁管 |
|------|------|--------|------|
| ① **Cloudflare Access 网关** | `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` | `CF-Access-Client-Id/Secret` | Cloudflare 后台 (**不是 forgejo token，不归本 skill / aether-rotate-pat**) |
| ② **forgejo 账号认证** | `FORGEJO_TOKEN` (PAT) | `Authorization: token …` | 本 skill + aether-rotate-pat |

> **内网端点 `192.168.69.200:3000` 完全绕过 CF 门** —— 调试 forgejo PAT 时走内网，把 CF 平面隔离掉。

### 陷阱: `"Only signed in user is allowed to call APIs."` 403

这个 403 长得像 CF 门 / access-gate 拒绝，**实为 forgejo 拒绝一个失效或缺失的 PAT**。
**别去轮换 CF token —— 该刷新 forgejo PAT。**

诊断表 (对外网 URL 逐步加 header 观察):

| 请求 | 结果 | 判读 |
|------|------|------|
| 无 CF header | `302` 重定向到 CF 登录 | CF 门在挡 → 缺 CF header |
| 有 CF header + 无/死 PAT | `403` + forgejo JSON `Only signed in user…` | **PAT 缺失/失效 → 刷 forgejo PAT** |
| 有 CF header + 有效 PAT | `200` | 两道门都过 |

对照口诀: **302 = CF 层问题; 403-json = forgejo PAT 层问题; 200 = 通。**
走内网 `192.168.69.200:3000` 复测可直接排除 CF 平面。

### 401 vs 403 速判

- `401 unauthorized` on `docker login`/push/pull → token 值错 / 账号-username 不匹配 / scope 不含 package。查 §3 是否用错 token。
- `403 Only signed in user` → §2 上表，刷 PAT。

---

## 3. 决策矩阵: 我要做 X，用哪个 token?

> 完整 token 清单 (scope · store · 消费方) 见 `docs/guides/forgejo-token-map.md §2`。
> ⚠ 下面速览是 doc/inventory 的**镜像，可能滞后** —— 与 `docs/guides/forgejo-token-map.md`
> 或 `.aether/pat-inventory.yaml` 冲突时**以后者为准**。

| 场景 | 用哪个 | 从哪取 |
|------|--------|--------|
| 交互开 PR / 发 issue / `forgejo` CLI / `aether` 只读命令 | **T1 simonfish** | shell 自动继承 `$FORGEJO_TOKEN` (from `~/.forgejo_env`); 验证 `login=simonfish` |
| CI 拉内网二进制 (golangci/nomad/gitleaks/ossutil) | **T3** | `secrets.FORGEJO_TOKEN` 自动注入 |
| CI / deploy job `docker login` + push 镜像 | **T3** | `-u $FORGEJO_USER=10cg-ci-bot -p $FORGEJO_TOKEN` 自动注入 |
| Nomad job 运行时拉容器镜像 | **T2** | Nomad var `docker_auth_password` (`aether env set` 管) |
| act_runner 拉 runner-images | **T2** | heavy `/root/.docker/config.json` (`docker login -u 10cg-ci-bot`) |
| aria-build push aria-runner 镜像 | **T4** | Nomad var `FORGEJO_BOT_PAT` (`nomad/jobs/aria-build`) |
| todo-web CI push package | **T6** (repo 级 override，不继承 org T3) | todo-web repo 级 Actions secret |
| 手动 `aether doctor` 查 registry (需 read:package) | ⚠️ T1 **无 package** → 会 401 | 走内网，或临时用 T2 值，或给 simonfish 加 read:package |

### Token 清单速览 (账号 · scope · store)

| # | 用途 | 账号 | scope | store |
|---|------|------|-------|-------|
| T1 | 人的 dev-shell | simonfish | issue+repo+read:user (**无 package**) | `~/.forgejo_env` (600), `.bashrc`+`.profile` source |
| T2 | runtime registry pull | 10cg-ci-bot | `read:package` | 18 Nomad var `docker_auth_password` + 3 heavy `/root/.docker/config.json` |
| T3 | org CI 全用途 | 10cg-ci-bot | issue+repo+package+read:user | org `10CG` Actions secret `FORGEJO_TOKEN` (+`FORGEJO_USER`) |
| T4 | aria-build DooD push | 10cg-ci-bot | `write:package` | Nomad var `FORGEJO_BOT_PAT` (aria-build, 自定义 key)。⚠ 现**复用 T3 同一物理 token** (待 mint 专用) → **轮换 T3 会连带断 aria-build** |
| T5 | runner-image mirror push | `ci-runner-image-mirror` (专用永久 bot) | `write:package` (**永不过期**) | heavy-1 `/opt/forgejo-runner/.docker-mirror/config.json` |
| T6 | todo-web CI | todo-web own | `write:package` | todo-web **repo 级** Actions secret (override org T3) |
| T7 | rotation bootstrap | ops | `write:user` | 不部署 (引导凭据) |

> ☠️ `ca32267` (旧 `aether-deploy` token, simonfish) 已 **revoke** —— H1 一 token N 用根因，
> 不要复活。silknode ACR 用的是 Aliyun 凭据 (`docker_registry_password`)，**非 forgejo**，不在本范围。

---

## 4. 轮换: 先枚举全部 store，再动手

**revoke / 轮换任何 token 前，枚举它的全部 store。** 一处 fingerprint = 假完整 (H1 教训:
`ca32267` revoke 级联到 8+ 仓)。四类 store 逐一核:

- [ ] **① Nomad Variables**: `docker_auth_password` + 自定义 key (`FORGEJO_BOT_PAT` 等)
  → `aether registry-auth list`
- [ ] **② Forgejo Actions secrets**: **repo 级 AND org 级** 都查
  → `aether doctor forgejo_actions_secret_drift` (cli-v1.16.43+)
- [ ] **③ host docker configs**: heavy `/root/.docker/config.json` (runner-pull) +
  `/opt/forgejo-runner/.docker-mirror` (mirror push)
  → 远端 `python3 base64 decode + sha256` 指纹，**不打印 token**
- [ ] **④ shell env**: `~/.forgejo_env` (simonfish 单一来源，login+interactive 都 source 它)

> ⚠ **T3 (org FORGEJO_TOKEN) 轮换的 blast-radius 目前包含 aria-build (T4)** —— 二者复用同一
> 物理 token；换 T3 时必须同步更新 aria-build 的 `FORGEJO_BOT_PAT` (或先 mint 专用解耦)。

工具:
- **Tier 1 自动轮换**: `aether registry-auth rotate` (nomad-variables + forgejo-secrets repo 级；`docker_auth_password` 单 key) —— 详见 `aether-rotate-pat` skill
- **手动**: 账号切换 / 自定义 var key / org 级 secret / host docker config / 永久 bot → 手动 (token-map §2 定位 store + `docs/guides/forgejo-pat-rotation.md` / `forgejo-pat-emergency-rotation.md`)
- **审计**: `aether doctor pat_age` (到期) + `pat_inventory_drift` (Nomad var 漂移) + `forgejo_actions_secret_drift` (org Actions secret 漂移)

> scope 决定消费面: 换的 token scope 不足 (例如 issue-only 却给需要 package 的消费方) 会留隐性断裂。
> 换前核对该 store 消费方需要的最小 scope。

---

## 5. 凭据卫生 + 红线

**凭据卫生 (绝不违反)**:
- ❌ **绝不 `grep`/`cat`/`echo` 含 token 的文件或变量** (`~/.forgejo_env`、`.bashrc`、`.env`、docker config…)。
- ✅ 验证"换没换"用 **sha256 指纹** (前 16 字符): `sha256sum <<<"$VAR" | cut -c1-16` 在 subshell 内，读完 scrub。
- ✅ 验证"有效性"用 subshell 读 + 立即清；**绝不把 token 值贴进对话** (transcript 持久化)。

**红线**:
1. 绝不一 token N 用**跨账号边界** (H1 根因)。
2. 机器 token 绝不进人的 shell，人的 token 绝不进 CI/job/host (反之亦然)。
3. revoke 前枚举**全部** store (§4)。
4. 新 token / 新 store 必须登记进 `.aether/pat-inventory.yaml` —— `forgejo_actions_secret_drift` 会揪未登记的 org secret。
5. 账号切换必须**同步原子**改 user + token (docker login username 必须匹配 token 归属账号)。

---

## 关联

- **权威人读版**: `docs/guides/forgejo-token-map.md` (完整 token 清单 + 决策矩阵 + 待办红线)
- **机读 SoT**: `.aether/pat-inventory.yaml` (登记全部 token/store，drift check 依据)
- **审计**: `aether doctor forgejo_actions_secret_drift` / `pat_age` / `pat_inventory_drift`
- **轮换执行**: `aether-rotate-pat` skill · `docs/guides/forgejo-pat-rotation.md` · `forgejo-pat-emergency-rotation.md`
- **事故全账**: [#189](https://forgejo.10cg.pub/10CG/Aether/issues/189) (H1 一 token N 用级联)
- **Nomad docker auth**: `docs/guides/nomad-variables-docker-auth.md`
