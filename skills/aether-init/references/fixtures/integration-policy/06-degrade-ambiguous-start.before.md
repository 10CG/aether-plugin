# GlassPipe

## 集成规范草稿（未完成）

有同事之前手动抄录过 marker 想着以后自己接手自动化，结果没抄完整，只留了一行孤立的
start marker（没有配对的 end marker）：

<!-- aether:integration-policy 2026-05-10 start -->

（下面这段本来要抄，还没抄完，先占位别删）

## 其他章节

一些正常的项目说明内容，与 marker 无关。

---

<!-- aether:integration-policy 2026-06-01 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. stateful job 必须带 `migrate` stanza。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->
