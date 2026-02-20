# Nomad Job 模板

模板按环境分为 dev 和 prod 两套，关键差异见末尾对照表。

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
    value     = "heavy_workload"
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
    value     = "heavy_workload"
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

## Docker 服务 + 持久化存储 — prod

`deploy/nomad-prod.hcl` (有状态变体):

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "heavy_workload"
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = true
  }

  group "app" {
    count = 1  # 有状态服务单副本

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

## exec 服务 — dev

`deploy/nomad-dev.hcl`:

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "light_exec"
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
    value     = "light_exec"
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
    value     = "light_exec"
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

## 占位符说明

| 占位符 | 说明 | 示例 |
|--------|------|------|
| `__PROJECT_NAME__` | 项目名称 | `my-api` |
| `__IMAGE__` | 容器镜像地址 | `forgejo.10cg.pub/org/my-api:abc123` |
| `__PORT__` | 服务端口 | `3000` |
| `__REPLICAS__` | 副本数 (prod) | `2` |
