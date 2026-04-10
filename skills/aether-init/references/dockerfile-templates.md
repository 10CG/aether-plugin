# Dockerfile 模板

> 这些模板都编码了 **Aether 环境下经过验证的最佳实践**。设计原理和踩坑
> 记录见 `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`。

---

## 关键设计决策

所有模板统一遵循以下原则：

1. **国内镜像** — npm 用 `registry.npmmirror.com`，pip 用 `mirrors.aliyun.com/pypi/simple/`。
   原因：Alpine 容器内直连公网会间歇性出现 `EIDLETIMEOUT`。
2. **3 次重试循环** — npm ci / pip install 套一个 retry 循环，预防
   瞬时网络抖动。
3. **多阶段构建 + layer caching** — 先 COPY deps manifest → install → 再 COPY source。
   这样只要 deps 不变 Docker 层就命中缓存。
4. **`COPY --chown`** — 创建非 root 用户后，用 `COPY --chown=user:group`
   一步到位，**不要**用 `RUN chown -R`（在大量文件时会产生几十秒的独立层）。
5. **`# syntax=docker/dockerfile:1`** — 第一行声明 parser directive。
6. **不使用** `RUN --mount=type=cache,target=...` — 在当前 runner 的 overlay
   文件系统上会报 `operation not supported`，详见 anti-patterns。

---

## Node.js (Express / Fastify / 通用后端)

```dockerfile
# syntax=docker/dockerfile:1
# 使用 Docker Hub 官方镜像 — 国内 node:22 镜像源 (docker.1ms.run) 覆盖不全
ARG NPM_REGISTRY=https://registry.npmmirror.com

FROM node:22-alpine AS deps
ARG NPM_REGISTRY
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm config set registry "$NPM_REGISTRY" && \
    for i in 1 2 3; do \
      npm ci --prefer-offline --no-audit && break; \
      echo "npm ci failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done

FROM node:22-alpine AS runtime
WORKDIR /app
# 先创建用户，再 COPY --chown (避免独立 chown 层)
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S app -G nodejs
COPY --from=deps --chown=app:nodejs /app/node_modules ./node_modules
COPY --chown=app:nodejs . .
USER app
EXPOSE 3000
ENV NODE_ENV=production
HEALTHCHECK --interval=10s --timeout=3s \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "server.js"]
```

## Node.js / Next.js (Web 应用)

```dockerfile
# syntax=docker/dockerfile:1
ARG NPM_REGISTRY=https://registry.npmmirror.com

FROM node:22-alpine AS deps
ARG NPM_REGISTRY
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm config set registry "$NPM_REGISTRY" && \
    for i in 1 2 3; do \
      npm ci --prefer-offline --no-audit && break; \
      echo "npm ci failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S nextjs -G nodejs
# Next.js standalone output
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
```

## Go

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS builder
WORKDIR /src
# 先 COPY 依赖文件，利用层缓存
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /app ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
# 非 root 用户
RUN addgroup -g 1001 -S app && adduser -u 1001 -S app -G app
COPY --from=builder --chown=app:app /app /app
USER app
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s \
  CMD wget -qO- http://localhost:8080/health || exit 1
CMD ["/app"]
```

## Python (FastAPI / 通用 web)

```dockerfile
# syntax=docker/dockerfile:1
# Stage 1: builder — 用 aliyun pip 镜像加速
FROM python:3.12-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml README.md ./
# 国内 pip 镜像 + 重试保护
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    pip config set global.trusted-host mirrors.aliyun.com && \
    pip config set global.timeout 300 && \
    for i in 1 2 3; do \
      pip install --no-cache-dir --user . && break; \
      echo "pip install failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done

# Stage 2: runtime
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*
# 先创建用户，再 COPY --chown (关键: 避免 RUN chown -R 层)
RUN useradd -m -u 1001 app
COPY --from=builder --chown=app:app /root/.local /home/app/.local
ENV PATH=/home/app/.local/bin:$PATH
ENV PYTHONPATH=/app/src
COPY --chown=app:app src/ ./src/
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -fsS http://localhost:8000/health || exit 1
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Python (requirements.txt 的老项目)

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/ && \
    pip config set global.trusted-host mirrors.aliyun.com && \
    pip config set global.timeout 300 && \
    for i in 1 2 3; do \
      pip install --no-cache-dir -r requirements.txt && break; \
      echo "pip install failed (attempt $i/3), retrying in 10s..." && sleep 10; \
    done
RUN useradd -m -u 1001 app
COPY --chown=app:app . .
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## 静态文件 (Nginx)

```dockerfile
# syntax=docker/dockerfile:1
# 如果需要先构建前端 (Vite / CRA / Next static export)，加一个 builder stage:
#
# FROM node:22-alpine AS builder
# ARG NPM_REGISTRY=https://registry.npmmirror.com
# WORKDIR /app
# COPY package.json package-lock.json ./
# RUN npm config set registry "$NPM_REGISTRY" && \
#     for i in 1 2 3; do npm ci && break; sleep 10; done
# COPY . .
# RUN npm run build
#
# FROM nginx:alpine
# COPY --from=builder /app/dist /usr/share/nginx/html

FROM nginx:alpine
COPY dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
HEALTHCHECK --interval=10s --timeout=3s \
  CMD wget -qO- http://localhost/health || exit 1
```

配套 `nginx.conf`:

```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    location /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

---

## Alpine vs Debian-slim 选择

| 基础镜像 | 优点 | 注意事项 |
|---------|------|---------|
| `alpine` (Node/Go) | 镜像最小 | musl libc — 某些 native 模块需额外 `apk add python3 make g++` |
| `slim` (Python) | glibc 兼容性最好 | 默认不装 curl / build tools，需 `apt-get install` |

**经验**：Node 用 alpine，Python 用 slim。Go 可以用 alpine 或 scratch。

---

## 常见陷阱快速参考

| 症状 | 原因 | 修复 |
|------|------|------|
| `npm error code EIDLETIMEOUT` | 容器访问 npmjs.org 瞬时故障 | ✅ 已用 npmmirror + 重试 |
| `pip timeout` | 容器访问公网 pypi 不稳定 | ✅ 已用 aliyun + 重试 |
| `RUN chown -R` 占 40+ 秒 | 大量文件在独立层重写 | ✅ 已改 `COPY --chown` |
| `docker.1ms.run/library/node:22: not found` | 国内镜像源未同步新版本 | ✅ 已改为 Docker Hub 官方 |
| `operation not supported` on `/app/node_modules` | `--mount=type=cache` 与 overlay fs 冲突 | ✅ 未使用 cache mount |

更完整的故障诊断见 `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md § Troubleshooting`。
