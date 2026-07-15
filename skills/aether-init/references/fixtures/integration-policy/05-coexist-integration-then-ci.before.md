# otherapp

otherapp 接入顺序与 `04` 相反：本项目先补的集成规范 marker，CI-policy marker 后加。
用于验证"任意顺序共存"不依赖块出现顺序。

<!-- aether:integration-policy 2026-06-01 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. stateful job 必须带 `migrate` stanza。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->

---

<!-- aether-ci-policy -->
### CI/CD Monitoring Policy (MANDATORY)

After every `git push` that triggers CI/deploy, you MUST walk the full
**push → CI → image → deploy → health** chain before reporting back.

1. **CI verification** — `/aether:aether-ci [sha]` to wait for and
   confirm CI reaches `success`.
2. **Failure diagnosis** — If CI fails, `/aether:aether-ci [sha] --reproduce`
   to reproduce locally.
3. **Deployment monitoring** — After CI success,
   `/aether:aether-deploy-watch otherapp-dev` to confirm the Nomad
   allocation reaches `running` and health checks pass.
4. **Only after the deployment is confirmed healthy** may you report
   "deployed" back to the user.

DO NOT use hand-written `sleep N`, "should be ready by now"-style reports,
or trust `git push` exit code alone.
