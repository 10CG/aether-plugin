# AmberCask

AmberCask 是 2026-04（v1.7.2 时代）接入的老项目，当时 `aether-init` 只会注入
CI/CD Monitoring Policy，成对栅栏日期戳 marker（`aether:integration-policy`，
Aether #245 C1）还不存在。本文件只含旧版单起始 `<!-- aether-ci-policy -->` marker，
完全不含新 marker。

<!-- aether-ci-policy -->
### CI/CD Monitoring Policy (MANDATORY)

After every `git push` that triggers CI/deploy, you MUST walk the full
**push → CI → image → deploy → health** chain before reporting back.

1. **CI verification** — `/aether:aether-ci [sha]` to wait for and
   confirm CI reaches `success`.
2. **Failure diagnosis** — If CI fails, `/aether:aether-ci [sha] --reproduce`
   to reproduce locally.
3. **Deployment monitoring** — After CI success,
   `/aether:aether-deploy-watch ambercask-dev` to confirm the Nomad
   allocation reaches `running` and health checks pass.
4. **Only after the deployment is confirmed healthy** may you report
   "deployed" back to the user.

DO NOT use hand-written `sleep N`, "should be ready by now"-style reports,
or trust `git push` exit code alone.
