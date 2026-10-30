# AI Runtime Bundle Build — Consumer Project CI Template

> Aether #543 M2-T1b deliverable: a copyable workflow template for consumer
> projects to build and push **exec-runtime bundles** (trimmed node + stripped
> deps, `aether ai pack`) into the internal Forgejo generic package registry,
> producing the `generic://` pinned source line the manifest expects. The
> docker-image sibling of this template is `ai-runtime-image-build.md`.

## When to use

Your project declares an **exec-path AI service** (light nodes, zero Docker)
in `.aether/ai-service.yaml` with
`source: generic://10CG/<name>@<version>+sha256:<hex>`. This template packs
your project on CI and pushes an immutable, sha256-pinned bundle the service
downloads via template-curl at alloc start.

## Template

Copy to `.forgejo/workflows/ai-bundle-build.yaml`, replace `<PROJECT>`:

```yaml
name: Build AI Runtime Bundle

on:
  push:
    branches: [main, master]
    paths: ['src/**', 'package.json', 'package-lock.json', '.aether/ai-service.yaml']
  workflow_dispatch:

env:
  NO_PROXY: 'localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8'   # runner proxies must not touch the intranet
  no_proxy: 'localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8'

jobs:
  pack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # aether CLI (≥1.23.17 has pack; ≥1.23.20 has the matured channel)
      - name: Install aether
        run: |
          curl -fsSL -H "Authorization: token ${{ secrets.FORGEJO_TOKEN }}" \
            "http://192.168.69.200:3000/api/v1/repos/10CG/Aether/releases/latest/assets/aether-linux-amd64" \
            -o /tmp/aether 2>/dev/null || true   # release asset API form; adjust if your runner lacks it
          chmod +x /tmp/aether && sudo mv /tmp/aether /usr/local/bin/aether
          aether version

      - name: node guard (pack assembles the runtime from the environment)
        run: node --version

      - name: pack + push (immutable, version = commit)
        env:
          FORGEJO_TOKEN: ${{ secrets.FORGEJO_TOKEN }}   # needs write:package
        run: |
          aether ai pack . --push --name <PROJECT>-bundle --owner 10CG \
            | tee /tmp/pack.out
          grep -q "generic://10CG/<PROJECT>-bundle@" /tmp/pack.out \
            || { echo "pack did not print the pinned generic:// source line"; exit 1; }
```

After the push, paste the printed `generic://10CG/<PROJECT>-bundle@<ver>+sha256:<hex>`
line into your manifest's `source:` field and commit it — the manifest change
is what deploys the new bundle (bundles themselves are immutable; a re-run on
the same commit will 409 on re-push, which is correct behavior).

## Hard-won notes (2026-10-28..30, Aether #562/#543 live runs)

1. **Owner is case-sensitive**: the cluster org is `10CG` — `10cg` gets
   404/500 on package routes. Never lowercase it.
2. **Intranet bypasses the proxy**: runner images carry proxy env; without
   `NO_PROXY` covering `192.168.0.0/16`, pushes fail (mirror-binary.sh's
   `--noproxy '*'` is the same lesson).
3. **Versions are immutable**: (name, version, file) can never be re-pushed.
   Version = git short sha (pack's default) is safe; timestamped manual
   versions are fine for smoke runs.
4. **Uploads must be binary-typed**: the CLI does this correctly
   (`application/octet-stream`). If you ever hand-curl uploads, an absent
   Content-Type makes Forgejo's multipart parser return **500** (the #562
   three-day misattribution — it looks like a server/credential problem but
   is the client's request shape).
5. **Deploy-side vars pre-exist** (fail-closed): the service task BLOCKS in
   template until `nomad/jobs/ai-<project>-<name>` exists — `package_read_token`
   (bundle download) and, for docker paths, `docker_auth_user`/`_password`.
   Pre-create before `aether ai up`; empty values work for public artifacts.
6. **Reference implementation**: Aether's own
   `.forgejo/workflows/ai-bundle-smoke.yml` + `tests/smoke/ai-bundle-smoke.sh`
   run this whole channel end-to-end against the real cluster — the judgment
   criteria there are the living spec.
