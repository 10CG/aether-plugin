# turfsync-worker

> 本文件由 `/aether:init` 生成，请勿手动删除下方 marker 区块（`aether-init` 重跑时会据此判定是否需要更新）。

<!-- aether:integration-policy 2026-07-15 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. 对已有数据的 volume 用 `aether volume create --register-only`（不用默认 create）。
4. stateful job 必须带 `migrate` stanza（`max_parallel=1` + `health_check=checks` + `min_healthy_time=30s` + `healthy_deadline=5m`）。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->
