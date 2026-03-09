# OpenSpec: CLI Installation Enhancement

> **ID**: cli-installation-enhancement
> **Status**: implemented
> **Created**: 2026-03-09
> **Author**: Claude Opus 4.6
> **Affected Components**: aether-plugin (aether-doctor), aether-cli (build)

---

## Problem Statement

### Current Issues

1. **Manual CLI Installation**: Users must manually build and install aether-cli, no guided installation
2. **No Version Compatibility Check**: aether-plugin doesn't verify CLI version compatibility
3. **Large Binary Size**: aether-cli compiled binary is large (~30-40MB) due to HashiCorp SDK dependencies
4. **No Download Source**: No pre-built binaries available for download

### User Impact

- New users struggle with environment setup
- Version mismatch causes unexpected behavior
- Slow installation due to large binary

---

## Proposed Solution

### Solution Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    aether-doctor Step 1                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Check aether CLI                                               │
│       │                                                         │
│       ├── Found ────────────────────► Check Version             │
│       │                                  │                      │
│       │                                  ├── Compatible ──► OK  │
│       │                                  │                      │
│       │                                  └── Incompatible       │
│       │                                         │               │
│       │                                         ▼               │
│       │                                    [方案C] 提示升级     │
│       │                                    提供下载/构建命令    │
│       │                                    可触发[方案A]        │
│       │                                                         │
│       └── Not Found ────────────────► [方案A] 自动安装          │
│                                              │                  │
│                                              ▼                  │
│                                        ┌─────────────┐          │
│                                        │ 检测平台    │          │
│                                        │ 检测架构    │          │
│                                        └──────┬──────┘          │
│                                               │                 │
│                                    ┌──────────┴──────────┐      │
│                                    │                     │      │
│                               有预构建二进制          无预构建   │
│                                    │                     │      │
│                                    ▼                     ▼      │
│                              下载并安装            从源码构建   │
│                                                       (go build)│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 方案A: 自动安装流程

```bash
# 1. 检测系统环境
OS=$(uname -s | tr '[:upper:]' '[:lower:]')  # linux/darwin/windows
ARCH=$(uname -m)  # x86_64/arm64

# 2. 尝试从发布源下载
RELEASE_URL="https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest"

# 3. 下载并安装
# curl -sL "${RELEASE_URL}/aether-${OS}-${ARCH}" -o /usr/local/bin/aether
# chmod +x /usr/local/bin/aether

# 4. 如果无预构建，从源码构建
# git clone https://forgejo.10cg.pub/10CG/aether-cli.git /tmp/aether-cli
# cd /tmp/aether-cli && go build -ldflags="-s -w" -o /usr/local/bin/aether .
```

### 方案C: 手动安装命令（可触发方案A）

当检测到 CLI 未安装或版本不兼容时，提供详细安装指南：

```markdown
## aether CLI 安装

检测到 aether CLI 未安装或版本过低。

当前要求: >= v0.7.0

### 选项 1: 自动安装（推荐）

是否立即自动安装？[Y/n]

### 选项 2: 手动安装

#### Linux/macOS
```bash
# 下载预构建版本
curl -sL https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest | \
  jq -r '.assets[] | select(.name | contains("linux-amd64")) | .browser_download_url' | \
  xargs curl -sL -o /usr/local/bin/aether
chmod +x /usr/local/bin/aether
```

#### Windows (PowerShell)
```powershell
# 下载预构建版本
Invoke-WebRequest -Uri "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest/download/aether-windows-amd64.exe" -OutFile "aether.exe"
```

#### 从源码构建
```bash
git clone https://forgejo.10cg.pub/10CG/aether-cli.git
cd aether-cli
go build -ldflags="-s -w" -o /usr/local/bin/aether .
```
```

---

## Implementation Details

### 1. aether-cli VERSION 文件

在 aether-cli 根目录添加 VERSION 文件（已存在）：
```
0.7.0
```

### 2. aether-plugin 版本要求

在 aether-plugin 中添加 CLI 版本要求配置：

```yaml
# .claude-plugin/plugin.json (新增字段)
{
  "version": "0.8.3",
  "cli": {
    "minVersion": "0.7.0",
    "recommendedVersion": "0.7.0"
  }
}
```

