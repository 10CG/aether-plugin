Aether 环境诊断
===============
诊断时间: 2026-03-18 (aether-doctor v2.1.0)
配置来源: 全局 (~/.aether/config.yaml)

---

## [OK] aether CLI

| 项目 | 值 |
|------|-----|
| 版本 | 0.7.2 |
| 路径 | /usr/local/bin/aether |
| 状态 | 已安装，版本正常 |

---

## [OK] 配置验证

| 项目 | 值 |
|------|-----|
| 配置地址 | http://192.168.69.70:4646 |
| Consul 地址 | http://192.168.69.70:8500 |
| Registry | forgejo.10cg.pub |
| 状态 | 配置有效 (地址在 Server 列表中) |

集群 Server 列表:
- infra-server-1: 192.168.69.70 (alive)
- infra-server-2: 192.168.69.71 (alive, **leader**)
- infra-server-3: 192.168.69.72 (alive)

> 注: 配置指向 infra-server-1 (192.168.69.70)，当前 leader 是 infra-server-2 (192.168.69.71)。
> 这是正常的 -- 任意 Server 都可接受 API 请求，leader 会自动转发。

---

## [OK] 集群连接

| 服务 | 版本 | 状态 |
|------|------|------|
| Nomad | 1.11.2 (build 2026-02-11) | 正常 |
| Consul | 1.22.3 | 正常 |

### Nomad 节点状态: 8/8 ready

| 节点 | IP | 类型 | 状态 |
|------|-----|------|------|
| heavy-1 | 192.168.69.80 | heavy_workload | ready |
| heavy-2 | 192.168.69.81 | heavy_workload | ready |
| heavy-3 | 192.168.69.82 | heavy_workload | ready |
| light-1 | 192.168.69.90 | light_exec | ready |
| light-2 | 192.168.69.91 | light_exec | ready |
| light-3 | 192.168.69.92 | light_exec | ready |
| light-4 | 192.168.69.93 | light_exec | ready |
| light-5 | 192.168.69.94 | light_exec | ready |

---

## [FIXED] SSH 连接

### 诊断结果

**当前实际测试**: 所有 SSH 连接均成功 (8/8 节点)

| 节点 | IP | SSH (hostname) | SSH (IP) | 状态 |
|------|-----|----------------|----------|------|
| heavy-1 | 192.168.69.80 | OK | OK | 正常 |
| heavy-2 | 192.168.69.81 | OK | OK | 正常 |
| heavy-3 | 192.168.69.82 | OK | OK | 正常 |
| light-1 | 192.168.69.90 | OK | - | 正常 |
| light-2 | 192.168.69.91 | OK | - | 正常 |
| light-3 | 192.168.69.92 | OK | - | 正常 |
| light-4 | 192.168.69.93 | OK | - | 正常 |
| light-5 | 192.168.69.94 | OK | - | 正常 |

### 发现的配置问题 (已修复)

SSH 密钥和网络连接本身是正常的，但发现了一个 **SSH 配置缺陷**，可能导致间歇性连接失败:

**问题**: `~/.ssh/config` 中的 `Host heavy-* light-*` 规则仅匹配主机名，不匹配 IP 地址。

当通过 IP 地址 (如 `ssh root@192.168.69.81`) 连接时:
1. `StrictHostKeyChecking` 回落为默认值 `ask` (而非 `no`)
2. 使用所有默认密钥类型 (而非仅 `id_ed25519`)
3. 没有 `ConnectTimeout` 限制

这意味着:
- 首次通过 IP 连接新节点时，会弹出 host key 确认提示 (在非交互环境中会直接失败)
- 如果 known_hosts 中的 host key 与节点不匹配 (如节点重装后)，会直接拒绝连接
- 没有超时设置，网络问题时可能长时间挂起

#### 修复内容

**文件**: `~/.ssh/config`

修改前:
```
Host heavy-* light-*
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

修改后:
```
Host heavy-* light-* 192.168.69.8? 192.168.69.9?
    User root
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    ConnectTimeout 10
```

**变更说明**:
1. 添加 `192.168.69.8?` 和 `192.168.69.9?` -- 使 SSH 配置也匹配 IP 地址方式的连接
2. 添加 `ConnectTimeout 10` -- 防止网络问题时无限等待 (参考 aether-doctor 推荐配置)

### SSH 密钥状态

| 项目 | 值 |
|------|-----|
| 密钥路径 | ~/.ssh/id_ed25519 |
| 密钥权限 | 600 (正确) |
| 目录权限 | 700 (正确) |
| 密钥指纹 | SHA256:JibKXgzlKMxhh1NKIjv9H2TvwXhFMVjngcGrYoF9zsI |

### known_hosts 状态

- 使用 hashed 格式存储 (安全)
- heavy-1/2/3 的 host key 已缓存 (通过 IP 方式)
- light-2/3/4/5 的 host key 在本次诊断中首次添加 (通过 hostname 方式)

### 次要发现: locale 警告

所有节点在 SSH 连接时会报 `bash: warning: setlocale: LC_ALL: cannot change locale (en_US.UTF-8)`。
这是因为客户端发送了 `LC_ALL=en_US.UTF-8` 环境变量，但节点上未安装该 locale。

**影响**: 仅为警告，不影响功能。
**修复** (可选): 在各节点上运行 `locale-gen en_US.UTF-8 && dpkg-reconfigure locales`。

---

## 诊断总结

```
[OK]    aether CLI      v0.7.2
[OK]    配置验证         地址有效 (192.168.69.70:4646)
[OK]    集群连接         Nomad 1.11.2 / Consul 1.22.3
[FIXED] SSH 连接         8/8 节点正常, 已修复 SSH 配置缺陷
```

### 状态: OK (已修复)

SSH 连接在诊断时全部成功。之前 heavy-2 和 heavy-3 的连接失败，最可能的原因是:

1. **SSH 配置不匹配 IP 地址** (已修复) -- 如果通过 IP 而非 hostname 连接，SSH 配置规则不生效，导致 `StrictHostKeyChecking=ask` 在非交互模式下失败
2. **临时网络问题** -- 节点或网络的暂时不可达，当前已恢复
3. **host key 变更** -- 如果节点近期重装/重新生成了 SSH host key，且 known_hosts 中有旧记录，在 `StrictHostKeyChecking=ask` 模式下会拒绝连接

修复后的 SSH 配置确保无论通过 hostname 还是 IP 连接，都使用统一的安全配置，从根本上避免此类问题复发。

---

诊断完成 | aether-doctor v2.1.0
