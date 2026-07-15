<!-- aether:distilled-from https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/nfs-virtiofs-host-volumes.md ; advisory: 无自动 drift 脚本消费此行, 人工核对见发布检查清单 -->

# 有状态服务 HCL 骨架 (stateful-templates)

> `aether-conventions` skill 的 references，**自包含**——消费方读不到主仓其他文档，
> 本文件内容即运行时 SoT。同 plugin 的 `aether-init` skill `nomad-templates.md`（自包含，
> 完整 job 模板 + 占位符表）与本文件同源蒸馏，两者应保持一致；维护者权威版见文末
> maintainer-only 指针。

## 0. 四条铁律（冻结，一行制，与 SKILL.md §0 同字面）

1. **`<service>.service.consul` 永不钉 IP**。
2. **host_volume 全 heavy 节点注册**——单节点注册 = 单节点 pin，reschedule 到别的
   heavy 就找不到卷（`#56`）。
3. **已有数据的 volume 用 `--register-only`**——裸 `create` 对已有数据不安全（会重写
   `chmod`，可能破坏 postgres pgdata 700 权限等敏感数据）。
4. **stateful 服务必带 `migrate` stanza**——`max_parallel=1, health_check="checks",
   min_healthy_time="30s", healthy_deadline="5m"`，保护 postgres/redis 免于并发写入。

## 1. 为什么需要这套骨架（blast-radius 原理）

Nomad `host_volume` 默认是**单节点**概念——只在一个节点声明，consumer job 就被钉死在
那个节点。对 postgres/redis 这类有状态服务，这是 blast-radius trap：那个节点的 docker
daemon 重启 / 内核更新 / 硬件故障，服务直接下线且**无重调度路径**。2026-04-24 事故
（heavy-1 docker daemon 卡死 → `dev-db` postgres+redis 两组全下线）即此模式（`#56`）。

物理存储其实早已是共享的：集群跑的是 NAS 经 NFS，全部 heavy 节点经 virtiofs 挂到
`/opt/aether-volumes`——同字节、同 inode 空间，但 Nomad 不知道，因为 `host_volume`
声明没有覆盖到全部 heavy 节点。**修复方式**：在每个 heavy 节点都声明同名
`host_volume`；调度器就能看到多个合法落点，migrate 生效，数据从未真的移动过（本来就是
一份共享 NFS 挂载）。

## 2. HCL 骨架（可直接改名套用）

```hcl
job "__PROJECT_NAME__" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  # node.class 值以集群实际配置为准 (curl $NOMAD_ADDR/v1/nodes | jq '.[].NodeClass');
  # 有状态 docker 服务用 heavy_workload —— 唯一带 docker driver + NFS-virtiofs 共享挂载
  constraint {
    attribute = "${node.class}"
    value     = "heavy_workload"
  }

  group "db" {
    count = 1  # 有状态服务单副本

    # stop-before-start migration: 保护 lockfile (postgres postmaster.pid) +
    # 避免并发写入者 (redis AOF)。drain-not-partition 是必须的操作纪律 (§4)。
    migrate {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "5m"    # 慢冷启动 (WAL recovery / RDB load) 可调 10-15m
    }

    volume "data" {
      type      = "host"
      source    = "__PROJECT_NAME__-data"   # 须匹配 §3 注册的 host_volume 名
      read_only = false
    }

    network {
      port "db" { to = __PORT__ }
    }

    task "server" {
      driver = "docker"

      volume_mount {
        volume      = "data"
        destination = "/data"
      }

      config {
        image = "__IMAGE__"
        ports = ["db"]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      service {
        name     = "__PROJECT_NAME__"
        port     = "db"
        provider = "consul"     # 消费方连它时写 __PROJECT_NAME__.service.consul (§0-1)

        check {
          type     = "tcp"      # 或 http + path，按服务类型定
          interval = "10s"
          timeout  = "3s"
        }
      }
    }
  }
}
```

## 3. host_volume 全 heavy 注册

```bash
# 对每个 heavy 节点都执行 (数量以集群实际拓扑为准: curl $NOMAD_ADDR/v1/nodes | jq -r '.[].Name')
aether volume create --node heavy-1 --project __PROJECT_NAME__ --volumes data
aether volume create --node heavy-2 --project __PROJECT_NAME__ --volumes data
aether volume create --node heavy-3 --project __PROJECT_NAME__ --volumes data
# ... 覆盖全部 heavy 节点，不要只注册一部分

# 已有数据 (如从单节点补注册到其余节点) 用 --register-only，跳过 mkdir/chmod:
aether volume create --node heavy-2 --project __PROJECT_NAME__ --volumes data --register-only
```

完整命令/参数/幂等性检查见 `aether-volume` skill（执行层）；本文件只给决策速记，不重复
其命令细节。

## 4. 操作纪律

- **drain-not-partition**：共享存储下，两个 alloc 理论上可能同时跑在不同节点。
  Postgres 靠 `postmaster.pid` 防第二实例启动；**redis 无锁文件保护**，两个写者会
  corrupt AOF。用 `nomad node drain -enable` 有序迁移；**禁止** `kill -9` Nomad
  client——这会让 alloc 无 ACK 消失，Nomad 可能在原 task 还在写时就重调度。
- `migrate { max_parallel = 1 }` 是硬性要求，即便有 drain，未来 `count` 调整或一次
  错误的 update 仍可能触发并行迁移。
- 备份纪律不因共享存储而免除：共享存储只保证可用性，不保证持久性（一次误操作会瞬间
  同步到"其它节点"，因为是同一份字节）。

## 5. 部署后验证

```bash
# 确认 volume 在所有 heavy 节点都已注册 (期望: 0 条该服务的 finding)
aether doctor --check host_volume_parity --json | \
  jq '.data.checks[0].detailed_findings[] | select(.consumer=="__PROJECT_NAME__")'

# 确认 constraint 没有把服务锁死在单节点
nomad job inspect __PROJECT_NAME__ | jq '.Job.Constraints'
```

## 6. 反模式（不要这样做）

- ❌ `constraint { attribute = "${node.unique.name}"; value = "heavy-1" }` ——
  单节点 pin，2026-04-24 `dev-db` 事故模式本身。
- ❌ 省略 `migrate` stanza —— drain 时新旧 alloc 可能并行写入，corrupt redis AOF。
- ❌ 只在部分 heavy 节点注册 volume 而 constraint 是 `node.class` —— 调度器选中
  未注册的节点会报 "computed class ineligible"。
- ❌ 对已有数据的 volume 跑裸 `aether volume create`（非 `--register-only`）——
  会重写文件权限，可能破坏 postgres pgdata 等权限敏感数据。

## 关联

> ⚠️ 下列 `https://forgejo.10cg.pub/...` 链接均为 **maintainer-only / 需主仓 + Cloudflare
> Access 权限 / 请勿 fetch**——CF Access 网关后，消费方 AI 无凭据 fetch 会拿到 CF 登录页
> HTML（200 OK 但内容错），比相对路径 Read 失败更隐蔽误导。仅供人类维护者核对。

- Stateful canonical（完整拓扑 + ESTALE 风险姿态 + 备份纪律）：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/nfs-virtiofs-host-volumes.md
  (maintainer-only / 请勿 fetch)
- 事故前史：`#56`（host_volume 全 heavy 注册铁律的由来）· `#157`（light 节点共享存储扩展）
