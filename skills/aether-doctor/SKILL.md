---
name: aether-doctor
description: |
  Aether 环境诊断工具。检查 CLI、配置、集群连接、SSH、CI/CD 配置等环境状态，更新配置缓存。

  使用场景："诊断环境"、"检查配置"、"环境有问题"、"SSH 连接失败"、"CI 配置错误"、"首次使用"
argument-hint: "[--ssh|--cluster|--ci|--refresh] [--fix]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
dependencies:
  cli:
    required: false
    role: "此 Skill 负责安装和检测 CLI，不是依赖方"
    install_capability: true
---

# Aether 环境诊断 (aether-doctor)

> **版本**: 2.1.0 | **优先级**: P0

## 快速开始

```
/aether:aether-doctor           # 完整诊断
/aether:aether-doctor --ssh     # 仅 SSH 检查
/aether:aether-doctor --cluster # 仅集群连接
/aether:aether-doctor --fix     # 自动修复问题
```

## 诊断项目

| 项目 | 检查内容 | 修复建议 |
|------|---------|---------|
| aether CLI | 安装状态、版本 | 自动安装 |
| 配置文件 | 格式、地址有效性 | 引导配置 |
| 集群连接 | Nomad/Consul API | 网络检查 |
| SSH 配置 | 密钥、权限、连接 | 提供命令 |
| CI/CD | Secrets 配置 | 修复建议 |

---

## 诊断流程

每一项都标 ✓ 通过 / ✗ 失败 / ! 警告，最后按 [输出示例](references/output-examples.md) 汇总；失败项附修复命令。

### Step 0: 确定缓存位置

```bash
if [ -f "./.aether/config.yaml" ]; then
  CACHE_FILE="./.aether/environment.yaml"
else
  CACHE_FILE="$HOME/.aether/environment.yaml"
fi
```

### Step 1: 检查 aether CLI

**检测逻辑**:
1. `command -v aether` → PATH 中
2. `~/.aether/aether` → 用户安装
3. `~/.aether/aether.exe` → Windows

**如果未安装或版本过低**:
- 提供交互式安装选项
- 详见 [CLI 安装流程](references/cli-installation.md)

### Step 1.5: 运行 `aether doctor`（CLI 可用时先做这一步）

CLI 自带集群侧诊断：Nomad / Consul 连通、Consul DNS、节点 driver、host volume、孤儿 job、模板陷阱、PAT 时效等数十项检查。

```bash
OUT=$(aether doctor --json); RC=$?    # 先存退出码：接了管道，$? 就是 jq 的
echo "$OUT" | jq '{summary: .data.summary, problems: [.data.checks[] | select(.status != "PASS") | {name, status, message}]}'
echo "exit=$RC"
```

- 完整运行会 SSH 到 heavy 节点，约一分钟。退出码 0 = 全部 PASS / WARN，1 = 至少一项 FAIL；2 / 3 = doctor 本身没跑成（配置读不了、连不上 Nomad），用 `echo "$OUT" | jq .error` 看原因，再按 Step 2–4 手工查。
- 按 FAIL / WARN 的 check 名深入：单项用 `aether doctor --check <name>`（只接受 `--check`，不接位置参数），单节点用 `--node <name>`。
- **CLI 的结果只决定先查哪里，不替代下面的手工检查。** 这几项 CLI 不查，照常按对应步骤做：
  - 配置的 Nomad 地址是否在 Server 列表里、配置文件格式（Step 2–4）
  - 本机 SSH 密钥与权限、`~/.ssh/config` 对 heavy / light 的配置、逐台节点的 SSH 连接（Step 5–6）。CLI 没有逐节点的 SSH 检查，只在部分检查里连 heavy 节点
  - CI secrets（Step 7）
- 用户报了具体症状（某几台 SSH 连不上、Nomad 超时等），对应的步骤照手工流程查到底；CLI 全 PASS 也不跳过。
- CLI 不可用时整套按 Step 2–7 手工检查。

### Step 2: 检查配置文件

```bash
# 检查配置（配置里可能有 cluster.nomad_token / consul_token，只看去掉凭据键之后的内容）
for f in ~/.aether/config.yaml ./.aether/config.yaml; do
  [ -f "$f" ] && { echo "== $f"; yq '(.. | select(tag == "!!map")) |= with_entries(select(.key | test("(?i)token|secret|password") | not))' "$f"; }
done
# 没有 yq 时只看地址行，不要 cat 整份文件
grep -E '^[[:space:]]*(nomad_addr|consul_addr|registry):' ~/.aether/config.yaml ./.aether/config.yaml 2>/dev/null

# 配置优先级：环境变量 > 项目 ./.aether/config.yaml > 全局 ~/.aether/config.yaml > 默认值
# 项目级文件存在时整份替代全局（不逐字段合并），缺的字段用默认值；命令不读 .env
```

