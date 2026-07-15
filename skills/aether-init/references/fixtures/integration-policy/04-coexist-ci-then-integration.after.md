# myapp

myapp 是示例服务，2026-04 由 `aether-init` v1.7.2 接入（早于 C1 集成规范 marker 存在）。

<!-- aether-ci-policy -->
### CI/CD Monitoring Policy (MANDATORY)

After every `git push` that triggers CI/deploy, you MUST walk the full
**push → CI → image → deploy → health** chain before reporting back.
A successful `git push` only means the git server accepted the bytes —
it says nothing about CI, image build, Nomad scheduling, or service health.

1. **CI verification** — `/aether:aether-ci [sha]` to wait for and
   confirm CI reaches `success`.
2. **Failure diagnosis** — If CI fails, `/aether:aether-ci [sha] --reproduce`
   to reproduce locally.
3. **Deployment monitoring** — After CI success,
   `/aether:aether-deploy-watch myapp-dev` to confirm the Nomad
   allocation reaches `running` and health checks pass.
4. **Only after the deployment is confirmed healthy** may you report
   "deployed" back to the user.

DO NOT use hand-written `sleep N`, "should be ready by now"-style reports,
or trust `git push` exit code alone.

---

<!-- aether:integration-policy 2026-07-15 start -->
### 集群集成规范 (MANDATORY)

1. 内网/DB 连接串一律用 `<service>.service.consul`，禁止硬编码 IP。
2. stateful 服务的 host_volume 必须在**全部** heavy 节点注册（不可单节点）。
3. 对已有数据的 volume 用 `aether volume create --register-only`（不用默认 create）。
4. stateful job 必须带 `migrate` stanza（`max_parallel=1` + `health_check=checks` + `min_healthy_time=30s` + `healthy_deadline=5m`）。

**详情** invoke `aether-conventions` skill。

<!-- aether:integration-policy end -->
