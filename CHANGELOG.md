# Changelog

All notable changes to aether-plugin will be documented in this file.

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
