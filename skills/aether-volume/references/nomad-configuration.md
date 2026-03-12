# Nomad 配置生成

## 目录结构

```
/opt/aether-volumes/
└── <project-name>/
    ├── data/
    ├── logs/
    └── uploads/
```

## Nomad client.hcl 配置

```hcl
# /opt/nomad/config/client.hcl
client {
  enabled    = true
  node_class = "heavy_workload"

  # <project-name> volumes
  host_volume "<project-name>-data" {
    path      = "/opt/aether-volumes/<project-name>/data"
    read_only = false
  }

  host_volume "<project-name>-logs" {
    path      = "/opt/aether-volumes/<project-name>/logs"
    read_only = false
  }

  server_join {
    retry_join = ["192.168.69.70", "192.168.69.71", "192.168.69.72"]
  }
}
```

## 在 Nomad Job 中使用

```hcl
job "my-api" {
  group "app" {
    # 声明使用 host volume
    volume "data" {
      type      = "host"
      source    = "my-api-data"
      read_only = false
    }

    task "app" {
      # 挂载到容器内
      volume_mount {
        volume      = "data"
        destination = "/app/data"
        read_only   = false
      }

      config {
        image = "my-api:latest"
        ports = ["http"]
      }
    }
  }
}
```

## 命名规范

| 组件 | 格式 | 示例 |
|-----|------|------|
| Host volume 名称 | `<project>-<volume>` | `my-api-data` |
| 目录路径 | `/opt/aether-volumes/<project>/<volume>` | `/opt/aether-volumes/my-api/data` |
