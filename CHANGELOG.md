# Changelog

All notable changes to aether-plugin will be documented in this file.

## [0.8.6] - 2026-03-12

### Changed
- **Skills Optimization**: Refactored skills using Progressive Disclosure pattern
  - `aether-doctor` SKILL.md: 1370 → 146 lines (89% reduction)
  - `aether-init` SKILL.md: 529 → 156 lines (70% reduction)

### Added
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
