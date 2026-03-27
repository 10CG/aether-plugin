# 部署监控规则模板

## 注入位置

- 如果项目已有 `CLAUDE.md`：追加到文件末尾（检查是否已包含 "部署监控规则" 字样，避免重复）
- 如果不存在：创建 `CLAUDE.md` 并写入以下内容

## 注入内容

以下内容应根据项目实际信息替换占位符后写入：

```markdown
## 部署监控规则（Aether 集群）

每次代码推送到部署分支后，必须后台持续轮询部署状态，直到得出最终结果后主动告知用户：

1. **推送完成后**，立即启动后台轮询（run_in_background），每 15 秒检查一次
2. **部署成功**：主动告知用户 "部署成功"
3. **部署失败**：立即排查原因（CI 日志、Nomad allocation、容器日志），告知失败原因 + 修复建议
4. **不要只查一次就报"排队中"然后结束** — 必须等到最终结果

### 检查方法

```bash
# CI 状态
forgejo GET /repos/__OWNER__/__REPO__/commits/__SHA__/status

# Nomad Job 状态
curl -s http://__NOMAD_ADDR__/v1/job/__JOB_NAME__/allocations | jq '.[0].ClientStatus'
```

### 部署分支

- `__DEPLOY_BRANCH__` → 自动部署到 dev 环境
```

## 占位符替换

| 占位符 | 来源 |
|--------|------|
| `__OWNER__/__REPO__` | git remote URL 解析 |
| `__NOMAD_ADDR__` | `.aether/config.yaml` → `cluster.nomad_addr` |
| `__JOB_NAME__` | 项目名称（Phase 1 分析结果） |
| `__DEPLOY_BRANCH__` | 默认 `develop`，如检测到 `main` 则用 `main` |
| `__SHA__` | 运行时由 `git rev-parse HEAD` 获取（模板中保留占位符） |

## 注入逻辑

```bash
# 检查是否已注入
if [ -f "CLAUDE.md" ] && grep -q "部署监控规则" CLAUDE.md; then
    echo "⚠ CLAUDE.md 已包含部署监控规则，跳过"
else
    echo "## 部署监控规则..." >> CLAUDE.md  # 或创建新文件
    echo "✓ 已注入部署监控规则到 CLAUDE.md"
fi
```
