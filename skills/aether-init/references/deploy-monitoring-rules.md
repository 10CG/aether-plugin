<!-- aether-ci-policy -->
### CI/CD Monitoring Policy (MANDATORY)

After every `git push` that triggers CI/deploy, you MUST walk the full
**push → CI → image → deploy → health** chain before reporting back.
A successful `git push` only means the git server accepted the bytes —
it says nothing about CI, image build, Nomad scheduling, or service health.

1. **CI verification** — `/aether:aether-ci [sha]` to wait for and
   confirm CI reaches `success`.
2. **Failure diagnosis** — If CI fails, `/aether:aether-ci [sha] --reproduce`
   to reproduce locally. For Aether-specific failure modes (TLS /
   EIDLETIMEOUT / `operation not supported` / `docker.1ms.run` missing tag /
   `invalid pkt-len`), consult
   `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`
   § Troubleshooting decision tree.
3. **Deployment monitoring** — After CI success,
   `/aether:aether-deploy-watch __JOB_NAME__` to confirm the Nomad
   allocation reaches `running` and health checks pass.
4. **Only after the deployment is confirmed healthy** may you report
   "deployed" back to the user.

DO NOT use hand-written `sleep N`, "should be ready by now"-style reports,
or trust `git push` exit code alone. These shortcuts have caused false
positives in past Aether-cluster CI/CD incidents.

> The plugin's PostToolUse hook (`ci-watch-hook.sh`) auto-writes
> `.aether/ci-watch.state` on `git push` and nudges Claude into polling
> mode. This section is the policy layer; the hook is the automation
> layer. They complement each other: the hook can fail (session mode,
> bypass, plugin not installed) — this policy ensures Claude still
> follows the correct flow regardless. Full rationale:
> `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`
> § CI Monitoring Policy.
