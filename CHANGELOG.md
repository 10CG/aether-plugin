# Changelog

All notable changes to aether-plugin will be documented in this file.

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
