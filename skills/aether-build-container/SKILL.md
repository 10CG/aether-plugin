---
name: aether-build-container
description: |
  Aether 集群上 owner-triggered 一次性 build container 原语 (walking skeleton, #27).
  把本地 git ref 的 tracked 树打包送上 heavy 节点宿主 docker, build + push 到内网
  registry, 返回 immutable image_sha256 契约。无 CLI 子命令、无版本 bump、零 Go 代码。

  使用场景: "build 镜像", "build aria-runner", "构建容器镜像", "build container",
  "把 Dockerfile 推到 registry", "image build", "用 Aether 跑 build", "10CG 项目
  build image", "首次镜像构建", "无 CI 触发的镜像 build"
argument-hint: "<git_ref> <dockerfile_path> <registry_path> [--build-arg K=V ...]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write
dependencies:
  cli:
    required: true
    min_version: "1.16.21"
    role: "skill dispatches Nomad batch job via `aether dev run`; reads alloc state via `aether status`"
---

# Aether build-container 原语 (#27 walking skeleton)

> **Spec**: `openspec/changes/build-container-skeleton/proposal.md` (post_spec 收敛 PASS)
> **决策**: `.aria/decisions/27-build-container-skeleton-brainstorm-2026-05-18.md`
> **Aria #111**: 契约 + 错误码权威输入

## 何时使用

```
你需要把本地某个 git ref 的代码 build 成镜像 + push 到内网 registry?
  ├─ owner-triggered 一次性 build (Aria runner image / 新项目首次 build) → 用本 skill
  ├─ CI 自动触发的 build → 不用本 skill, 走 Forgejo workflow (本 skill 仅 owner action)
  └─ 已有镜像, 只是要部署 → 用 aether-deploy
```

**不要用的场景**:
- Symptom A 节点自省 (用 `aether status` 而非本 skill — 自省 #27 Symptom A 显式 out-of-scope)
- 多 arch / SBOM / build cache 命中分析 — 本 skill skeleton 不做 (Aria #111 确认 commercial launch 才相关)
- programmatic / 脚本调用 — skill 仅 AI/人触发 (M2-M6 不需要 CLI/HTTP API, per Aria #111 Q1)

## 入参契约

| 参数 | 说明 | 示例 |
|------|------|------|
| `git_ref` | 本地 checkout 里要 build 的 ref (branch/tag/sha) | `master`, `feature/aria-m5`, `a5f0ef6` |
| `dockerfile_path` | Dockerfile 路径,**相对**仓库根目录 | `Dockerfile`, `docker/runner.Dockerfile` |
| `registry_path` | 目标 registry 全路径不含 tag | `forgejo.10cg.pub/10CG/aria-runner` |
| `build_args` (可选) | docker build --build-arg 数组 | `[{K: NODE_VERSION, V: 22}]` |
| `tag_strategy` (可选) | `immutable` (默认, short-sha) / `latest` / `both` | `immutable` |

## 输出契约 (per Aria #111 Q3)

**成功**:
```yaml
status: ok
image_sha256: "sha256:abc123…"            # 必需 (RepoDigests)
registry_url: "forgejo.10cg.pub/10CG/aria-runner@sha256:abc123…"  # 必需, 全路径
source_commit_sha: "a5f0ef6abc…"          # 必需, 防 handoff 漂移
source_git_ref: "feature/aria-m5"         # 视同必需
build_node: "heavy-3"                      # nice-to-have
build_duration_sec: 87                     # nice-to-have
alloc_id: "<nomad alloc id>"               # 诊断用
```

**失败**:
```yaml
status: error
error_code: <下表 8 枚举之一>
message: "<诊断信息>"
alloc_id: "<nomad alloc id, 若 dispatch 已发生>"
```

## 错误码 (8 枚举)

| 来源 | 码 | 触发 |
|------|----|------|
| 节点 | `source_not_found` (exit 20) | 共享卷上 ctx tarball 缺失 / tar 解包失败 |
| 节点 | `dockerfile_invalid` (exit 21) | 解包后 dockerfile_path 不存在 |
| 节点 | `build_failed` (exit 22) | `docker build` 非零 / inspect 拿不到 digest |
| 节点 | `push_failed` (exit 23) | `docker push` 失败 (含 registry auth 陈旧 token) |
| skill | `scp_failed` | 本地打包 / scp 到共享卷失败 |
| skill | `dispatch_failed` | pre-flight registry-auth parity 失败 / `aether dev run` 拒绝 |
| skill | `alloc_timeout` | 1800s deadline 内 alloc 未到终态 |
| skill | `result_missing` | alloc 终态但共享卷无 result.json → 视为 build_failed + alloc_id |

## 编排步骤 (skill 执行流程)

**前置**: 你在 git checkout 里 (本地 owner machine, 非 heavy 节点)。

### Step 1 — 解析 git ref + 抓 sha

```bash
JOB_ID="$(date +%s)-$$"
SRC_SHA="$(git rev-parse "$git_ref")"        # 完整 sha, 用作 immutable tag + label
SRC_REF="$git_ref"                            # 用户给的原始字符串 (branch name 等)
SHORT_SHA="${SRC_SHA:0:7}"
TAG="${SHORT_SHA}"   # tag_strategy=immutable default
```

### Step 2 — 本地 recursive clone + tar 工作树

```bash
CTX_LOCAL="/tmp/ctx-${JOB_ID}.tgz"
CLONE_DIR="/tmp/clone-${JOB_ID}"

# 从 cwd 推断 origin URL (要求 owner 在目标 git 仓的 checkout 里运行 skill)
GIT_URL=$(git remote get-url origin 2>/dev/null) \
  || { emit_error "scp_failed" "cwd not a git repo or no 'origin' remote — run skill from inside target git checkout" ; return 1; }

# Recursive clone of pinned ref. --recurse-submodules 展开所有子模块 (gitlink → 真文件),
# 与单纯 git archive 不同 —— archive 对 meta-repo 子模块只导出空目录占位 (Aria O2 踩坑)。
# --depth=1 + --shallow-submodules 提速 (我们只要那个 commit 的树, 不要历史)。
git clone --recurse-submodules --shallow-submodules --depth=1 \
  --branch "$git_ref" "$GIT_URL" "$CLONE_DIR" \
  || { emit_error "scp_failed" "git clone --recurse-submodules failed for ${GIT_URL}#${git_ref}" ; return 1; }

SRC_SHA=$(cd "$CLONE_DIR" && git rev-parse HEAD)
SRC_REF="$git_ref"
SHORT_SHA="${SRC_SHA:0:7}"
TAG="${SHORT_SHA}"

# Tar 工作树 (含 submodule 展开内容), 排除 .git 减小 context 体积 + 避开 .git 内文件可能的
# COPY 副作用。这个 tar 是 build context, 进 host docker daemon 解 build。
tar -czf "$CTX_LOCAL" -C "$CLONE_DIR" \
  --exclude=.git --exclude='**/.git' --exclude='.gitmodules' \
  . \
  || { emit_error "scp_failed" "tar working tree failed" ; return 1; }
rm -rf "$CLONE_DIR"
```

**为何不再用 `git archive`** (D4 amendment, 2026-05-22): Aria #111 owner 答复实证
`git archive` 对 meta-repo 只导出 gitlink 占位, 子模块目录是空的 → Dockerfile `COPY aria/`
之类的指令找不到内容 → build_failed。10CG 生态约 1/3 项目用 submodule (Aether/Aria/nexus/silknode
+ 跨项目共享的 `standards` 子模块), 是主流 pattern 非边缘。

防漂移属性**不变**: `git clone <pinned-ref>` 取的也是已 commit 的内容, 不含本地未 commit 改动。
源凭据用 owner 本地 git config (SSH key / .git-credentials), **不向 heavy 节点引入新 secret**
(Aria O2 在容器内 clone 踩的 R1 insteadOf / R3 ssh→https / R4 sslVerify 都因此在本设计无需消化)。

### Step 3 — Pre-flight registry-auth parity (§3a)

候选节点 = Nomad `/v1/nodes` 过滤 `node.class=heavy_workload` 的当下集合 (**不要硬编码** heavy-1/2/3, 新增节点需自动覆盖):

```bash
REGISTRY_HOST="${registry_path%%/*}"    # forgejo.10cg.pub
mapfile -t CANDIDATES < <(curl -sf "${NOMAD_ADDR}/v1/nodes" | \
  python3 -c "import json,sys;[print(n['Address']) for n in json.load(sys.stdin) if n.get('NodeClass')=='heavy_workload' and n.get('Status')=='ready']")

for HOST in "${CANDIDATES[@]}"; do
  if ! ssh -o ConnectTimeout=5 "root@${HOST}" \
    "python3 -c \"import json,sys;a=json.load(open('/root/.docker/config.json')).get('auths',{});sys.exit(0 if '${REGISTRY_HOST}' in a else 1)\"" 2>/dev/null; then
    emit_error "dispatch_failed" "precheck: node ${HOST} ~/.docker/config.json missing auth for ${REGISTRY_HOST} (parity drift; #45 rotation may have changed value but cannot detect from skill — see proposal §3a 保护边界)" ; return 1
  fi
done
```

**保护边界 (诚实)**: 仅查 key 在不在, **不验 token 有效性**。#45 token 轮换 (值变 key 在) → pre-flight 通过, 仍走 dispatch 后 `push_failed`(23) 优雅降级。precheck 仅消除 "节点完全未配置" 的非确定性。

### Step 4 — scp ctx 到共享 virtiofs

```bash
STAGE_NODE="${CANDIDATES[0]}"   # 任意一个 — virtiofs 共享 inode (CLAUDE.md #56), build 落点与 scp 目标解耦
CTX_REMOTE="/opt/aether-volumes/_build-ctx/${JOB_ID}.tgz"
RESULT_REMOTE="/opt/aether-volumes/_build-ctx/${JOB_ID}.result.json"
ssh "root@${STAGE_NODE}" "mkdir -p /opt/aether-volumes/_build-ctx"
scp "$CTX_LOCAL" "root@${STAGE_NODE}:${CTX_REMOTE}" || { emit_error "scp_failed" "scp ctx to ${STAGE_NODE}" ; return 1; }
```

### Step 5 — scp task-script + 渲染 HCL + dispatch

**关键设计** (smoke iteration 后修订): task-script.sh 不再 inline 进 HCL heredoc
(HCL2 heredoc 会把 bash `${VAR}` 当 HCL 插值解析, escape 后又触发其他 parse 错)。
改为**和 ctx 一起 scp 到共享卷**, HCL 只引用绝对路径。架构反而更简单。

```bash
# 5a. scp task-script.sh 到共享卷 (与 ctx 同目录)
SCRIPT_REMOTE="/opt/aether-volumes/_build-ctx/${JOB_ID}.sh"
scp "${CLAUDE_PLUGIN_ROOT}/skills/aether-build-container/references/task-script.sh" \
    "root@${STAGE_NODE}:${SCRIPT_REMOTE}" \
    || { emit_error "scp_failed" "scp task-script to ${STAGE_NODE}" ; return 1; }
ssh "root@${STAGE_NODE}" "chmod +x ${SCRIPT_REMOTE}"

# 5b. 渲染 HCL (纯 sed 替换 __VAR__, 无 inline body, 无 awk 多行陷阱)
HCL_TPL="${CLAUDE_PLUGIN_ROOT}/skills/aether-build-container/references/job-template.hcl"
RENDERED="/tmp/job-${JOB_ID}.hcl"
sed -e "s|__JOB_ID__|${JOB_ID}|g" \
    -e "s|__CTX_PATH__|${CTX_REMOTE}|g" \
    -e "s|__RESULT_PATH__|${RESULT_REMOTE}|g" \
    -e "s|__SCRIPT_PATH__|${SCRIPT_REMOTE}|g" \
    -e "s|__DOCKERFILE_PATH__|${dockerfile_path}|g" \
    -e "s|__BUILD_ARGS__|${BUILD_ARGS_STR}|g" \
    -e "s|__REGISTRY__|${registry_path}|g" \
    -e "s|__TAG__|${TAG}|g" \
    -e "s|__SRC_REF__|${SRC_REF}|g" \
    -e "s|__SRC_SHA__|${SRC_SHA}|g" \
    "$HCL_TPL" > "$RENDERED"

# 5c. dispatch (确保 NOMAD_ADDR 在 env 中, aether dev run 默认 fallback 127.0.0.1:4646)
export NOMAD_ADDR="${NOMAD_ADDR:-http://192.168.69.70:4646}"
aether dev run "$RENDERED" --name "build-container-${JOB_ID}" --yes --json \
  || { emit_error "dispatch_failed" "aether dev run rejected HCL or Nomad unreachable" ; return 1; }
```

清理时 Step 8 加: `ssh "root@${STAGE_NODE}" "rm -f ${SCRIPT_REMOTE}"`

### Step 6 — 轮询 alloc 收敛 (deadline 1800s, 复用 qa-M1 模式)

```bash
DEADLINE=$(( $(date +%s) + 1800 ))
JOB="build-container-${JOB_ID}"
while :; do
  ST=$(aether status "$JOB" --json 2>/dev/null || echo '{}')
  RUNNING=$(echo "$ST" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('data',{}).get('job',{}).get('allocations',{}).get('running',0))" 2>/dev/null || echo 0)
  FAILED=$(echo "$ST" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());print(d.get('data',{}).get('job',{}).get('allocations',{}).get('failed',0))" 2>/dev/null || echo 0)
  COMPLETE=$(echo "$ST" | python3 -c "import json,sys;d=json.loads(sys.stdin.read());s=d.get('data',{}).get('job',{}).get('status','');print('yes' if s=='dead' else 'no')" 2>/dev/null || echo no)
  if [ "$COMPLETE" = "yes" ] || [ "${FAILED:-0}" -ge 1 ]; then break; fi
  [ "$(date +%s)" -ge "$DEADLINE" ] && { emit_error "alloc_timeout" "alloc did not reach terminal within 1800s" ; return 1; }
  sleep 10
done
```

### Step 7 — 读 result.json + 输出 yaml

```bash
RESULT_JSON="$(ssh "root@${STAGE_NODE}" "cat ${RESULT_REMOTE} 2>/dev/null" || echo '')"
if [ -z "$RESULT_JSON" ]; then
  # alloc 终态但无 result.json — 节点脚本死在写 result 前; 视为 build_failed + alloc_id
  ALLOC_ID=$(aether status "$JOB" --json | python3 -c "import json,sys;print(json.load(sys.stdin).get('data',{}).get('job',{}).get('allocations',{}).get('items',[{}])[0].get('id','unknown'))" 2>/dev/null || echo unknown)
  emit_error "result_missing" "alloc terminal but no result.json (alloc=${ALLOC_ID}); inspect with 'nomad alloc logs ${ALLOC_ID}'"
fi
echo "$RESULT_JSON" | python3 -c "import json,sys,yaml;print(yaml.safe_dump(json.loads(sys.stdin.read())))"   # 输出 yaml 给 owner
```

### Step 8 — Finally (永远执行)

```bash
ssh "root@${STAGE_NODE}" "rm -f /opt/aether-volumes/_build-ctx/${JOB_ID}.tgz /opt/aether-volumes/_build-ctx/${JOB_ID}.result.json /opt/aether-volumes/_build-ctx/${JOB_ID}.sh" 2>/dev/null || true
rm -f "$CTX_LOCAL" "$RENDERED" 2>/dev/null || true
```

清理归 **skill 生命周期所有权**, 不依赖节点 trap。节点 trap 只清自己解出来的 WORK_DIR `/opt/aether-volumes/_build-ctx/work-<id>/`(DooD 后从原 `/tmp/b-<id>` 迁到共享卷, 因 host daemon 必须见同 inode 才能解析 build context;tgz/result.json/sh 由 skill finally 清)。临时 job 可能死, 共享卷清理不能托付它。

## 关键设计说明

**push 鉴权 (诚实)**: build job **不注入凭据**。`docker push` 复用宿主 docker daemon 既有 `~/.docker/config.json` + insecure-registries (Forgejo runner 8 个月已建立)。这是 **#32 Vault 对本 skeleton 非阻塞的肯定性理由**: skill scope 内零 secret 注入。代价: 见 Step 3 pre-flight 的保护边界局限 + push_failed 优雅降级路径。

**scp 目标节点任意性**: `/opt/aether-volumes` 是 NFS 经 virtiofs 重新挂载到 3 台 heavy, **同一 inode 空间** (CLAUDE.md #56)。scp 到哪台都行, Nomad 把 build 放到哪台, 那台都能读到 — **scp 目标与 build 落点解耦**。

**资源预留 vs 实际占用 (D5)**: HCL 里的 `cpu=2000/memory=3000` 是 Nomad **binpack 转向信号** (让调度排除饱和节点), **不是 build 实际开销的硬上限** — `docker build` 跑在宿主 daemon, 不在 Nomad 给 raw_exec task 的 cgroup 记账。skeleton 接受此限制, 真隔离 (专用节点 / kaniko) 留迭代。

**prune 后台化原因**: `docker builder prune` 在 result.json 写入**后**以 `( ... & )` 子 shell 后台运行。否则一个挂起的 prune 会占住 raw_exec slot 到 1800s alloc_timeout, skill 误判成功 build 为 timeout。result.json 落盘 = 成功判定点。

## 边界 (out-of-scope, 留迭代)

- 节点自省 (#27 Symptom A `aether-inventory`) — 后续 issue
- 真隔离 (专用 build 节点 / kaniko rootless sandbox)
- 精确"最空节点" affinity (需 skill 预飞查 Nomad alloc 量注软 affinity)
- programmatic CLI/HTTP API (M3+ 跨项目复用才重评)
- build cache 命中 / SBOM / multi-arch / SLSA (commercial launch ~2026-08+ 才相关)
- token validity 探测 (Step 3 pre-flight 仅查 key 在否)

## 参考

- Spec: `openspec/changes/build-container-skeleton/proposal.md`
- 决策: `.aria/decisions/27-build-container-skeleton-brainstorm-2026-05-18.md`
- Aria #111: 契约 / 错误码 / programmatic 需求权威输入
- qa-M1 alloc 轮询模式: `tests/smoke/run-rotation-smoke.sh` (commit cbc482d)
- 共享 virtiofs host volume: CLAUDE.md "Stateful Job Host Volumes" (#56)
- HCL 模板: `references/job-template.hcl`
- 节点脚本: `references/task-script.sh`
