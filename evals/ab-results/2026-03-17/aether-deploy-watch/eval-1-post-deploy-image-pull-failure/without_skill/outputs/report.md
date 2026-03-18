# nexus-api-dev 部署状态诊断报告

**时间**: 2026-03-18 12:43 UTC+8
**Job**: nexus-api-dev
**Nomad**: http://192.168.69.70:4646
**Consul**: http://192.168.69.70:8500

---

## 诊断结论

**服务本身完全正常**，所有容器运行健康、健康检查通过、Traefik 路由正确。用户无法访问的原因是 **Cloudflare Access 拦截了外部请求**，返回 302 重定向到 Cloudflare Access 登录页面。

---

## 详细检查结果

### 1. Nomad Job 状态: HEALTHY

| 检查项 | 结果 |
|--------|------|
| Job Status | `running` (Version 26) |
| Deployment | `successful` (1 Healthy, 0 Unhealthy) |
| Allocation | `bcd4b635` on `heavy-1`, ClientStatus=`running` |

**Task 状态**:

| Task | 状态 | 说明 |
|------|------|------|
| `migrate` (prestart) | `dead` (Exit Code 0) | 数据库迁移成功完成 |
| `api` (main) | `running` | 主 API 服务正常运行，无重启 |
| `worker` (sidecar) | `running` | ARQ Worker 正常运行，无重启 |

- 镜像: `forgejo.10cg.pub/10cg/nexus:8cfba04`
- 启动时间: 2026-03-17T23:10:29Z
- 无 OOM、无崩溃、无重启记录

### 2. Consul 健康检查: PASSING

```
Service: nexus-api-dev
Check: "service: nexus-api-dev check"
Status: passing
Output: HTTP GET http://192.168.69.80:28803/health: 200 OK
        {"status":"healthy","version":"0.1.0"}
```

**依赖服务状态**:
- `nexus-db-dev`: passing (PostgreSQL accepting connections)
- `nexus-redis-dev`: passing (TCP connect 192.168.69.81:6379 Success)

### 3. Traefik 路由: CONFIGURED

```
Router: nexus-api-dev@consulcatalog
Rule: Host(`nexus-dev.10cg.pub`)
Entrypoints: [web]  (port 80)
Status: enabled
Backend: http://192.168.69.80:28803 (UP)
```

**直接访问测试**:
- `curl http://192.168.69.80:28803/health` --> **200 OK** (直连容器端口)
- `curl -H "Host: nexus-dev.10cg.pub" http://192.168.69.80:80/health` --> **200 OK** (通过 Traefik)

### 4. 外部访问: BLOCKED BY CLOUDFLARE ACCESS

DNS 解析 `nexus-dev.10cg.pub` 指向 Cloudflare (104.21.58.104 / 172.67.159.3)。

**HTTPS 请求结果**:
```
HTTP/2 302
Location: https://10cg.cloudflareaccess.com/cdn-cgi/access/login/nexus-dev.10cg.pub?...
```

Cloudflare Access 要求身份验证，将所有请求重定向到登录页面。HTTP 请求也被 Cloudflare 强制跳转 HTTPS (301)。

### 5. 应用日志: NORMAL

```
INFO: Uvicorn running on http://0.0.0.0:8000
INFO: 127.0.0.1:* - "GET /health HTTP/1.1" 200 OK
INFO: 192.168.69.80:* - "GET /health HTTP/1.1" 200 OK
```

日志中只有健康检查请求，无错误、无异常堆栈。

---

## 根因分析

**问题不在部署层面，而在网络接入层面。**

`nexus-dev.10cg.pub` 域名通过 Cloudflare 代理，且配置了 Cloudflare Access 策略。外部用户访问时被 Cloudflare Access 拦截，需要通过身份验证才能到达后端服务。

可能的场景：
1. Cloudflare Access 策略新加或变更，之前可能没有配置
2. 用户的 Access 会话过期
3. 该域名本就需要 Access 认证，但用户不知道

---

## 修复建议

### 方案 A: 调整 Cloudflare Access 策略（推荐）

如果 `nexus-api-dev` 是需要公开访问的 API 服务:

1. 登录 Cloudflare Zero Trust Dashboard
2. 进入 **Access** > **Applications**
3. 找到覆盖 `nexus-dev.10cg.pub` 的 Access 策略
4. 选择以下之一:
   - **移除该域名的 Access 策略**（完全公开）
   - **添加 Bypass 规则**，例如对 `/health` 和 API 路径免认证
   - **添加 Service Token**，让客户端通过 `CF-Access-Client-Id` / `CF-Access-Client-Secret` 头访问

### 方案 B: 配置 Service Token（API 客户端场景）

如果需要保持 Access 保护但允许 API 调用:

1. 在 Cloudflare Zero Trust 创建 Service Token
2. 客户端请求时附带:
   ```
   CF-Access-Client-Id: <client-id>
   CF-Access-Client-Secret: <client-secret>
   ```

### 方案 C: 检查 Traefik 入口配置（次要优化）

当前 Traefik router 仅绑定 `web` (port 80) 入口，缺少 `websecure` (port 443)。建议在 Consul tags 中添加:

```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.nexus-api-dev.rule=Host(`nexus-dev.10cg.pub`)",
  "traefik.http.routers.nexus-api-dev.entrypoints=web,websecure",
  "traefik.http.routers.nexus-api-dev.tls=true",
  "traefik.http.routers.nexus-api-dev.priority=100"
]
```

> 注意: 如果 Cloudflare SSL 模式为 "Flexible"（Cloudflare -> Origin 走 HTTP），则当前仅绑定 `web` 入口是可以工作的。但如果 SSL 模式为 "Full" 或 "Full (Strict)"，则需要 `websecure` 入口并配置 TLS 证书。

---

## 快速验证步骤

```bash
# 1. 确认内网可达 (应返回 200)
curl http://192.168.69.80:28803/health

# 2. 确认 Traefik 路由正常 (应返回 200)
curl -H "Host: nexus-dev.10cg.pub" http://192.168.69.80:80/health

# 3. 修改 Cloudflare Access 后，验证外部可达
curl https://nexus-dev.10cg.pub/health
```
