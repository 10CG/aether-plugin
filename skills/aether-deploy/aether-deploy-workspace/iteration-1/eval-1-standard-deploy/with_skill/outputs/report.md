# aether-deploy 执行报告

> **Skill**: aether-deploy v0.3.0
> **日期**: 2026-03-17
> **服务**: my-api
> **目标版本**: v1.2.3
> **目标环境**: 生产 (prod)

---

## Step 1: 解析参数

从用户请求中提取以下信息:

| 参数 | 值 |
|------|-----|
| 服务名 | `my-api` |
| 目标版本 | `v1.2.3` |
| 镜像地址 | `forgejo.10cg.pub/10CG/my-api:v1.2.3` |
| Nomad 地址 | `http://192.168.69.80:4646` |
| HCL 文件 | `deploy/nomad-prod.hcl` |
| 来源 | dev 环境验证通过（运行 2 天） |

**版本标签检查**: `v1.2.3` -- 非 `latest`，符合安全要求。

---

## Step 2: 验证镜像存在

**执行命令**:
```bash
docker manifest inspect forgejo.10cg.pub/10CG/my-api:v1.2.3
```

**结果**: **无法验证** -- 当前环境未安装 `docker` CLI，也无 `skopeo` / `crane` 等替代工具。

**备选验证** -- 尝试通过 Registry V2 API:
```bash
curl -s "https://forgejo.10cg.pub/v2/10CG/my-api/manifests/v1.2.3"
```
返回 HTTP 302 (Cloudflare Access 重定向)，无法直接验证。

**判定**: 镜像验证不可用。用户明确声明镜像地址为 `forgejo.10cg.pub/10CG/my-api:v1.2.3` 且已在 dev 环境运行 2 天。基于用户确认继续流程，但标记为 **WARNING**。

> **WARNING**: 镜像存在性未经自动验证。建议在有 Docker 环境的机器上手动执行:
> ```bash
> docker manifest inspect forgejo.10cg.pub/10CG/my-api:v1.2.3
> ```

---

## Step 3: 获取当前状态

**执行命令**:
```bash
curl -s "http://192.168.69.80:4646/v1/job/my-api" | jq -r '.TaskGroups[0].Tasks[0].Config.image'
```

**结果**: `job not found`

Nomad 集群确认连接正常 (Nomad v1.11.2, dc1)，但不存在名为 `my-api` 的生产 Job。同时检查了 `my-api-dev`、`my-api-prod` 等变体，均不存在。

**判定**: 这是 **首次生产部署**，非版本升级。无当前版本可对比。

---

## Step 4: 显示差异并确认

**应输出**:
```
部署确认
========
服务: my-api
当前版本: (无 - 首次部署)
目标版本: v1.2.3
镜像: forgejo.10cg.pub/10CG/my-api:v1.2.3
Nomad: http://192.168.69.80:4646
HCL: deploy/nomad-prod.hcl

部署类型: 首次部署 (新 Job)

确认部署到生产环境？ [y/N]
```

**实际结果**: **流程阻断**

检查 `deploy/nomad-prod.hcl` 文件:
- 当前工作目录 (`/home/dev/Aether`) 下不存在 `deploy/nomad-prod.hcl`
- 全局搜索未找到任何 `my-api` 相关的 HCL 文件

**缺少 HCL 文件，无法继续部署。**

---

## Step 5: 执行部署

**状态**: 未执行 -- 被 Step 4 阻断

**预期执行命令** (如果 HCL 文件存在):
```bash
# 替换镜像占位符并提交 Job
cat deploy/nomad-prod.hcl \
  | sed "s|__IMAGE__|forgejo.10cg.pub/10CG/my-api:v1.2.3|g" \
  | nomad job run -address=http://192.168.69.80:4646 -
```

或通过 Nomad API:
```bash
cat deploy/nomad-prod.hcl \
  | sed "s|__IMAGE__|forgejo.10cg.pub/10CG/my-api:v1.2.3|g" \
  | nomad job run -output - \
  | curl -s -X POST "http://192.168.69.80:4646/v1/jobs" -d @-
```

---

## Step 6: 等待健康检查

**状态**: 未执行 -- 被 Step 4 阻断

**预期流程**:
```bash
# 轮询 allocation 状态
while true; do
  STATUS=$(curl -s "http://192.168.69.80:4646/v1/job/my-api/allocations" \
    | jq '[.[] | select(.ClientStatus == "running")] | length')
  DESIRED=$(curl -s "http://192.168.69.80:4646/v1/job/my-api" \
    | jq '.TaskGroups[0].Count')
  if [ "$STATUS" -eq "$DESIRED" ]; then
    echo "All allocations running"
    break
  fi
  sleep 5
done

# Consul 健康检查
curl -s "http://192.168.69.70:8500/v1/health/service/my-api?passing" | jq 'length'
```

---

## Step 7: 输出结果

**状态**: 部署未完成

---

## 最终结论

### 部署结果: BLOCKED

部署流程在 Step 4 被阻断，原因如下:

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 参数解析 | PASS | 服务名、版本、镜像地址均已提取 |
| 版本标签 | PASS | v1.2.3，非 latest |
| 镜像验证 | WARN | 环境无 docker CLI，无法自动验证 |
| Nomad 连接 | PASS | http://192.168.69.80:4646 正常 (v1.11.2) |
| 当前 Job | INFO | 不存在，属于首次部署 |
| HCL 文件 | **FAIL** | `deploy/nomad-prod.hcl` 不存在 |

### 需要用户解决

1. **提供 HCL 文件**: `deploy/nomad-prod.hcl` 在当前项目中不存在。请确认:
   - HCL 文件的正确路径（可能在 `my-api` 项目仓库中而非 Aether 仓库）
   - 或者需要先使用 `/aether:init` 生成部署配置

2. **镜像验证**: 建议在有 Docker 的环境中确认镜像可拉取:
   ```bash
   docker pull forgejo.10cg.pub/10CG/my-api:v1.2.3
   ```

3. **确认 Job 名称**: 生产环境的 Nomad Job 名称是否为 `my-api`，还是 `my-api-prod`？

### 恢复部署

一旦上述问题解决，可重新执行:
```
/aether:deploy my-api v1.2.3
```

或者如果需要先初始化项目:
```
/aether:init --lang <语言> --port <端口>
```
然后再执行部署。

### 回滚提示

因部署未实际执行，无需回滚。如果后续部署后出现问题，使用:
```
/aether:rollback my-api
```
