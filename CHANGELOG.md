# Changelog

All notable changes to aether-plugin will be documented in this file.

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
