# Changelog

All notable changes to aether-plugin will be documented in this file.

## [1.7.0] - 2026-04-10

### Added
- **New plugin-level `references/` directory** — authoritative cross-skill
  reference resources, accessible via `${CLAUDE_PLUGIN_ROOT}/references/`.
- **`references/forgejo-ci-optimization.md`** — comprehensive Forgejo CI
  optimization and troubleshooting guide for the Aether environment. Covers
  10 anti-patterns (with real error messages), 10 best practices, 4 real
  project case studies (SilkNode 25m→10m41s, Nexus 9m30s→6m43s, Kairos
  13m→4m39s cold, Kino api 6m→2m14s + web 4m46s→1m51s), and an
  error-keyword-driven troubleshooting decision tree.
- Symlink `docs/guides/forgejo-ci-optimization.md` in the main Aether repo
  pointing to the plugin-level guide (single source of truth).

### Changed
- **aether-init / workflow-templates.md**: substantial rewrite (242→477
  lines). All Docker templates now include: explicit `driver: docker` in
  buildx, DNS fix for internal registry, build+push split pattern, polling
  deployment verification. Documents why each pattern is necessary.
- **aether-init / dockerfile-templates.md**: substantial rewrite (91→250
  lines). Node templates: npm mirror (`registry.npmmirror.com`) + 3x retry
  loop + `# syntax=docker/dockerfile:1`. Python templates: pip mirror
  (`mirrors.aliyun.com`) + retry. All templates use `COPY --chown` instead
  of `RUN chown -R`. Added multi-stage + proper layer caching for every
  language. Node default version aligned to 22.
- **aether-init/SKILL.md**: added cross-skill reference row in the 详细参考
  table pointing to `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`.
- **aether-ci/SKILL.md**: added 1-line blockquote in 故障处理 section
  pointing to the optimization guide for Aether-specific error modes
  (TLS / EIDLETIMEOUT / operation not supported / docker.1ms.run tag missing
  / invalid pkt-len). Pure additive change — [skip-benchmark qualified].

### Quality verification
- AB benchmark for aether-init: **WITH skill wins decisively** (3/3 critical,
  5/5 aether-specific vs WITHOUT 1/3 critical, 1/5 aether-specific). No
  regression. Results in `ab-results/2026-04-10/aether-init/`.
- Static benchmark: aether-init 344→350 lines (OK), aether-ci 397→399 lines
  (OK, 1 line under warning threshold).

## [1.6.6] - 2026-04-09

### Changed
- **aether-deploy-watch**: SKILL.md optimized from 486→393 lines. Extracted
  4 procedural sections to `references/` directory (CI diagnosis, phantom alloc,
  polling patterns, CronCreate integration). No content changes. [skip-benchmark]
- **requirements.yaml**: `cli.recommended_version` updated to 1.7.0.

## [1.6.5] - 2026-04-09

### Changed
- **requirements.yaml**: Update `cli.recommended_version` from 1.6.0 to 1.6.1.

## [1.6.4] - 2026-04-08

### Changed
- **aether-ci Skill v2.1.0**: Three-tier strategy chain (API → SSH → local repro),
  run list table display, 15 failure patterns (was 9) with 7 categories,
  SSH degradation handling, `--search` log capability.
  AB tested: WITH_BETTER (3/3 evals, 60/60 vs 51/60).

## [1.6.3] - 2026-04-08

### Changed
- **aether-ci Skill v2.0.0**: Step 2 uses `aether ci status --json` (CLI v1.5.0+),
  new Step 2a remote log reading via `aether ci logs`, expanded error patterns
  (docker build, dependency install, timeout split). AB tested: WITH_BETTER (20/20 vs 17/20).
- Compacted CronCreate section (359→315 lines, under 400 guard).

## [1.6.2] - 2026-04-03

### Added
- **benchmark-aggregate-hook**: PostToolUse hook that detects AB test result commits
  and reminds to run `aggregate-results.py` to update OVERALL_BENCHMARK_SUMMARY.md.
  Prevents summary staleness after AB testing sessions.

## [1.6.1] - 2026-04-01

