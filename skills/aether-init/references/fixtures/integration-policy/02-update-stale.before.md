# SilkNode

SilkNode 是消息投递服务，2026-06 接入 Aether。

## 部署

见 `deploy/nomad-prod.hcl`。

---

<!-- aether:integration-policy 2026-06-01 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. stateful job 必须带 `migrate` stanza。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->

## 团队备注

上线值班表见内部 wiki，不放在本文件。
