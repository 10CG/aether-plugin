# Nomad Job 模板

模板按环境分为 dev 和 prod 两套，关键差异见末尾对照表。

## 占位符说明

| 占位符 | 说明 | 来源 |
|--------|------|------|
| `__PROJECT_NAME__` | 项目名称 | 当前目录名或用户输入 |
| `__IMAGE__` | 容器镜像地址 | CI 流水线替换 |
| `__PORT__` | 服务端口 | 项目分析或用户输入 |
| `__REPLICAS__` | 副本数 (prod) | 默认 2，可调整 |
| `__DOCKER_NODE_CLASS__` | Docker 节点类型 | 从 API 发现 |
| `__EXEC_NODE_CLASS__` | exec 节点类型 | 从 API 发现 |

---

## Docker 服务 — dev

`deploy/nomad-dev.hcl`:

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "__DOCKER_NODE_CLASS__"
  }

  group "app" {
    count = 1

    network {
      port "http" { to = __PORT__ }
    }

    task "server" {
      driver = "docker"

      config {
        image = "__IMAGE__"
        ports = ["http"]
      }

      resources {
        cpu    = 300
        memory = 256
      }

      service {
        name     = "__PROJECT_NAME__"
        port     = "http"
        provider = "consul"
        tags     = ["dev", "__PROJECT_NAME__"]

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
```

## Docker 服务 — prod

`deploy/nomad-prod.hcl`:

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "__DOCKER_NODE_CLASS__"
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  group "app" {
    count = __REPLICAS__

    spread {
      attribute = "${node.unique.id}"
    }

    network {
      port "http" { to = __PORT__ }
    }

    task "server" {
      driver = "docker"

      config {
        image = "__IMAGE__"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "__PROJECT_NAME__"
        port     = "http"
        provider = "consul"
        tags     = ["prod", "__PROJECT_NAME__"]

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
```

## Docker 服务 + 持久化存储 — prod (NFS-virtiofs 共享卷)

`deploy/nomad-prod.hcl` (有状态变体):

> **前置要求**: volume 必须在**所有** heavy 节点上都已注册 — 单节点注册
> 会变成 blast-radius trap (任一节点宕机即服务不可用)。Aether 集群的
> `/opt/aether-volumes/` 是 NFS-virtiofs 共享挂载，物理上已在所有 heavy 节点,
> 只需 Nomad 注册全覆盖即可。详见 [`docs/guides/nfs-virtiofs-host-volumes.md`](../../../../docs/guides/nfs-virtiofs-host-volumes.md)。
>
> 注册命令 (**对每个 heavy 节点**都执行):
> ```bash
> aether volume create --node heavy-1 --project __PROJECT_NAME__ --volumes data
> aether volume create --node heavy-2 --project __PROJECT_NAME__ --volumes data
> aether volume create --node heavy-3 --project __PROJECT_NAME__ --volumes data
> ```

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  # node.class 值由集群实际配置决定, 常见: heavy_workload / light_exec
  # (查询: curl $NOMAD_ADDR/v1/nodes | jq '.[].NodeClass')
  constraint {
    attribute = "${node.class}"
    value     = "__DOCKER_NODE_CLASS__"
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  group "app" {
    count = 1  # 有状态服务单副本

    # stop-before-start migration: 保护 lockfile (postgres postmaster.pid) +
    # 避免并发写入者 (redis AOF). drain-not-partition 是必须的操作纪律。
    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "5m"    # 慢冷启动 (WAL recovery, RDB load) 可调至 10-15m
    }

    volume "data" {
      type   = "host"
      source = "__PROJECT_NAME__-data"
    }

    network {
      port "http" { to = __PORT__ }
    }

    task "server" {
      driver = "docker"

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      config {
        image = "__IMAGE__"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "__PROJECT_NAME__"
        port     = "http"
        provider = "consul"

        check {
          type     = "http"
          path     = "/health"
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
```

**部署后验证**:

```bash
# 确认 volume 在所有 heavy 节点都已注册 (期望: 0 条 dev-db 相关的 finding)
aether doctor --check host_volume_parity --json | jq '.data.checks[0].detailed_findings[] | select(.consumer=="__PROJECT_NAME__")'

# 验证 constraint 不再将服务锁死在单节点
nomad job inspect __PROJECT_NAME__ | jq '.Job.Constraints'
```

**反模式** (不要这样做):

- ❌ `constraint { attribute = "${node.unique.name}"; value = "heavy-1" }` — 单节点 pin, 2026-04-24 `dev-db` 事故模式
- ❌ 省略 `migrate` stanza — drain 时新旧 alloc 可能并行写入, corrupt redis AOF
- ❌ 只在 heavy-1 注册 volume 而 constraint 是 `node.class` — 调度器选中 h-2/h-3 会报 "computed class ineligible"

## exec 服务 — dev

`deploy/nomad-dev.hcl`:

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "__EXEC_NODE_CLASS__"
  }

  group "worker" {
    count = 1

    task "run" {
      driver = "exec"

      config {
        command = "/opt/apps/__PROJECT_NAME__/run.sh"
      }

      env {
        APP_ENV = "development"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
```

## exec 服务 — prod

`deploy/nomad-prod.hcl`:

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "__EXEC_NODE_CLASS__"
  }

  group "worker" {
    count = __REPLICAS__

    task "run" {
      driver = "exec"

      config {
        command = "/opt/apps/__PROJECT_NAME__/run.sh"
      }

      env {
        APP_ENV = "production"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name     = "__PROJECT_NAME__"
        provider = "consul"

        check {
          type     = "script"
          command  = "/opt/apps/__PROJECT_NAME__/health.sh"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
```

## 定时任务 (batch + periodic)

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 * * * *"]  # 每小时
    prohibit_overlap = true
  }

  constraint {
    attribute = "${node.class}"
    value     = "__EXEC_NODE_CLASS__"
  }

  group "task" {
    task "run" {
      driver = "exec"

      config {
        command = "/opt/apps/__PROJECT_NAME__/run.sh"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
```

---

## 服务连接（Consul DNS）

Aether 集群中所有通过 Nomad 部署的服务都会注册到 Consul，可通过 DNS 自动发现。
应用连接其他服务时，应使用 Consul DNS 的 FQDN 格式而非硬编码 IP。

### 连接地址规则

| 格式 | 示例 | 说明 |
|------|------|------|
| `{name}.service.consul` (FQDN) | `postgres.service.consul` | **推荐** — 显式完整域名，不依赖 DNS search 配置 |
| `{name}` (短名) | `postgres` | 不推荐 — 依赖节点 `/etc/resolv.conf` 中的 `search consul`，不可靠 |

### HCL env 块示例

在 Nomad job 的 `task` 中通过 `env {}` 注入服务地址：

```hcl
      env {
        # 数据库 — Consul DNS 自动解析到当前健康实例
        DATABASE_URL = "postgres://user:pass@postgres.service.consul:5432/__PROJECT_NAME__"

        # Redis — 同理
        REDIS_URL = "redis://redis.service.consul:6379/0"

        # 其他常见服务
        MONGO_URI           = "mongodb://mongo.service.consul:27017/__PROJECT_NAME__"
        RABBITMQ_URL        = "amqp://guest:guest@rabbitmq.service.consul:5672"
        ELASTICSEARCH_URL   = "http://elasticsearch.service.consul:9200"
      }
```

> **边界说明 — 两种有效模式**: 上面 `env {}` + Consul DNS FQDN (`.service.consul`) 是
> **静态地址注入**模式 — 容器启动时拿到域名字符串, 每次连接都走 DNS 解析到当前健康实例,
> 过程中**不涉及 template 重渲染**, 天然免疫 Consul catalog 抖动问题。
>
> 另一种是 `template {}` + `service "..."` 模板指令的**动态渲染**模式 (见下文 registry auth
> 及 Render Flap Mitigation 章节) — 将服务地址展开成具体 IP:Port 写进 env 文件, Consul
> catalog 变化时 consul-template 会重渲染文件, 需要 `wait {}` + `change_mode="noop"` +
> `{{ if gt (len $svc) 0 }}` 三件套防御 render flap。
>
> **选择准则**: 应用能用 DNS 直连时优先 `env {}` FQDN 模式 (代码最简, 无重渲染隐患);
> 必须拿到具体 IP 或混合注入 Nomad Variables (如密钥 + 服务地址) 时才用 `template {}`。

### 工作原理

1. 服务通过 Nomad job 中的 `service { provider = "consul" }` 块注册到 Consul
2. Consul 在集群 DNS（端口 8600）中为每个健康服务创建 `{name}.service.consul` 记录
3. 集群节点上的 dnsmasq 将 `.consul` 域名转发到 Consul DNS
4. 应用代码无需修改，只需将连接地址改为 `.service.consul` 后缀

### 前置条件

- 集群 infra 节点需配置 dnsmasq 转发 `.consul` 查询（参见 `scripts/setup-consul-dns.sh`）
- 目标服务必须已部署且 Consul 健康检查通过
- 使用 FQDN（`{svc}.service.consul`）而非短名，避免 DNS search domain 不一致导致解析失败

---

## 私有 Registry Auth (forgejo.10cg.pub 等)

凭据不可以硬编码在 HCL。使用 Nomad Variables + `template { env=true }` 注入 env，`config.auth` 用 `${VAR}` 插值。

**首次部署前预置** (一次性):
```bash
aether env set --sensitive --job __PROJECT_NAME__ docker_auth_user simonfish
aether env set --sensitive --job __PROJECT_NAME__ docker_auth_password "$FORGEJO_PAT"
```

**HCL 片段** (加到 `task "server" {}` 内):
```hcl
template {
  destination = "${NOMAD_SECRETS_DIR}/docker-auth.env"
  env         = true
  change_mode = "noop"              # 文件被重写后不触发任务重启; 凭据轮换靠下次自然重启/主动部署生效
  splay       = "5s"                # splay 只在 change_mode=restart/signal 时生效; 此处保留作为切换 safety net
  wait {
    min = "10s"                     # <10s 闪失被 wait 吞掉 — 真正的 flap absorber
    max = "30s"
  }
  data        = <<-EOT
    {{- with nomadVar "nomad/jobs/__PROJECT_NAME__" -}}
    DOCKER_AUTH_USER={{ .docker_auth_user }}
    DOCKER_AUTH_PASSWORD={{ .docker_auth_password }}
    {{- end -}}
  EOT
}

config {
  image = "__IMAGE__"
  auth {
    username = "${DOCKER_AUTH_USER}"
    password = "${DOCKER_AUTH_PASSWORD}"
  }
}
```

> **关于此 template 的特殊性**: 该示例仅使用 `nomadVar` (Nomad Variables), 不涉及 `service "..."`
> 服务查询指令, 因此**不需要** `{{ if gt (len $svc) 0 }}` 服务守卫 — nomadVar 读取不存在的 path
> 时 `with` 块整体跳过, 语义已是安全的。`wait` + `change_mode = "noop"` 两件套在此仍然必要:
> Nomad Variables 变更 (凭据轮换) 不应自动重启 (见运维手册 [nomad-variables-docker-auth.md](../../../../docs/guides/nomad-variables-docker-auth.md) §轮换流程)。

**验证**: `aether doctor hardcoded_docker_auth` 应返回 0 findings。详见 `docs/guides/nomad-variables-docker-auth.md`。

## Consul Template 渲染抖动缓解 (Render Flap Mitigation)

> **Canonical source**: [docs/guides/consul-template-render-flap-mitigation.md](../../../../docs/guides/consul-template-render-flap-mitigation.md) (随 CLI v1.11.0 发布)
>
> 本章节仅列要点 — 语义细节、完整示例、边界分析以 canonical guide 为准。

### 为什么需要

当 template 块使用 `{{ range service "X" }}` 引导**必选** env 变量时, upstream 在 Consul 中短暂 0 healthy 实例会让整行不渲染 → 应用 env-check fast-fail。

**真实案例**: SilkNode 项目 silknode-web 于 2026-04-24 在 heavy-3 观察到 ~30s 自愈重启循环 (详见上游 issue 与本项目 issue #61)。

### 三件套 (required env 变量必选)

| 组件 | 作用 |
|---|---|
| `wait { min = "10s"; max = "30s" }` | debounce 渲染本身, 吞掉 <10s 闪失 — 这是**唯一**延迟/合并上游变更的机制 |
| `change_mode = "noop"` | 文件**仍会被重写**但**不触发任务重启** — 保护运行中进程内存中的老 env |
| `{{ if gt (len $svc) 0 }}` 守卫 | 0 实例时整行**不写入**, 避免 `REDIS_URL=` 空值 |

### 保护边界 (重要)

| 场景 | 本方案保护? |
|---|---|
| 上游 <10s 闪失 | ✅ wait 吸收, 不重渲染 |
| 上游 10-30s 闪失 | ✅ 文件缺行 + noop 不重启, 运行进程保留内存老值 |
| 任务本身重启期间上游 0 实例 | ❌ 冷启动读新文件失败 — 应用端负责启动重试 |
| 首次部署, 上游从未健康 | ❌ 等同裸 range — 用 Nomad 依赖排序先起 upstream |

**关键**: 本方案保护"运行中进程", 不保护"冷启动或任务重启读新文件"。应用端对必选 env 仍应实现启动重试或健康检查 back-off。

### `wait` vs `splay` 语义对比

| 机制 | 作用时机 | 对闪失 | 何时生效 |
|---|---|---|---|
| `wait { min max }` | **渲染前** debounce | ✅ 直接吞掉窗口内闪失 | 任何 `change_mode` |
| `splay` | **渲染后**的**重启时机**随机化 | ❌ 不影响渲染频率 | 仅 `change_mode = "restart"` 或 `"signal"` |

`splay = "5s"` 在 `change_mode = "noop"` 时无实际作用, 但保留声明无害 (便于未来切换 change_mode 时不再改)。

### `{{ env }}` ≠ 上次渲染值 (反直觉陷阱)

`{{ env "REDIS_URL" }}` 读 **consul-template daemon 的进程环境**, 不是上次渲染的文件内容。冷启动或任务重启后进程 env 不含渲染产出的值, 返回空串 — 与裸 range 行为**等价失败**。

**永远不要**把 `{{ env "X" }}` 当作 fallback 使用。

### 两种模板写法并存: `env {}` + FQDN vs `template {}` + 守卫

Aether 支持两种服务依赖写法, 各有适用场景:

| 写法 | 适用场景 | 优点 | 局限 |
|---|---|---|---|
| `env { REDIS_URL = "redis://redis.service.consul:6379" }` + Consul DNS | 服务 IP/端口固定或由 DNS 解析, docker 网络可用 | 最简单, 无 template 渲染开销 | 端口动态分配时不适用; 依赖 Consul DNS |
| `template { ... {{ range service "X" }} ... }` + 三件套 | 动态端口或需要 `nomadVar` 注入 credentials | 灵活, 完整 Nomad Var + Consul service 集成 | 写错会抖动, 必须加守卫 |

新项目若 upstream 端口固定, 优先 `env {}` + FQDN; 若需要动态端口或合并 `nomadVar`, 用 `template {}` + 三件套。

### 进一步阅读

完整语义推导、诊断流程、已知限制详见 canonical guide (上方链接), 同时参考:
- 项目 issue [#61](https://forgejo.10cg.pub/10CG/Aether/issues/61) (触发背景)
- `aether doctor template_bare_range` — 检测既有部署是否有裸 range 模式

---

## dev vs prod 对照表

| 配置项 | dev | prod |
|--------|-----|------|
| 副本数 | 1 | 2+ (__REPLICAS__) |
| CPU | 300 (docker) / 100 (exec) | 500 (docker) / 200 (exec) |
| 内存 | 256 MB | 512 MB (docker) / 256 MB (exec) |
| update 策略 | 无 (直接替换) | 滚动更新 + auto_revert |
| spread | 无 | 分散到不同节点 |
| Consul tags | `["dev", ...]` | `["prod", ...]` |
| 健康检查 (exec) | 无 | script check |
| APP_ENV | development | production |