### Step 3-4: 集群验证和连接测试

Step 1.5 跑过时先看它对 Nomad / Consul / DNS 的结论。配置的 Nomad 地址是否在 Server 列表里它不查，照 [集群拓扑和验证](references/cluster-validation.md) 核对（不拿 leader 判断）；连不上、超时这类症状也照该文档查到底。CLI 不可用时整套照它做。

### Step 5-6: SSH 检查和连接测试

下面三项每次都做，不论失败的是哪几台、Step 1.5 跑没跑过：

1. **本机**：密钥存在与权限 `stat -c '%a %n' ~/.ssh ~/.ssh/id_*`（目录 700、私钥 600）；私钥文件在、而 `ssh-keygen -y -P '' -f <私钥> >/dev/null` 失败，说明它有口令 —— CLI 不走 ssh-agent、也不问口令，用不了这把；`~/.ssh/config` 对 heavy-* / light-* 的配置：`ssh -G <节点名> | grep -E '^(hostname|user|port|identityfile|proxyjump) '`
2. **逐台测 Nomad 里的全部节点**：CLI 的 SSH 不读 `~/.ssh/config`。`aether volume` 按 Nomad 里的节点 IP 连，用户默认 root，密钥用 `--ssh-key` 指定的，否则依次试 `~/.ssh/id_ed25519`、`id_rsa`、`id_ecdsa`（都没有就报 `no authentication method available`）。所以先按 CLI 的条件测（`-i` 换成 CLI 用的那把），再用节点名按终端的路径测；终端通而 CLI 条件不通，差别就在 `~/.ssh/config`（比如它给节点配了另一把 IdentityFile）
   ```bash
   # NOMAD_ADDR 用 Step 2 核对过的地址
   curl -s "$NOMAD_ADDR/v1/nodes" | jq -r '.[] | "\(.Name) \(.Address)"' | while read -r name ip; do
     r=$(ssh -n -F /dev/null -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=5 root@"$ip" hostname 2>&1) \
       && echo "OK   $name $ip" || echo "FAIL $name $ip: $(echo "$r" | tail -1)"
   done
   ```
3. **完整报告**：正常 / 异常各几台；失败节点逐台写错误类型（`Connection timed out` / `Connection refused` / `Permission denied` / `Host key verification failed`），按类型给不同修法。`--fix` 自动做的只限本机（权限、known_hosts 旧条目），节点侧（authorized_keys、sshd）给出命令由操作员执行；动手前都先问

分层排查、决策树与修复命令详见 [SSH 诊断](references/ssh-diagnostics.md)

### Step 7: CI/CD 配置检查（可选）

详见 [CI 配置检查](references/ci-configuration.md)

### Step 8: 更新缓存

详见 [环境缓存格式](references/environment-cache.md)

---

## 详细参考

| 主题 | 文档 |
|------|------|
| CLI 安装流程 | [cli-installation.md](references/cli-installation.md) |
| 集群拓扑和验证 | [cluster-validation.md](references/cluster-validation.md) |
| SSH 诊断 | [ssh-diagnostics.md](references/ssh-diagnostics.md) |
| CI 配置检查 | [ci-configuration.md](references/ci-configuration.md) |
| 环境缓存格式 | [environment-cache.md](references/environment-cache.md) |
| 输出示例 | [output-examples.md](references/output-examples.md) |

---

## 与其他 Skills 的集成

### 缓存读取示例

```bash
# 获取集群信息
SERVERS=$(yq '.cluster.servers[] | .ip' ./.aether/environment.yaml)
LEADER=$(yq '.cluster.current_leader' ./.aether/environment.yaml)
HEAVY_NODES=$(yq '.cluster.clients[] | select(.class == "heavy_workload") | .ip' ./.aether/environment.yaml)
```

### 错误诊断建议

| 错误类型 | 建议 |
|---------|-----|
| `command not found` | 运行 `/aether:aether-doctor` 安装 CLI |
| `connection refused` | 运行 `/aether:aether-doctor --cluster` |
| `permission denied (SSH)` | 运行 `/aether:aether-doctor --ssh` |

---

## 命令行等价操作

```bash
# 检查 CLI
aether version

# 集群侧完整诊断 / 单项 / 单节点
aether doctor --json
aether doctor --check pat_age,orphan_jobs --json
aether doctor --node heavy-1

# 检查集群（CLI 不可用时）
curl -s http://192.168.69.70:4646/v1/status/leader
curl -s http://192.168.69.70:4646/v1/nodes

# 测试 SSH
ssh -o ConnectTimeout=5 root@192.168.69.80 "hostname"
```

---

**Skill 版本**: 2.0.0
**最后更新**: 2026-03-12
**维护者**: 10CG Infrastructure Team
