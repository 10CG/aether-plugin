# Aether 集群配置报告

**日期**: 2026-03-18
**执行方式**: Without Skill (直接使用 CLI)

---

## 1. 配置创建

使用 `aether setup` 命令创建全局配置：

```bash
aether setup --nomad-addr http://192.168.69.70:4646 \
             --consul-addr http://192.168.69.70:8500 \
             --registry forgejo.10cg.pub
```

**结果**: 配置已保存到 `~/.aether/config.yaml`

配置文件内容：

```yaml
cluster:
    consul_addr: http://192.168.69.70:8500
    nomad_addr: http://192.168.69.70:4646
    registry: forgejo.10cg.pub
    registry_url: forgejo.10cg.pub
```

---

## 2. 连接验证

使用 `aether setup --check` 验证所有连接：

| 组件 | 状态 | 详情 |
|------|------|------|
| Nomad | healthy | Leader: 192.168.69.71:4647 |
| Consul | healthy | Leader: 192.168.69.70:8300 |
| Registry | reachable | Type: Forgejo Container Registry, Auth: FORGEJO_TOKEN |

**所有连接检查通过。**

---

## 3. 集群状态概览

### 3.1 Jobs

- **Total**: 17 | **Running**: 17 | **Pending**: 0 | **Failed**: 0

### 3.2 节点状态

所有 8 个节点均为 ready 状态：

| 节点 | 类型 | 状态 | IP |
|------|------|------|----|
| heavy-1 | heavy_workload | ready | 192.168.69.80 |
| heavy-2 | heavy_workload | ready | 192.168.69.81 |
| heavy-3 | heavy_workload | ready | 192.168.69.82 |
| light-1 | light_exec | ready | 192.168.69.90 |
| light-2 | light_exec | ready | 192.168.69.91 |
| light-3 | light_exec | ready | 192.168.69.92 |
| light-4 | light_exec | ready | 192.168.69.93 |
| light-5 | light_exec | ready | 192.168.69.94 |

### 3.3 服务健康检查

- **Total**: 24 | **Passing**: 22 | **Warning**: 0 | **Critical**: 1

**Critical 服务**:
- `psych-ai-dev-api` (节点: heavy-1) - 健康检查失败

所有其他服务运行正常。

---

## 4. Registry 认证链

```
Registry URL: forgejo.10cg.pub
Type: Forgejo Container Registry
认证 Fallback 链: FORGEJO_TOKEN -> GITEA_TOKEN -> AETHER_REGISTRY_PASSWORD -> REGISTRY_PASSWORD -> REGISTRY_TOKEN
当前使用: FORGEJO_TOKEN
```

---

## 5. 注意事项

1. **psych-ai-dev-api 健康检查异常**: 该服务在 heavy-1 节点上的健康检查为 critical 状态。如果这是你关心的服务，建议进一步排查（查看日志、检查端口是否正常监听等）。
2. **配置文件权限警告**: 检测到 `aether-plugin/.aether/config.yaml` 权限为 644，建议使用 `chmod 0600` 修复。
3. **集群整体健康**: 所有节点 ready，17/17 jobs 运行中，集群整体状态良好。

---

## 6. 总结

集群配置已成功创建并验证。Nomad、Consul 和 Registry 三个核心组件的连接均正常。集群当前运行 17 个 jobs，8 个节点全部在线。除 `psych-ai-dev-api` 一个服务健康检查异常外，其余全部正常。
