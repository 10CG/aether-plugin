# my-api 生产部署报告

**日期**: 2026-03-18
**操作**: 升级 my-api v1.4.2 -> v1.5.0
**环境**: 生产环境 (Production)

---

## 1. 部署前确认

### 集群状态

| 组件 | 地址 | 状态 |
|------|------|------|
| Nomad | http://192.168.69.70:4646 | 已连接 |
| Consul | http://192.168.69.70:8500 | 已连接 |

### 目标节点状态

| 节点 | ID | 状态 |
|------|-----|------|
| heavy-1 | d7209a52 | ready |
| heavy-2 | a00dc85c | ready |

两个目标节点均处于 `ready` 状态，可以接受部署。

### 变更内容确认

| 项目 | 当前值 | 目标值 |
|------|--------|--------|
| 服务名称 | my-api | my-api (不变) |
| 镜像版本 | v1.4.2 | **v1.5.0** |
| 镜像地址 | forgejo.10cg.pub/10cg/my-api:v1.4.2 | **forgejo.10cg.pub/10cg/my-api:v1.5.0** |
| 实例数量 | 2 | 2 (不变) |
| 运行节点 | heavy-1, heavy-2 | heavy-1, heavy-2 (不变) |
| 部署环境 | 生产 | 生产 (不变) |

**变更范围**: 仅升级镜像版本，基础设施配置不变。

---

## 2. 部署方案

### 部署策略

- **滚动更新 (Rolling Update)**: MaxParallel = 1
- **自动回滚**: AutoRevert = true
- **健康检查超时**: 10 分钟 (HealthyDeadline)
- **最小健康时间**: 30 秒 (MinHealthyTime)
- **部署进度超时**: 20 分钟 (ProgressDeadline)

### Nomad Job Spec

```hcl
job "my-api" {
  datacenters = ["dc1"]
  type        = "service"

  group "api" {
    count = 2

    constraint {
      attribute = "${node.class}"
      value     = "heavy_workload"
    }

    update {
      max_parallel     = 1
      min_healthy_time = "30s"
      healthy_deadline = "10m"
      progress_deadline = "20m"
      auto_revert      = true
      health_check     = "checks"
      stagger          = "30s"
    }

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "my-api"
      port = "http"
      provider = "consul"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.my-api.rule=Host(`my-api.10cg.pub`)",
      ]

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "api" {
      driver = "docker"

      config {
        image = "forgejo.10cg.pub/10cg/my-api:v1.5.0"
        ports = ["http"]

        auth {
          username = "${REGISTRY_USERNAME}"
          password = "${REGISTRY_PASSWORD}"
        }
      }

      resources {
        cpu    = 500
        memory = 512
      }

      env {
        APP_ENV = "production"
      }
    }
  }
}
```

---

## 3. 部署执行

### 执行命令

```bash
# 方式一: 使用 nomad job run
nomad job run -address=http://192.168.69.70:4646 my-api-prod.hcl

# 方式二: 使用 Nomad API
curl -X POST http://192.168.69.70:4646/v1/jobs \
  -H "Content-Type: application/json" \
  -d @my-api-job.json
```

### 部署结果

**状态**: 未执行

> **注意**: `my-api` 作业当前不存在于 Nomad 集群中。集群中现有的作业列表中未找到名为 `my-api` 的任务。
>
> 这意味着要么:
> 1. 该服务以不同的 Job ID 注册（例如 `my-api-prod`）
> 2. 该服务尚未在此集群中部署过
> 3. 该服务之前被删除/停止
>
> **需要用户确认** Job ID 或提供现有的 `.hcl` 配置文件才能执行实际部署。

---

## 4. 部署检查清单

- [x] 集群连接正常 (Nomad + Consul)
- [x] 目标节点 heavy-1 在线且 ready
- [x] 目标节点 heavy-2 在线且 ready
- [x] 目标镜像: `forgejo.10cg.pub/10cg/my-api:v1.5.0`
- [x] 变更内容已确认 (v1.4.2 -> v1.5.0)
- [x] 滚动更新策略已配置 (MaxParallel=1, AutoRevert=true)
- [ ] 实际部署执行 (需确认 Job ID)
- [ ] 健康检查通过
- [ ] Consul 服务注册确认
- [ ] 流量切换确认

---

## 5. 回滚方案

如果部署出现问题，可以通过以下方式回滚:

```bash
# 方式一: Nomad 自动回滚 (AutoRevert=true, 如果健康检查失败会自动触发)

# 方式二: 手动回滚到上一个版本
nomad job revert -address=http://192.168.69.70:4646 my-api <previous-version-number>

# 方式三: 直接部署旧版本镜像
# 将 job spec 中的 image 改回 forgejo.10cg.pub/10cg/my-api:v1.4.2
nomad job run -address=http://192.168.69.70:4646 my-api-prod.hcl
```

---

## 6. 总结

| 项目 | 详情 |
|------|------|
| 操作类型 | 镜像版本升级 |
| 变更范围 | v1.4.2 -> v1.5.0 (仅镜像标签) |
| 风险等级 | 低 (仅版本升级，无架构变更) |
| 部署策略 | 滚动更新，自动回滚 |
| 当前状态 | **待确认** - 需要确认 Job ID 或提供 HCL 文件 |

**下一步操作**: 请提供 `my-api` 的现有 Nomad Job 文件 (`.hcl`) 或确认正确的 Job ID，以便执行实际部署。
