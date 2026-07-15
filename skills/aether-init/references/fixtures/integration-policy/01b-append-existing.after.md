# TurfSync

TurfSync 是内部草坪养护调度工具。本文件由团队手写维护，早于 `aether-init` 接入。

## 本地开发

```bash
make dev
```

## 已知坑

- `~/.turfsync/devdb.env` 是手写的本地开发数据库连接配置，不受本仓 git 追踪。

---

<!-- aether:integration-policy 2026-07-15 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. 对已有数据的 volume 用 `aether volume create --register-only`（不用默认 create）。
4. stateful job 必须带 `migrate` stanza（`max_parallel=1` + `health_check=checks` + `min_healthy_time=30s` + `healthy_deadline=5m`）。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->
