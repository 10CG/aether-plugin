# 项目分析

## 扫描项目特征

### 检测语言/框架

```bash
# Node.js
[ -f "package.json" ] && FRAMEWORK=$(jq -r '.dependencies | keys[]' package.json)

# Go
[ -f "go.mod" ] && MODULE=$(head -1 go.mod | cut -d' ' -f2)

# Python
[ -f "requirements.txt" ] || [ -f "pyproject.toml" ]

# Rust
[ -f "Cargo.toml" ]

# Java
[ -f "pom.xml" ] || [ -f "build.gradle" ]
```

### 检测已有配置

```bash
# 容器化
[ -f "Dockerfile" ] && echo "已有 Dockerfile"

# CI/CD
[ -d ".forgejo/workflows" ] || [ -d ".github/workflows" ]

# 部署配置
[ -d "deploy/" ]
```

### 检测项目特征

```bash
# 入口文件
ENTRY=$(find . -name "main.*" -o "main.go" | head -1)

# 端口
grep -r "PORT|listen" --include="*.go" --include="*.js"

# 数据库
grep -r "DATABASE|REDIS|MONGO" .env* 2>/dev/null

# 文件写入（判断有状态）
grep -r "os.Write|ioutil.WriteFile|fs.Write" --include="*.go"
```

## 决策逻辑

### Driver 选型

| 条件 | Driver |
|------|--------|
| 有 Dockerfile | docker |
| 需要系统依赖 | docker |
| 纯脚本/轻量级 | exec |

### Node Class 选择

| 项目类型 | Node Class |
|---------|------------|
| Web API | heavy_workload |
| 后台任务 | heavy_workload |
| 轻量脚本 | light_exec |

### Registry 格式

| Registry | 镜像格式 |
|----------|---------|
| Forgejo | `forgejo.10cg.pub/{org}/{image}:{tag}` |
| Docker Hub | `{org}/{image}:{tag}` |

### Tag 策略

| 环境 | Tag |
|------|-----|
| dev | latest 或分支名 |
| prod | semver (v1.2.3) |
