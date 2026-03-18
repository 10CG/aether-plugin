# Aether 环境诊断报告

**诊断时间**: 2026-03-18
**机器**: linux (6.17.9-1-pve)
**用户**: dev

---

## 总览

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Aether CLI | PASS | v0.7.2 已安装 |
| 全局配置文件 | PASS | ~/.aether/config.yaml 存在且内容正确 |
| 项目配置文件 | INFO | 不存在（非必须，全局配置已覆盖） |
| Nomad 连接 | PASS | http://192.168.69.70:4646 响应正常 (0.9ms) |
| Consul 连接 | PASS | http://192.168.69.70:8500 响应正常 (2.9ms) |
| SSH heavy-1 | PASS | root@192.168.69.80 连接成功 |
| CI/CD 配置 | PASS | Forgejo workflows 已配置 |
| Go 环境 | PASS | go1.26.1 已安装 |
| Forgejo CLI | PASS | forgejo CLI 可用 |
| Nomad CLI (本地) | WARN | 未安装（非必须，可通过 API 操作） |
| Consul CLI (本地) | WARN | 未安装（非必须，可通过 API 操作） |
| Docker (本地) | WARN | 未安装（构建在远程节点执行） |

**综合结论**: 环境基本就绪，核心功能可正常使用。有 3 个非阻断性警告。

---

## 1. Aether CLI

**状态**: PASS

```
位置: /usr/local/bin/aether
版本: aether 0.7.2
```

CLI 已正确安装且可执行。

---

## 2. 配置文件

**状态**: PASS

### 全局配置 (~/.aether/config.yaml)

```yaml
cluster:
  consul_addr: http://192.168.69.70:8500
  nomad_addr: http://192.168.69.70:4646
  registry: forgejo.10cg.pub
  registry_url: forgejo.10cg.pub
```

配置验证结果：
- Nomad 地址: 正确，API 可达
- Consul 地址: 正确，API 可达
- Registry: forgejo.10cg.pub，类型自动检测为 Forgejo Container Registry
- Registry 认证: FORGEJO_TOKEN 环境变量已配置 (fallback chain 可用)
- Nomad Token: 未配置（ACL 未启用，无需 Token）

### 项目配置 (./.aether/config.yaml)

不存在。这不是问题 -- 全局配置已提供所有必要参数。仅在需要项目级覆盖时才需要创建。

---

## 3. 集群连接

### Nomad (http://192.168.69.70:4646)

**状态**: PASS

- API 响应: HTTP 200, 0.9ms
- ACL: 未启用
- 广播地址: 192.168.69.70:4646

**节点状态** (8/8 ready):

| 节点 | IP | 状态 |
|------|----|------|
| heavy-1 | 192.168.69.80 | ready |
| heavy-2 | 192.168.69.81 | ready |
| heavy-3 | 192.168.69.82 | ready |
| light-1 | 192.168.69.90 | ready |
| light-2 | 192.168.69.91 | ready |
| light-3 | 192.168.69.92 | ready |
| light-4 | 192.168.69.93 | ready |
| light-5 | 192.168.69.94 | ready |

**运行中的 Jobs** (17 个):

| Job | 状态 | 类型 |
|-----|------|------|
| dev-db | running | service |
| kairos-dev | running | service |
| kairos-prod | running | service |
| mailpit | running | service |
| nexus-api-dev | running | service |
| nexus-db-dev | running | service |
| nexus-redis-dev | running | service |
| openstock-dev | running | service |
| psych-ai-supervision-dev | running | service |
| silknode-gateway | running | service |
| silknode-web | running | service |
| todo-web-backend-dev | running | service |
| todo-web-backend-prod | running | service |
| todo-web-frontend-dev | running | service |
| todo-web-frontend-prod | running | service |
| traefik | running | service |
| wecom-relay | running | service |

所有 17 个 Job 均为 running 状态，集群运行健康。

### Consul (http://192.168.69.70:8500)

**状态**: PASS

- API 响应: HTTP 200, 2.9ms
- Leader: 192.168.69.70:8300

**已注册节点** (11 个):

| 节点 | IP |
|------|----|
| heavy-1 | 192.168.69.80 |
| heavy-2 | 192.168.69.81 |
| heavy-3 | 192.168.69.82 |
| infra-server-1 | 192.168.69.70 |
| infra-server-2 | 192.168.69.71 |
| infra-server-3 | 192.168.69.72 |
| light-1 | 192.168.69.90 |
| light-2 | 192.168.69.91 |
| light-3 | 192.168.69.92 |
| light-4 | 192.168.69.93 |
| light-5 | 192.168.69.94 |

**已注册服务**: 27 个（包括 consul, nomad, traefik 及各应用服务）

---

## 4. SSH 连接 (heavy-1)

**状态**: PASS

```
目标: root@192.168.69.80 (heavy-1)
主机名: heavy-1
内核: 6.1.0-43-amd64
```

