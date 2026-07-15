<!-- aether:distilled-from https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/cluster-dns-split-architecture.md ; advisory: 无自动 drift 脚本消费此行, 人工核对见发布检查清单 -->

# DNS 集成原理与自测 (dns-integration)

> `aether-conventions` skill 的 references，**自包含**——消费方读不到主仓其他文档，
> 本文件内容即运行时 SoT。维护者权威版（含 §3.2 分流器完整配方 + §4 VIP infra 运维面）
> 见文末 maintainer-only 指针，消费方无权限也不该照做。

## 0. 铁律（冻结，一行）

**任何消费方连接集群内的有状态服务（postgres/redis/…），一律用 `<service>.service.consul`
服务名，永不写死 IP。**

服务名跟着 Nomad alloc 走：服务 reschedule 换节点，名字自动解析到新 IP，消费方零感知。
写死 IP 是 blast-radius trap——一次重调度就让所有钉 IP 的消费方集体断线，而且断得静默
（health check 可能还是绿的，直到有人跑集成测试才发现）。`#185` → `#186` → `#241` 三次
复发全是违反这一条。

## 1. 为什么会有"分流"这回事（拓扑原理）

- **infra dnsmasq**（`192.168.69.70` / `.71` / `.72`）是集群 DNS 入口：`*.consul` 转给
  本机 Consul（`:8600`），公网域名转给代理网关（`.212`，fake-IP `198.18.0.0/16`）。
- **两个反直觉事实**（务必记住）：
  1. infra dnsmasq 解析公网域名返回的是**fake-IP**，不是真实 IP——只有能路由到 `.212`
     的机器（集群内 heavy/infra 节点）才能靠它上外网。**够不到 `.212` 的机器（如 LAN
     上的 dev 容器）不能整机切到内网 dnsmasq，否则公网全断**——这就是为什么 LAN dev
     机必须"按域名分流"而不是"整体换 DNS"。
  2. `*.10cg.local` 在集群 DNS 里**无任何解析**（dnsmasq 和 Tailscale MagicDNS 都返回
     空）。它只是部分机器 `resolv.conf` 的 search 后缀，底下没有真实 DNS 区——**不要
     依赖 `.10cg.local` 名字连服务**。

## 2. 按消费方分类（先判你是哪类，决定要不要配置）

| 类型 | `.consul` 怎么解析 | 需要的动作 |
|---|---|---|
| **A. 集群内 Nomad job**（绝大多数场景） | Nomad 自动把容器 DNS 指向 infra dnsmasq | **无**，直接写 `X.service.consul` |
| **C. LAN 内 dev 容器/机器**（临时手写 dev env） | 需本机装本地 dnsmasq 分流器 | 见 §4 |
| **D. 集群外/漫游设备**（Tailscale 外网访问） | 需 subnet router 广播内网段 | 依赖 `#244`，未落地 |
| **E. 无法改 resolver 的黑盒设备** | 解析不了 `.consul` | 需 keepalived VIP（infra 运维面，非本域） |

## 3. Case A — Nomad job，零配置

```
DATABASE_URL=postgres://<user>:<pass>@dev-db.service.consul:5432/app
REDIS_URL=redis://cache.service.consul:6379
```

写完就完事——不需要装任何东西、改任何 resolver。

## 4. Case C — LAN dev 容器，自测 + 决策桥

**先自测**（零风险，不改任何配置）：

```bash
dig +short @127.0.0.1 <name>.service.consul
```

- **解析到内网 IP**（如 `192.168.69.82`）→ 本机已装本地分流器，照常用 consul 名，到此
  为止。
- **失败 / NXDOMAIN** → 本机缺本地 dnsmasq 分流器。**决策桥**（拿不到完整配方时仍要有
  的自包含安全动作，依序执行）：
  1. **绝不**把 IP 钉进任何可能进 HCL / Nomad job 的文件——这正是 `#241` 的复发路径。
  2. 纯本地一次性 dev 文件确需临时用 IP，**必须**显式标注 `# dev-box-local-only`，且
     **绝不**进 HCL / Nomad job 定义。
  3. 推荐装本地 dnsmasq 分流器（`*.consul` 转发到 infra 三台冗余 dnsmasq，其余走干净
     公网 resolver）——完整可复制配方是**易变配方**（随集群拓扑演进腐化，且明确属
     10cg.local 地界），本文件不 verbatim 复制，见文末 maintainer-only 指针。

**装完分流器后复测**（原理相同，命令不变）：

```bash
dig +short @127.0.0.1 dev-db.service.consul   # 期望: 内网 IP, 非超时/NXDOMAIN
dig +short @127.0.0.1 github.com              # 期望: 真实 IP, 非 198.18.x fake-IP
aether doctor --check consul_dns              # 期望: PASS
```

> `consul_dns` 在 dev 机上报 WARN **不是噪音**——2026-06-02 曾被当噪音忽略，那正是
> `#241` 提前 6 周的预警信号。WARN = 该机缺本节分流器的机械信号，别忽略。

## 5. Case D / E — 依赖 #244，只给方向不给配方

- **D（集群外/漫游设备）**：需要 subnet router 广播 `192.168.69.0/24` 段才够得到
  dnsmasq；这条路径依赖 `#244`（集群外消费者服务发现），**尚未落地**。本域暂不发运
  机制细节。
- **E（无法改 resolver 的黑盒设备）**：给目标服务挂一个 keepalived VIP，设备连 VIP。
  这是 infra 运维面（黑盒设备接线 + keepalived 配置），不是消费方 repo 里能做的事，
  超出本 skill 范围。

## 6. 自测命令合集

```bash
# 本机是否已具备内网 DNS 分流 (零风险，只读)
dig +short @127.0.0.1 <name>.service.consul

# 公网解析是否干净 (非 fake-IP 198.18.x，分流器场景专用)
dig +short @127.0.0.1 github.com

# 官方健康检查 (任何应解析 .consul 的机器都能跑)
aether doctor --check consul_dns
```

## 关联

> ⚠️ 下列 `https://forgejo.10cg.pub/...` 链接均为 **maintainer-only / 需主仓 + Cloudflare
> Access 权限 / 请勿 fetch**——该域名在 CF Access 网关之后，消费方 AI 若无 CF 凭据对其
> 发 WebFetch，会拿到 CF 登录页 HTML（200 OK 但内容是错的），比"文件不存在"更隐蔽误导。
> 这些链接只为**人类维护者**核对用；消费方 AI 读不到、也不该尝试读。

- DNS canonical（含 §3.2 分流器完整配方 + §4 VIP 完整语义）：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/cluster-dns-split-architecture.md
  (maintainer-only / 请勿 fetch)
- 事故前史：`#185` / `#186` / `#241`（同根因三次复发）· `#244`（case D/E 依赖）
