# Changelog

All notable changes to aether-plugin will be documented in this file.

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