### SSH 密钥

| 密钥类型 | 路径 | 状态 |
|----------|------|------|
| Ed25519 | ~/.ssh/id_ed25519 | 存在, 权限 600 (正确) |
| RSA | ~/.ssh/id_rsa | 不存在 |
| ECDSA | ~/.ssh/id_ecdsa | 不存在 |

### SSH Config

```
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

SSH 配置正确，使用 Ed25519 密钥，已禁用 StrictHostKeyChecking 简化连接。

### heavy-1 节点服务状态

| 服务 | 状态 | 版本 |
|------|------|------|
| Nomad | active | v1.11.2 (2026-02-11) |
| Docker | active | 29.2.1 |

### Host Volumes 目录

`/opt/nomad/host_volumes/` 目录不存在。如果需要使用 `aether volume create`，该目录会在首次创建 volume 时自动生成。

---

## 5. CI/CD 配置

**状态**: PASS

### Forgejo Workflows

位置: `/home/dev/Aether/.forgejo/workflows/`

| 文件 | 说明 |
|------|------|
| ci.yml | CI 流水线 (test + lint) |
| cli-release.yml | CLI 发布流水线 |

### ci.yml 内容摘要

- **触发条件**: push 到 master/feature/* 分支, PR 修改 aether-cli/** 时
- **Go 版本**: 1.22
- **Jobs**:
  - `test`: 运行 `go test -v -race ./...`
  - `lint`: 运行 golangci-lint

### Git Remotes

| 名称 | URL |
|------|-----|
| origin | ssh://forgejo@forgejo.10cg.pub/10CG/aether-plugin.git |
| github | git@github.com:10CG/aether-plugin.git |

双远程配置正确（Forgejo + GitHub 镜像）。

### Forgejo CLI

`forgejo` CLI 工具已安装 (`/home/dev/.npm-global/bin/forgejo`)，可用于 API 操作。

---

## 6. 开发工具链

| 工具 | 状态 | 版本/路径 |
|------|------|-----------|
| Go | PASS | go1.26.1 (/usr/local/go/bin/go) |
| Aether CLI | PASS | 0.7.2 (/usr/local/bin/aether) |
| Forgejo CLI | PASS | /home/dev/.npm-global/bin/forgejo |
| Git | PASS | 已配置双远程 |
| Nomad CLI | WARN | 未安装（本地） |
| Consul CLI | WARN | 未安装（本地） |
| Docker | WARN | 未安装（本地） |

---

## 警告项与修复建议

### WARN-1: 本地未安装 Nomad CLI

**影响**: 无法在本地直接使用 `nomad` 命令（如 `nomad node status`、`nomad job run` 等）。
**当前替代方案**: 可通过 `aether` CLI 或直接调用 Nomad HTTP API 操作。
**修复建议**（可选）:

```bash
# 安装 Nomad CLI
curl -fsSL https://releases.hashicorp.com/nomad/1.11.2/nomad_1.11.2_linux_amd64.zip -o /tmp/nomad.zip
unzip /tmp/nomad.zip -d /tmp
sudo mv /tmp/nomad /usr/local/bin/
export NOMAD_ADDR=http://192.168.69.70:4646
```

### WARN-2: 本地未安装 Consul CLI

**影响**: 无法在本地直接使用 `consul` 命令。
**当前替代方案**: 可通过 Consul HTTP API 操作。
**修复建议**（可选）:

```bash
# 安装 Consul CLI
curl -fsSL https://releases.hashicorp.com/consul/1.20.0/consul_1.20.0_linux_amd64.zip -o /tmp/consul.zip
unzip /tmp/consul.zip -d /tmp
sudo mv /tmp/consul /usr/local/bin/
export CONSUL_HTTP_ADDR=http://192.168.69.70:8500
```

### WARN-3: 本地未安装 Docker

**影响**: 无法在本地构建容器镜像。
**当前替代方案**: Docker 构建在 CI/CD (Forgejo Runner) 或远程节点上执行，heavy-1 已安装 Docker 29.2.1。
**修复建议**: 如果不需要本地构建镜像，可忽略。如需安装:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker dev
```

---

## 总结

环境诊断通过。Aether 的核心工作流（CLI 使用、集群管理、SSH 操作、CI/CD）全部就绪：

1. **Aether CLI** v0.7.2 已安装，配置文件指向正确的集群地址
2. **Nomad 集群** 8 节点全部 ready，17 个 Job 正常运行
3. **Consul 集群** 11 节点注册，27 个服务正常
4. **SSH 到 heavy-1** 连接正常，密钥和配置均正确
5. **CI/CD** Forgejo workflows 已配置（test + lint + release）
6. **Registry** 自动检测为 Forgejo 类型，FORGEJO_TOKEN 已配置

3 个警告项（nomad/consul/docker CLI 未在本地安装）均为非阻断性问题，不影响日常使用。