### Changed
- **aether-status**: Complete SKILL.md redesign (v2.0.0). Investigation-first approach
  replaces checklist-driven format. 314→118 lines. Adds mandatory Consul depth checks,
  severity grading, investigation signal mapping. AB test: WITH win rate 0%→100%.

## [1.6.0] - 2026-04-01

### Added
- **aether-deploy-watch**: Phantom alloc detection in Step 3 timeout path.
  When health checks time out, fetches TaskStates for each "running" alloc
  to detect containers dead at Docker level but reported running by Nomad (Issue #12).
- **deploy-doctor**: Phantom alloc detection in allocation analysis step.
  Verifies TaskStates depth for running allocations, identifies Docker event
  stream disconnection as root cause, suggests alloc stop or node drain.

## [1.5.1] - 2026-03-31

### Fixed
- **aether-deploy-watch**: Add CI status diagnostic when image not found or deploy
  times out (Aether#9). Distinguishes cancelled CI (superseded by newer push) from
  real failures via Forgejo Actions Tasks API. Prevents false "Runner resource leak"
  diagnosis and destructive `docker network prune` suggestions.

### Added
- **AB eval**: New eval-6 `rapid-push-cancelled-ci-misdiagnosis` for deploy-watch

## [1.5.0] - 2026-03-31

### Added
- **aether-report**: New skill for reporting bugs and feature requests to Aether
  maintainers. Auto-routes to Forgejo (internal users) or GitHub (external users).
  Collects environment context, enforces privacy review before submission.

## [1.4.0] - 2026-03-31

### Changed
- **aether-deploy-watch**: Complete v2.0.0 rewrite — 4-step pipeline orchestrator
  with direct Nomad/Consul API calls for control flow
  - Step 0: Context resolution (job name, SHA, registry)
  - Step 1: Image verification via forgejo wrapper
  - Step 2: Deploy convergence via Nomad deployments API
  - Step 3: Health verification via Consul health API (2 consecutive checks)
  - Two modes: post-push pipeline (--version) and spot-check
- **ci-watch-hook**: Added job_name + expected_image to state file; CI success
  now triggers deploy-watch automatically
- **aether-ci**: CronCreate prompt updated to invoke deploy-watch on CI success
- **cli.recommended_version**: 0.9.0 → 1.0.0

### Fixed
- **IP addresses**: Fixed 60+ hardcoded 192.168.1.x → 192.168.69.x across 16 files
  (agents, skills, references). PVE address 192.168.1.11 preserved.

## [1.3.2] - 2026-03-28

### Fixed
- **aether-init**: Inject CLAUDE.md rules for existing projects (not just new ones)

## [1.3.1] - 2026-03-27

### Added
- **aether-init**: Phase 2 自动注入部署监控规则到项目 CLAUDE.md (Closes aether-plugin#1)
- **aether-init/references**: deploy-monitoring-rules.md 模板 (含占位符替换规则)

## [1.3.0] - 2026-03-26

### Changed
- **cli.min_version**: 0.7.0 → 0.9.0 (CLI deploy execution now functional)
- **cli.recommended_version**: 0.8.0 → 0.9.0

### Note
- v1.2.2 contained new features (Consul DNS guidance) that should have been a MINOR bump. Per VERSIONING.md, already-published version numbers are not modified. v1.3.0 corrects the version sequence.

## [1.2.2] - 2026-03-25

### Added
- **aether-init**: Consul DNS service discovery guidance — detect DATABASE/REDIS/MONGO deps, recommend `{svc}.service.consul` FQDN
- **aether-init/references**: HCL env block examples with `.service.consul` connection strings
- **aether-doctor**: DNS resolution diagnostic step (`dig consul.service.consul`)
- **aether-setup**: DNS status line in `--show` output

### Fixed
- **aether-dev**: Complete v1.1.0 config migration — replaced `.env` + `endpoints.*` with `.aether/config.yaml` + `cluster.*` two-tier pattern (lines 349-368)

### Quality
- All 4 modified Skills pass static-benchmark (init: 315 lines, dev: 383, setup: 293, doctor: 147)
- OpenSpec: consul-dns-service-discovery (US-013)

## [1.2.1] - 2026-03-25

### Fixed
- **cli-guard-hook.sh**: Platform-aware CLI download — auto-detect OS/arch via `uname`, no longer depends on `jq`. Fixes macOS users downloading wrong-platform (linux) binary.
- **detect-cli.sh**: Same platform-aware fix for `print_install_guidance()`.
- **cli-installation.md**: GitHub mirror as primary download (no CF auth needed), Forgejo as fallback. Manual install now covers both arm64 and amd64 for macOS.

### Improved
- **aether-volume SKILL.md**: Added safety guarantees table, common failure patterns with SSH diagnostics
- **aether-setup SKILL.md**: Enhanced config priority chain visualization, Consul auto-derivation, diagnostic framework

### Quality
- AB test: 10 Skills × 20 evals, WITH **100%** win rate (20/20), up from 90%
- volume e1: TIE → WITH_BETTER, setup e1: TIE → WITH_BETTER

## [1.2.0] - 2026-03-24

### Added
- **aether-ci**: CI status query, failure diagnosis, auto-monitoring (PostToolUse Hook + CronCreate polling)
- **ci-watch-hook.sh**: PostToolUse Hook auto-detects `git push` and triggers CI monitoring
- **hooks.json**: Migrated to standard Claude Code command format (PreToolUse + PostToolUse)

### Improved
- **aether-setup**: Added config priority chain explanation and richer cluster detail (Docker versions, host volumes per node)
- **aether-volume**: Added idempotency check before create and post-create SSH directory verification

### Quality
- AB test: 10 Skills × 20 evals, WITH 90% win rate (18/20), zero regressions
- WITH_BETTER: 8/10, MIXED: 2/10 (setup, volume — simple task ceiling), WITHOUT: 0/10
- Hook E2E validation: 69/69 checks passed

## [1.1.0] - 2026-03-19

### Added (2026-03-24)
- **aether-ci**: CI status query, failure diagnosis, and auto-monitoring skill
  - Forgejo commit status API integration for CI state checking
  - Local reproduction of failed CI jobs (go test / golangci-lint)
  - Error pattern matching and fix suggestions
  - Watch mode with CronCreate-based polling
- **PostToolUse Hook** (`ci-watch-hook.sh`): Auto-detect `git push` and trigger CI monitoring
- **hooks.json migrated** to standard Claude Code command format (both PreToolUse + PostToolUse)

### Improved (AB test validated)
- **aether-status**: Removed prescriptive curl/jq templates, added exploration dimension guidance. WITHOUT_BETTER → WITH_BETTER (2-0)
- **aether-deploy**: Added registry API fallback when docker CLI unavailable, failure diagnosis guidance. MIXED → WITH_BETTER (2-0)
- **aether-rollback**: Expanded to 3 rollback strategies (Nomad revert / Git resubmit / emergency deploy), added execution confirmation step, structured root cause analysis. MIXED → WITH_BETTER (2-0)
- **aether-doctor**: Enhanced SSH diagnostics with 5-layer diagnostic framework (network → name resolution → auth → remote-side → application). MIXED → WITH_BETTER (2-0)
- **aether-setup**: Streamlined from 410 to 213 lines, removed boilerplate bash functions, added connection failure diagnostic guide. MIXED → MIXED (stable)

### Fixed
- **Config schema**: All 5 skills corrected endpoints.* → cluster.* in config read sections

### Quality
- AB test: 9 Skills × 18 evals, WITH 94.4% win rate (up from 50%)
- WITH_BETTER: 8/9 skills, MIXED: 1/9 (setup), WITHOUT_BETTER: 0/9
- Zero regressions across two optimization rounds

## [1.0.0] - 2026-03-18

### Milestone
- First stable release with full AB test baseline validation

### Added
- **skill-benchmark**: AB comparison testing skill for quality verification
- **Error handling improvements**: 5 skills upgraded (status, init, setup, dev, cli-guard)
- **Deep investigation guidance**: aether-status now encourages exploration beyond basic queries

### Fixed
- **aether-setup**: Config schema corrected (endpoints.* → cluster.*)
- **aether-setup**: Project config path corrected (.env → .aether/config.yaml)
- **aether-volume CLI**: Idempotency check for existing volumes

### Quality
- AB test baseline: 9 Skills × 18 evals, WITH 50% win rate
- 3 real bugs discovered and fixed through AB testing
- Benchmark infrastructure moved to aether-plugin-benchmarks/

## [0.9.1] - 2026-03-13

### Fixed
- **Dual Authentication Support**: Forgejo API requires both CF Token AND Forgejo Token
  - Added `FORGEJO_TOKEN` to authentication headers
  - Updated `fetch_release_with_cf_auth()` to include Forgejo API token

### Test Results
| Auth Method | HTTP Code | Notes |
|-------------|-----------|-------|
| None | 302 | CF redirect |
| Forgejo Token only | 302 | CF blocked |
| CF Token only | 403 | Forgejo rejected |
| **CF + Forgejo Token** | **200** | **Success!** |

### Configuration Required
```bash
# CF Access Service Token (aria spec)
export CF_ACCESS_CLIENT_ID="your-client-id"
export CF_ACCESS_CLIENT_SECRET="your-client-secret"

# Forgejo API Token
export FORGEJO_TOKEN="your-forgejo-token"
```

## [0.9.0] - 2026-03-13

### Added
- **Cloudflare Access Token Detection**: Smart token detection before Forgejo API requests
  - Check environment variables: `CF_ACCESS_TOKEN`, `CLOUDFLARE_ACCESS_TOKEN`, `CF_AUTHORIZATION`
  - Check config files: `~/.cloudflare/access-token`, `~/.cfaccess`, `~/.config/cloudflare/access-token`
  - Auto-detect when CF authentication is required (302/401 response)

### Changed
- **CLI Installation Workflow**: Prioritize existing CF token configuration
  - `scripts/detect-cli.sh`: Added `detect_cf_access_token()`, `fetch_release_with_cf_auth()`, `check_cf_access_required()` functions
  - `skills/aether-doctor/references/cli-installation.md`: Updated installation flow with CF token detection
  - `.claude-plugin/requirements.yaml`: Added complete `cf_access` configuration section

### Workflow
**Before (Fallback immediately):**
```
Forgejo API → 302 → 放弃，尝试源码构建
```

**After (Check CF token first):**
```
Forgejo API → 302 → 检查本地 CF Token
                          ├─ 有 Token → 使用认证请求下载
                          └─ 无 Token → 显示配置引导
```

### Configuration
```yaml
# .claude-plugin/requirements.yaml
cli:
  cf_access:
    env_vars:
      - "CF_ACCESS_TOKEN"
      - "CLOUDFLARE_ACCESS_TOKEN"
      - "CF_AUTHORIZATION"
    config_files:
      - "~/.cloudflare/access-token"
      - "~/.cfaccess"
      - "~/.config/cloudflare/access-token"
    cookie_name: "CF_Authorization"
    instructions: |
      1. 在浏览器中访问 https://forgejo.10cg.pub 并完成 CF 认证
      2. 打开开发者工具 → Application → Cookies
      3. 复制 CF_Authorization cookie 值
      4. 设置环境变量: export CF_ACCESS_TOKEN="your-token"
```

### How to Get CF Token
```bash
# Method 1: Environment variable (recommended)
export CF_ACCESS_TOKEN="your-token-here"

# Method 2: Config file
echo "your-token-here" > ~/.cfaccess
chmod 600 ~/.cfaccess

# Steps to obtain token:
# 1. Visit https://forgejo.10cg.pub in browser and complete CF authentication
# 2. Open DevTools (F12) → Application → Cookies
# 3. Copy the CF_Authorization cookie value
```

## [0.9.0] - 2026-03-13

### Added
- **Cloudflare Access Token Detection**: Smart token detection before Forgejo API requests
  - Check environment variables: `CF_ACCESS_TOKEN`, `CLOUDFLARE_ACCESS_TOKEN`, `CF_AUTHORIZATION`
  - Check config files: `~/.cloudflare/access-token`, `~/.cfaccess`, `~/.config/cloudflare/access-token`
  - Auto-detect when CF authentication is required (302/401 response)

### Changed
- **CLI Installation Workflow**: Prioritize existing CF token configuration
  - `scripts/detect-cli.sh`: Added `detect_cf_access_token()`, `fetch_release_with_cf_auth()`, `check_cf_access_required()` functions
  - `skills/aether-doctor/references/cli-installation.md`: Updated installation flow with CF token detection
  - `.claude-plugin/requirements.yaml`: Added complete `cf_access` configuration section

### Workflow
**Before (Fallback immediately):**
```
Forgejo API → 302 → 放弃，尝试源码构建
```

**After (Check CF token first):**
```
Forgejo API → 302 → 检查本地 CF Token
                          ├─ 有 Token → 使用认证请求下载
                          └─ 无 Token → 显示配置引导
```

### Configuration
```yaml
# .claude-plugin/requirements.yaml
cli:
  cf_access:
    env_vars:
      - "CF_ACCESS_TOKEN"
      - "CLOUDFLARE_ACCESS_TOKEN"
      - "CF_AUTHORIZATION"
    config_files:
      - "~/.cloudflare/access-token"
      - "~/.cfaccess"
      - "~/.config/cloudflare/access-token"
    cookie_name: "CF_Authorization"
```

## [0.8.9] - 2026-03-12

### Added
- **PreToolUse Hook for CLI Auto-Detection** (P2 Optimization):
  - `skills/aether-cli-guard/SKILL.md` - Hook skill documentation
  - `scripts/cli-guard-hook.sh` - Executable hook script
  - Automatic CLI detection before executing aether commands
  - User-friendly install guidance when CLI is missing

- **Hook Configuration** (`hooks.json`):
  - PreToolUse hook with Bash tool filter
  - Command pattern matching for `aether`
  - Graceful fallback with install instructions

### Changed
- **Automated CLI Detection Flow**:
  ```
  User runs: aether volume list
       ↓
  Hook triggers: CLI detection
       ↓
  ├─ CLI found → Command executes
  └─ CLI missing → Block + Show install guide
  ```

### User Experience
**Before (Manual):**
```
User: 运行 aether volume list
Claude: ❌ CLI 未安装...
```

**After (Automatic):**
```
User: 运行 aether volume list
Hook: 🔍 检测 aether CLI...
      ❌ 未找到 → 显示安装引导
      ✅ 已找到 → 命令继续执行
```

### Hook Skill
| 属性 | 值 |
|------|-----|
| Name | aether-cli-guard |
| Type | Hook Skill (内部) |
| Trigger | PreToolUse + Bash + "aether" |
| User-invocable | false |

## [0.8.8] - 2026-03-12

### Added
- **Shared CLI Detection Scripts** (`scripts/`):
  - `detect-cli.sh` - Full CLI detection with version checking and install guidance
  - `cli-functions.sh` - Lightweight functions for sourcing in skills

### Changed
- **Unified CLI Pre-check**: All CLI-dependent skills now use shared detection:
  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
  require_aether_cli || exit 1
  ```

- **Skills updated**:
  - `aether-deploy` v0.3.0 - Uses shared script, gets CLI path
  - `aether-dev` v0.3.0 - Uses shared script
  - `aether-rollback` v0.3.0 - Uses shared script
  - `aether-init` v0.5.0 - Uses shared script
  - `aether-volume` v1.3.0 - Uses shared script

### Benefits
- **DRY**: Single source of truth for CLI detection logic
- **Consistency**: Same error messages across all skills
- **Maintainability**: Update detection in one place
- **Extensibility**: Easy to add new detection paths

## [0.8.7] - 2026-03-12

### Changed
- **Unified CLI Dependency Declaration**: Standardized `dependencies.cli` frontmatter across all skills
  - Consistent format: `required`, `min_version`, `note`
  - Clear guidance when CLI is missing: "请运行 /aether:doctor 安装 CLI"

- **Skills updated with CLI pre-check section**:
  - `aether-deploy` v0.2.0 - Added CLI detection and guidance
  - `aether-dev` v0.2.0 - Added CLI detection and guidance
  - `aether-rollback` v0.2.0 - Added CLI detection and guidance
  - `aether-init` v0.4.0 - Updated dependencies format
  - `aether-volume` v1.2.0 - Updated dependencies format
  - `aether-status` v1.1.0 - Marked CLI as optional (API-only mode)
  - `aether-deploy-watch` v1.2.0 - Marked CLI as not required
  - `aether-doctor` v2.1.0 - Marked as CLI installer/provider

- **requirements.yaml**: Updated with complete skill dependency matrix

### CLI Dependency Matrix

| Skill | CLI Required | Min Version | Notes |
|-------|-------------|-------------|-------|
| aether-doctor | No | - | CLI installer |
| aether-init | Yes | 0.7.0 | Project setup |
| aether-volume | Yes | 0.7.0 | Volume management |
| aether-deploy | Yes | 0.7.0 | Production deploy |
| aether-dev | Yes | 0.7.0 | Dev deployment |
| aether-rollback | Yes | 0.7.0 | Rollback |
| aether-status | No | - | API-only mode |
| aether-deploy-watch | No | - | Uses aether-status |
| aether-setup | No | - | Config only |

## [0.8.6] - 2026-03-12

### Changed
- **Skills Optimization**: Refactored skills using Progressive Disclosure pattern
  - `aether-doctor` SKILL.md: 1370 → 146 lines (89% reduction)
  - `aether-init` SKILL.md: 529 → 156 lines (70% reduction)
  - `aether-volume` SKILL.md: 461 → 149 lines (68% reduction)

### Added
- **aether-volume references/** (5 files):
  - `command-details.md` - Full command parameters and examples
  - `ssh-authentication.md` - SSH authentication methods
  - `nomad-configuration.md` - Generated configuration and Job usage
  - `troubleshooting.md` - Common issues and solutions
  - `best-practices.md` - Best practices and project type recommendations

- **aether-doctor references/** (6 files):
  - `cli-installation.md` - CLI installation workflows
  - `cluster-validation.md` - Cluster topology and validation
  - `ssh-diagnostics.md` - SSH checks and fixes
  - `ci-configuration.md` - CI/CD configuration checks
  - `environment-cache.md` - Cache format and validity
  - `output-examples.md` - Diagnostic output examples

- **aether-init references/** (2 new files):
  - `project-analysis.md` - Project detection and decision logic
  - `file-generation.md` - File generation commands

### Design Principle

Following skill-creator best practices:
- **SKILL.md** - Core workflow only (< 350 lines recommended)
- **references/** - Detailed content loaded on demand
- **scripts/** - Executable code
- **assets/** - Templates and resources

## [0.8.5] - 2026-03-12

### Changed
- **CLI Installation Directory**: Changed from `/usr/local/bin/` to `~/.aether/`
  - No longer requires `sudo` privileges
  - CLI installed alongside `config.yaml` for unified management
  - Skills auto-detect CLI location (PATH → ~/.aether/)

- `aether-doctor` skill (v1.4.0 → v1.5.0):
  - Added multi-path CLI detection logic
  - Updated all installation scripts to use `~/.aether/`
  - Enhanced error messages with correct paths

### CLI Detection Priority

```bash
# 1. Check PATH
if command -v aether &> /dev/null; then
  AETHER_CLI="aether"
# 2. Check ~/.aether/
elif [ -f "$HOME/.aether/aether" ]; then
  AETHER_CLI="$HOME/.aether/aether"
fi
```

### Installation Paths

| Platform | Old Path | New Path |
|----------|----------|----------|
| Linux/macOS | `/usr/local/bin/aether` | `~/.aether/aether` |
| Windows | `%USERPROFILE%\aether.exe` | `%USERPROFILE%\.aether\aether.exe` |

### Directory Structure

```
~/.aether/
├── config.yaml        # Aether 配置文件
├── environment.yaml   # 环境状态缓存
└── aether[.exe]       # CLI 二进制文件
```

## [0.8.4] - 2026-03-12

### Added
- **Complete CLI Installation Workflow**: Enhanced `aether-doctor` (v1.4.0) with full installation support
  - Automatic installation from Forgejo releases (方案 A)
  - Source build fallback (方案 B)
  - Platform-specific manual installation commands (方案 C)
  - Specify version installation option

- **requirements.yaml**: Complete CLI dependency configuration
  - Release API URLs (latest and versioned)
  - Tag format: `aether-cli/v{VERSION}`
  - Binary naming: `aether-{OS}-{ARCH}[.exe]`
  - Supported platforms matrix (Linux/macOS/Windows, amd64/arm64)

### Changed
- `aether-doctor` skill (v1.3.0 → v1.4.0):
  - Fixed download URLs to use correct Aether releases API
  - Updated binary naming format documentation
  - Added Windows `.exe` suffix handling
  - Enhanced interactive installation with version selection

- Removed invalid `cli` field from `plugin.json` (caused installation error)
- Moved CLI requirements to `requirements.yaml` and skill frontmatters

### Fixed
- **CLI Release Workflow**: Fixed ldflags variable name (`main.version` → `main.Version`)
  - Binary version now correctly embedded at build time
  - Affects `.forgejo/workflows/cli-release.yml`

### Configuration

```yaml
# .claude-plugin/requirements.yaml
cli:
  min_version: "0.7.0"
  recommended_version: "0.7.0"
  release_api: "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases"
  tag_format: "aether-cli/v{VERSION}"
  binary_format: "aether-{OS}-{ARCH}"
  platforms:
    - { os: linux, arch: amd64, binary: "aether-linux-amd64" }
    - { os: linux, arch: arm64, binary: "aether-linux-arm64" }
    - { os: darwin, arch: amd64, binary: "aether-darwin-amd64" }
    - { os: darwin, arch: arm64, binary: "aether-darwin-arm64" }
    - { os: windows, arch: amd64, binary: "aether-windows-amd64.exe" }
```

### Release Source

| Item | Value |
|------|-------|
| Release API | `https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases` |
| Latest | `.../releases/latest` |
| Versioned | `.../releases/tags/aether-cli/v{VERSION}` |

## [0.8.3] - 2026-03-09

### Added
- **CLI Version Compatibility**: Plugin now defines minimum CLI version requirement
  - `plugin.json` includes `cli.minVersion` and `cli.recommendedVersion` fields
  - `aether-doctor` (v1.3.0) checks CLI version compatibility

### Changed
- `aether-doctor` skill: Enhanced CLI installation support
  - Added version compatibility check (Plugin v0.8.x requires CLI >= 0.7.0)
  - Added automatic installation flow (方案A)
  - Added manual installation commands (方案C)
  - Interactive installation prompts when CLI not found or incompatible

### Configuration
```json
// plugin.json
{
  "cli": {
    "minVersion": "0.7.0",
    "recommendedVersion": "0.7.0",
    "downloadUrl": "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest"
  }
}
```

## [0.8.1] - 2026-03-08

### Changed
- **Refactored Skill Architecture**: Clear separation between base layer and composition layer
  - `aether-status` (v1.0.0): Enhanced as **base layer** skill
    - Added `--failed` flag: View failed allocations with details
    - Added `--recent` flag: View recent deployments
    - Added `--logs` flag: View allocation logs
    - Added `--watch` flag: Continuous monitoring mode
  - `aether-deploy-watch` (v1.1.0): Refactored as **composition layer** skill
    - Now calls `aether-status` for status queries
    - Focused on monitoring loop, error pattern matching, and fix suggestions
    - Clear documentation of skill relationships

### Architecture
```
aether-status (base layer)├── provides core status queries
├── --failed, --recent, --logs, --watch
│
aether-deploy-watch (composition layer)
├── calls aether-status for status
├── monitoring loop
├── error diagnosis
└── fix suggestions
```

## [0.8.0] - 2026-03-08

### Added
- **NEW Skill**: `aether-deploy-watch` - Post-deploy verification and diagnostics
  - Automatically check Nomad allocation status after CI/CD deployment
  - Collect failed allocation logs and error messages
  - Pattern matching for common deployment failures (image pull, network, auth, etc.)
  - Provide specific fix suggestions based on error patterns
  - Support `--follow` mode for continuous monitoring
  - Support `--timeout` parameter for custom timeout

### Changed
- `aether-doctor` skill: Added CI/CD configuration check (Step 8)
  - Detect CI platform (Forgejo/GitHub/GitLab)
  - Check workflow files for correct secrets usage
  - Identify hardcoded values vs secrets references
  - Provide fix suggestions for incorrect configurations
- `aether-init` workflow templates: Updated to use correct Forgejo secrets
  - Use `secrets.FORGEJO_TOKEN` instead of `secrets.REGISTRY_TOKEN`
  - Use `secrets.FORGEJO_USER` instead of `secrets.REGISTRY_USERNAME`

### Fixed
- CI shows success but Nomad deployment fails - now caught by `aether-deploy-watch`

## [0.7.2] - 2026-03-08

### Added
- `aether-doctor` skill: CI/CD configuration check (Step 8)
  - Detect CI platform (Forgejo/GitHub/GitLab)
  - Check workflow files for correct secrets usage
  - Identify hardcoded values vs secrets references
  - Provide fix suggestions for incorrect configurations
  - Support `--ci` flag for CI-only check

### Changed
- `aether-init` workflow templates: Updated to use correct Forgejo secrets
  - Use `secrets.FORGEJO_TOKEN` instead of `secrets.REGISTRY_TOKEN`
  - Use `secrets.FORGEJO_USER` instead of `secrets.REGISTRY_USERNAME`
  - Nomad address from `secrets.NOMAD_ADDR` instead of hardcoded
  - Added documentation for Forgejo auto-injected secrets

## [0.7.1] - 2026-03-08

### Changed
- `aether-doctor` skill: Major update v1.1.0
  - **Fixed**: Configuration validation logic - no longer uses leader address for comparison
  - **Added**: Complete cluster topology caching (all servers and clients)
  - **Added**: Project-level environment cache (`./.aether/environment.yaml`)
  - **Improved**: Configuration validation checks if address belongs to server list
  - **Improved**: Caches all server nodes with roles (leader/follower)
  - **Improved**: Caches all client nodes with classes and drivers
  - **Improved**: SSH connection tests for all nodes (servers + clients)

### Fixed
- Configuration conflict between multiple projects using same global cache
- Incorrect validation due to RPC port (4647) vs HTTP port (4646) mismatch

## [0.7.0] - 2026-03-07

### Added
- `aether-doctor` skill: Environment diagnostics tool
  - Check aether CLI installation and version
  - Validate configuration file existence and format
  - Test Nomad/Consul cluster connectivity
  - Check SSH key configuration and permissions
  - Test SSH connection to all cluster nodes
  - Collect cluster overview (node types, counts, IPs)
  - Update configuration cache with environment status
  - Provide repair suggestions for common issues

### Changed
- Enhanced environment state caching in config.yaml
- Skills can now read cached environment status before execution
- Better error messages with diagnostic suggestions

## [0.6.0] - 2026-03-07

### Added
- `aether-volume` skill: Host volume management guide
  - Volume creation, listing, and deletion workflows
  - SSH connection and remote execution guidance
  - Dry-run preview and rollback mechanisms

### Changed
- `aether-init` skill: Added Step 2.3 Registry authentication configuration
- Updated to support aether-cli v0.6.0 volume management features
- Enhanced registry integration with platform-specific credentials

## [0.5.0] - 2026-03-06

### Changed
- Updated to support aether-cli v0.5.0 registry auth detection
- Skills now leverage CLI's intelligent credential mapping
- Forgejo users can use `FORGEJO_TOKEN`/`FORGEJO_USER` directly

## [0.2.0] - 2026-02-19

### Added
- `aether-setup` skill: Configure cluster endpoints (global or project-level)
- Configuration discovery: Read from `~/.aether/config.yaml` or project `.env`
- Auto-discovery: Node classes and drivers discovered from Nomad API

### Changed
- `aether-init`: Two-phase workflow (analyze → generate), dev/prod config separation
- All skills: Removed hardcoded cluster info, now use config discovery
- Templates: Use placeholders (`__DOCKER_NODE_CLASS__`, `__REGISTRY__`, etc.)

## [0.1.0] - 2026-02-19

### Added
- Initial release
- `aether-init` skill: Project scaffolding for Aether deployment
- `aether-dev` skill: Dev environment deploy, test jobs, logs
- `aether-status` skill: Cluster and service status query
- `aether-deploy` skill: Production deployment with approval
- `aether-rollback` skill: Production rollback
- `deploy-doctor` agent: Deployment failure diagnostics
- `node-maintenance` agent: Node maintenance orchestration
