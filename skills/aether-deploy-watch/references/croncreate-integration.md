# CronCreate 集成 (ci-watch-hook 触发链)

deploy-watch 是 CI 推送后监控链的终端环节。完整链路：

```
git push
  → ci-watch-hook 检测推送，写入状态文件
  → CronCreate 创建定时轮询 CI 状态
  → CI 成功
  → CronCreate 触发 deploy-watch
```

### 触发方式

ci-watch-hook 在 CI 成功后，CronCreate 的 prompt 包含命令式指令：

```
IMMEDIATELY invoke /aether:deploy-watch {JOB_NAME} --version {SHA}
Do not summarize. Invoke the skill now.
```

### 状态文件

路径: `.aether/deploy-watch.state`

```yaml
sha: abc1234def567890abc1234def567890abc1234d
repo: 10CG/my-project
job_name: my-project
expected_image: forgejo.10cg.pub/10cg/my-project:abc1234def567890abc1234def567890abc1234d
phase: image | deploy | health | done | failed
started: 2026-03-31T10:00:00Z
```

### 阶段更新

deploy-watch 在每个 Step 转换时更新 `phase` 字段：

```bash
yq -i ".phase = \"deploy\"" .aether/deploy-watch.state
```

状态流转: `image → deploy → health → done` (正常) 或任意阶段 → `failed` (异常)。

用户也可以不依赖 ci-watch-hook，直接调用：
`/aether:deploy-watch my-api --version abc1234def567890abc1234def567890abc1234d`
