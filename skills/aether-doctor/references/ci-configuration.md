# CI/CD 配置检查

## 检测 CI 平台

```bash
if [ -d ".forgejo/workflows" ]; then
  CI_PLATFORM="forgejo"
elif [ -d ".github/workflows" ]; then
  CI_PLATFORM="github"
elif [ -f ".gitlab-ci.yml" ]; then
  CI_PLATFORM="gitlab"
else
  CI_PLATFORM="none"
fi
```

## Secrets 配置规范

### Forgejo 环境

| Secret | 说明 | 自动注入 |
|--------|------|---------|
| `FORGEJO_USER` | 当前用户名 | ✅ |
| `FORGEJO_TOKEN` | 访问令牌 | ✅ |
| `NOMAD_ADDR` | Nomad API 地址 | ❌ |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ❌ |

### GitHub 环境

| Secret | 说明 | 自动注入 |
|--------|------|---------|
| `GITHUB_ACTOR` | 当前用户名 | ✅ |
| `GITHUB_TOKEN` | 访问令牌 | ✅ |
| `NOMAD_ADDR` | Nomad API 地址 | ❌ |
| `NOMAD_TOKEN` | Nomad 访问令牌 | ❌ |

## 常见配置问题

| 问题 | 当前配置 | 正确配置 |
|------|---------|---------|
| Registry 认证 | `secrets.REGISTRY_TOKEN` | `secrets.FORGEJO_TOKEN` |
| Registry 用户 | `secrets.REGISTRY_USERNAME` | `secrets.FORGEJO_USER` |
| Nomad 地址 | 硬编码 IP | `${{ secrets.NOMAD_ADDR }}` |

## 检查 Workflow 文件

```bash
# 扫描 secrets 引用
grep -r "secrets\." .forgejo/workflows/ | grep -v "^#"

# 检查硬编码地址
grep -r "192.168" .forgejo/workflows/
```

## 自动修复命令

```bash
# 替换错误的 secrets 名称
sed -i 's/secrets\.REGISTRY_TOKEN/secrets.FORGEJO_TOKEN/g' .forgejo/workflows/deploy.yaml
sed -i 's/secrets\.REGISTRY_USERNAME/secrets.FORGEJO_USER/g' .forgejo/workflows/deploy.yaml
```