### 3. aether-doctor 增强

**Step 1: 检查 CLI 版本**

```markdown
### Step 1: 检查 aether CLI

#### 1.1 检查命令是否存在

\`\`\`bash
which aether || where aether
\`\`\`

- 如果不存在 → 执行 [方案A] 自动安装 或 提供 [方案C] 手动命令

#### 1.2 检查版本兼容性

\`\`\`bash
aether version --json 2>/dev/null || aether version
\`\`\`

- 读取 plugin.json 中的 `cli.minVersion`
- 比较当前版本是否 >= minVersion
- 不兼容 → 提供升级命令，可触发自动安装

#### 1.3 版本兼容性矩阵

| Plugin Version | CLI Min Version | Notes |
|---------------|-----------------|-------|
| 0.8.x         | 0.7.0           | 故障转移支持 |
| 0.9.x         | 0.8.0           | TBD |
\`\`\`

### 4. CLI 二进制优化

**构建命令优化**：

```bash
# 标准构建（优化大小）
go build -ldflags="-s -w" -o aether .

# 进一步压缩（可选，需要 upx）
go build -ldflags="-s -w" -o aether .
upx --best aether
```

**预期效果**：

| 优化方式 | 大小 (amd64) | 减少 |
|---------|-------------|------|
| 无优化 | ~40MB | - |
| -ldflags="-s -w" | ~28MB | 30% |
| + UPX | ~10MB | 75% |

### 5. 发布流程

创建 CI/CD 自动发布预构建二进制：

```yaml
# .forgejo/workflows/release.yaml
on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        goos: [linux, darwin, windows]
        goarch: [amd64, arm64]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - name: Build
        env:
          GOOS: ${{ matrix.goos }}
          GOARCH: ${{ matrix.goarch }}
        run: |
          go build -ldflags="-s -w" -o aether-${{ matrix.goos }}-${{ matrix.goarch }} .
      - name: Release
        uses: actions/forgejo-release@v1
        with:
          files: aether-*
```

---

## Task Breakdown

### Task 1: CLI VERSION 嵌入（aether-cli）
- 在编译时将 VERSION 嵌入二进制
- 添加 `aether version` 子命令
- 文件: `cmd/version.go`, `internal/version/version.go`

### Task 2: Plugin 版本配置（aether-plugin）
- 在 plugin.json 添加 CLI 版本要求
- 文件: `.claude-plugin/plugin.json`

### Task 3: aether-doctor 增强（aether-plugin）
- 增强 Step 1 检查 CLI 版本兼容性
- 添加自动安装流程
- 添加手动安装命令
- 文件: `skills/aether-doctor/SKILL.md`

### Task 4: CLI 构建优化（aether-cli）
- 更新 Makefile/构建脚本
- 添加 -ldflags 优化
- 可选: 添加 UPX 压缩
- 文件: `Makefile` 或 `build.sh`

### Task 5: 发布流程（aether-cli）
- 创建 Forgejo Actions 发布 workflow
- 自动构建多平台二进制
- 文件: `.forgejo/workflows/release.yaml`

---

## Success Criteria

- [ ] aether-doctor 检测 CLI 未安装时提供自动安装选项
- [ ] aether-doctor 检测 CLI 版本不兼容时提供升级选项
- [ ] 自动安装支持 Linux/macOS/Windows
- [ ] 手动安装命令清晰完整
- [ ] CLI 二进制大小减少至少 30%
- [ ] 多平台预构建二进制可通过 API 下载

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| 下载源不可用 | 中 | 高 | 提供从源码构建的备选方案 |
| 版本比较逻辑错误 | 低 | 中 | 使用 semver 库进行版本比较 |
| UPX 压缩后杀毒误报 | 低 | 低 | UPX 作为可选步骤 |

---

## References

- [aether-doctor SKILL.md](../../skills/aether-doctor/SKILL.md)
- [aria OpenSpec 规范](/path/to/aria/openspec)
- [Go 编译优化](https://golang.org/cmd/link/)
- [UPX 压缩工具](https://upx.github.io/)
