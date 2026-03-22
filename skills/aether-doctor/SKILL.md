---
name: aether-doctor
description: |
  Aether 环境诊断工具。检查 CLI、配置、集群连接、SSH、CI/CD 配置等环境状态，更新配置缓存。

  使用场景："诊断环境"、"检查配置"、"环境有问题"、"SSH 连接失败"、"CI 配置错误"、"首次使用"
argument-hint: "[--ssh|--cluster|--ci|--refresh] [--fix]"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, Write, AskUserQuestion
dependencies:
  cli:
    required: false
    role: "此 Skill 负责安装和检测 CLI，不是依赖方"
    install_capability: true
---

# Aether 环境诊断 (aether-doctor)

> **版本**: 2.1.0 | **优先级**: P0

## 快速开始

```
/aether:doctor           # 完整诊断
/aether:doctor --ssh     # 仅 SSH 检查
/aether:doctor --cluster # 仅集群连接
/aether:doctor --fix     # 自动修复问题
```

## 诊断项目

| 项目 | 检查内容 | 修复建议 |
|------|---------|---------|
| aether CLI | 安装状态、版本 | 自动安装 |
| 配置文件 | 格式、地址有效性 | 引导配置 |
| 集群连接 | Nomad/Consul API | 网络检查 |
| SSH 配置 | 密钥、权限、连接 | 提供命令 |
| CI/CD | Secrets 配置 | 修复建议 |

---

## 诊断流程

### Step 0: 确定缓存位置

```bash
if [ -f "./.aether/config.yaml" ]; then
  CACHE_FILE="./.aether/environment.yaml"
else
  CACHE_FILE="$HOME/.aether/environment.yaml"
fi
```

### Step 1: 检查 aether CLI

**检测逻辑**:
1. `command -v aether` → PATH 中
2. `~/.aether/aether` → 用户安装
3. `~/.aether/aether.exe` → Windows

**如果未安装或版本过低**:
- 提供交互式安装选项
- 详见 [CLI 安装流程](references/cli-installation.md)

### Step 2: 检查配置文件

```bash
# 检查配置
cat ~/.aether/config.yaml 2>/dev/null
cat ./.aether/config.yaml 2>/dev/null

# 配置优先级
# 环境变量 > 项目配置 > 全局配置
```

### Step 3-4: 集群验证和连接测试

详见 [集群拓扑和验证](references/cluster-validation.md)

### Step 5-6: SSH 检查和连接测试

详见 [SSH 诊断](references/ssh-diagnostics.md)

### Step 7: CI/CD 配置检查（可选）

详见 [CI 配置检查](references/ci-configuration.md)

### Step 8: 更新缓存

详见 [环境缓存格式](references/environment-cache.md)

---

## 详细参考

| 主题 | 文档 |
|------|------|
| CLI 安装流程 | [cli-installation.md](references/cli-installation.md) |
| 集群拓扑和验证 | [cluster-validation.md](references/cluster-validation.md) |
| SSH 诊断 | [ssh-diagnostics.md](references/ssh-diagnostics.md) |
| CI 配置检查 | [ci-configuration.md](references/ci-configuration.md) |
| 环境缓存格式 | [environment-cache.md](references/environment-cache.md) |
| 输出示例 | [output-examples.md](references/output-examples.md) |

---

## 与其他 Skills 的集成

### 缓存读取示例

```bash
# 获取集群信息
SERVERS=$(yq '.cluster.servers[] | .ip' ./.aether/environment.yaml)
LEADER=$(yq '.cluster.current_leader' ./.aether/environment.yaml)
HEAVY_NODES=$(yq '.cluster.clients[] | select(.class == "heavy_workload") | .ip' ./.aether/environment.yaml)
```

### 错误诊断建议

| 错误类型 | 建议 |
|---------|-----|
| `command not found` | 运行 `/aether:doctor` 安装 CLI |
| `connection refused` | 运行 `/aether:doctor --cluster` |
| `permission denied (SSH)` | 运行 `/aether:doctor --ssh` |

---

## 命令行等价操作

```bash
# 检查 CLI
aether version

# 检查集群
curl -s http://192.168.1.70:4646/v1/status/leader
curl -s http://192.168.1.70:4646/v1/nodes

# 测试 SSH
ssh -o ConnectTimeout=5 root@192.168.1.80 "hostname"
```

---

**Skill 版本**: 2.0.0
**最后更新**: 2026-03-12
**维护者**: 10CG Infrastructure Team
