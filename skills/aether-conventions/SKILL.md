---
name: aether-conventions
description: |
  Aether 集成规范速查 —— 四域 investigation-first hub。消费方项目里临时手写 dev env /
  测试配置 / 连接串时的规范速查点 (#185→#186→#241 同根因三次复发的知识层加固)。

  回答: "内网服务连接该用 consul 名还是 IP"、"数据库怎么连"、"DATABASE_URL 怎么写"、
  "REDIS_URL 怎么写"、"连接串该用 IP 还是 consul"、"连 postgres/redis/内网服务的地址"、
  "host volume 该注册几个节点/规范"、"stateful 服务模板规范"、"有状态服务该怎么配"、
  "DB 密码该存哪"、"应用 secret 该存哪"、"连接串密码能不能硬编码进 HCL"。

  使用场景: "Aether 集成规范速查"、"consul 名还是 IP"、"内网服务怎么连"、"数据库怎么连"、
  "DATABASE_URL 怎么写"、"REDIS_URL 怎么写"、"连接串用 IP 还是 consul"、"连 postgres/redis
  地址"、"host volume 该注册几个节点"、"volume 规范"、"stateful 服务模板规范"、"有状态服务
  该怎么配"、"DB 密码该存哪"、"应用 secret 该存哪"、"连接串密码能不能硬编码进 HCL"
disable-model-invocation: false
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion, Skill
---

# Aether 集成规范速查 (aether-conventions)

> **版本**: 0.1.0 | **优先级**: P2 | **事故根因**: #185→#186→#241 同根因三次复发 (消费方钉 IP)
> **形态**: investigation-first 四域路由 hub —— 先判落在哪域，再进对应段落。
> **宣称边界**: 本 skill 是降低复发概率的**知识层加固**，不是机械闭环；repo 外手写文件
> (如 `~/.turfsync/devdb.env`) 的拦截是 L4 hook 领域，本 skill 不覆盖 (#246 跟踪)。

## 0. 铁律速记 (先记这四条，逐字冻结)

1. **`<service>.service.consul` 永不钉 IP** —— 服务名跟着 Nomad alloc 走，reschedule 换
   节点消费方零感知；钉 IP = 静默 blast-radius trap，health check 可能还是绿的。
2. **host_volume 全 heavy 节点注册** —— 单节点注册 = 单节点 pin，reschedule 到别的 heavy
   就找不到卷 (#56)。
3. **已有数据的 volume 用 `--register-only`** —— `aether volume create` 对已有数据不安全
   (会当新建处理)；`--register-only` 只登记不新建。
4. **stateful 服务必带 `migrate` stanza** —— `max_parallel=1, health_check="checks",
   min_healthy_time="30s", healthy_deadline="5m"`，保护 postgres/redis 免于并发写入。

> 这四条对消费方即是运行时 SoT，本文件自包含 (读不到主仓其他文档也照样够用)。
> 维护者权威版另见 §关联 (maintainer-only)。

## 1. 先判域 (investigation-first)

| 你的问题像哪句 | 去哪 |
|---|---|
| 内网服务连接怎么写 / DATABASE_URL·REDIS_URL 怎么配 / postgres·redis 地址 | §2 DNS 域 |
| 该用哪个 forgejo token / docker push 401 / CF Access 403 | **不在本域** → 调用 `aether-forgejo-creds` |
| DB 密码/连接串密码/应用 secret 该存哪 | §3 凭据域 (应用/DB 子集) |
| host volume 该注册几个节点 / volume 规范 | §4 Volume 域 |
| stateful 服务模板规范 / 有状态服务该怎么配 | §5 Stateful 域 |
| volume 怎么建 (执行动作) | **不在本域** → `aether-volume` |
| 接入 Aether / 生成部署文件 | **不在本域** → `aether-init` |
| 提交规范 / 版本发布流程等非集成规范问句 | **不在本域**，主仓 `CLAUDE.md` 另有说明 |

多域组合问题按顺序逐条过 (如「stateful postgres 用 consul 名还是 IP，volume 又怎么建」)：
先 §2 定连接方式，再 §4/§5 定存储与模板；各域独立判断，互不阻塞。

## 2. DNS 域 — 内网服务连接 (case-A-first)

**先问一句：你是 Nomad job 吗？**

- **是 (case A，绝大多数场景)** → 直接写 `<service>.service.consul`，**什么都不用配**：
  ```
  DATABASE_URL=postgres://<user>:<pass>@dev-db.service.consul:5432/app
  REDIS_URL=redis://cache.service.consul:6379
  ```
  Nomad 自动把容器 DNS 指向 infra dnsmasq，服务 reschedule 换节点自动解析到新 IP。

- **否，你在 LAN dev 容器/机器上临时手写配置 (case C)**：先自测
  ```bash
  dig +short @127.0.0.1 <name>.service.consul
  ```
  - 解析到内网 IP → 本机已装分流器，照常用 consul 名。
  - 失败/NXDOMAIN → 本机缺本地 dnsmasq 分流器。**决策桥** (拿不到完整配方时的自包含
    安全动作，三步走)：
    1. **绝不**把 IP 钉进任何可能进 HCL / Nomad job 的文件。
    2. 纯本地一次性 dev 文件确需临时用 IP，显式标注 `# dev-box-local-only`，且**绝不**
       进 HCL。
    3. 推荐装本地分流器 —— 完整可复制配方是维护者专属指针 (见 §关联)，不在本 skill
       verbatim 复制 (随集群演进腐化，且 canonical 明标该配方属 10cg.local 地界)。

- **集群外/漫游设备 (case D，subnet router) / 无法改 resolver 的黑盒设备 (case E，VIP)**：
  依赖 #244 尚未落地，本域只给出上面的原理和指针，不发运机制细节。

> 深度原理 + 更多自测命令：`references/dns-integration.md` (本 skill 内，自包含)。

## 3. 凭据域 — 窄委托 + 应用/DB secret 子集

本域**仅两类**触点，边界严格，不与 `aether-forgejo-creds` 竞争：

- **Forgejo/git/registry 凭据** (该用哪个 token / docker push 401 / CF Access 403 等)
  —— **不在此域**。**用 Skill 工具实际调用** `aether-forgejo-creds` (机制性指令，不是
  把它当参考文档读过去；不复述其内容)。
- **应用/DB 凭据** (连接串密码 / DB 密码 / API secret) —— **在此域**：
  - 存 Nomad Variables，`template { env = true }` 注入运行时 env (如
    `DATABASE_PASSWORD`)，供 app 从环境变量读取；**绝不**把明文密码硬编码进 HCL，
    也**绝不**把含明文密码的连接串提交进 repo。
  - `config.auth.${VAR}` 插值是 **docker 拉私有镜像的 registry auth** 专用字段
    (对应上面第一条 Forgejo/registry 凭据场景)，**不是**应用/DB 凭据的注入路径——
    DB 密码/连接串密码**不要**往 `config.auth` 里塞，那里塞的是 registry
    `username`/`password`，两者是完全不同的凭据。
  - 详见主仓 CLAUDE.md「凭据管理原则」+ maintainer-only 指针 (见 §关联)。

> 第三方 (Aliyun/ACR 等) 凭据同样不在 `aether-forgejo-creds` 范围内，按上面「应用/DB」
> 模式处理，不单独开域。

## 4. Volume 域 — 决策速记 (完整命令见 `aether-volume`)

- 生产/有状态服务：**每个 heavy 节点都要注册** host_volume，单节点注册是 #56
  blast-radius trap。
- 已有数据：`aether volume create --register-only` (对已有数据安全)；裸 `create` 对
  已有数据**不安全**。
- 完整命令/参数/幂等性检查见 `aether-volume` skill (执行层)；本域只回答「该不该 /
  怎么规范」，不重复其命令细节。

## 5. Stateful 域 — HCL 决策速记

- Constraint 用 `${node.class} = heavy_workload` (**不是** `heavy`；实际值以
  `curl $NOMAD_ADDR/v1/nodes` 为准)。
- **必带** `migrate` stanza (同 §0 第 4 条)。
- host_volume 全 heavy 注册 (同 §4)。
- 完整 HCL 骨架：`references/stateful-templates.md` (本 skill 内，自包含) + L1 模板
  `../aether-init/references/nomad-templates.md` (同 plugin，自包含)。

## 关联

> ⚠️ 下列 `https://forgejo.10cg.pub/...` 链接均为 **maintainer-only / 需主仓 + Cloudflare
> Access 权限 / 请勿 fetch**：该域名在 CF Access 网关之后，消费方 AI 若无 CF 凭据对其发
> WebFetch，会拿到 CF 登录页 HTML (200 OK 但内容是错的) —— 比"文件不存在"更隐蔽误导。
> 这些链接只为**人类维护者**核对用；消费方 AI 读不到、也不该尝试读。

- DNS 域完整原理/配方：`references/dns-integration.md` (本 skill 内，自包含)
- Stateful HCL 骨架：`references/stateful-templates.md` (本 skill 内，自包含)
- 凭据域 (Forgejo/git/registry)：调用 `aether-forgejo-creds` skill
- Volume 执行层：`aether-volume` skill
- 项目接入生成 (含 L1 模板 + L3 常驻 policy 段)：`aether-init` skill
- DNS canonical (含 §3.2 分流器完整配方 + §4 VIP，消费方无权限也不该照做)：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/cluster-dns-split-architecture.md
  (maintainer-only / 需主仓 + CF Access 权限 / 请勿 fetch)
- Stateful canonical (host_volume / migrate stanza 完整语义)：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/nfs-virtiofs-host-volumes.md
  (maintainer-only / 需主仓 + CF Access 权限 / 请勿 fetch)
- 应用/DB 凭据管理原则 canonical：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/nomad-variables-docker-auth.md
  (maintainer-only / 需主仓 + CF Access 权限 / 请勿 fetch)
- CLI 配置优先级 / env 导出第五岔路 (非 DNS/凭据/volume 域，环境变量 > 项目配置 > 全局
  配置 > 默认值)：
  https://forgejo.10cg.pub/10CG/Aether/src/branch/master/docs/guides/third-party-integration.md
  (maintainer-only / 需主仓 + CF Access 权限 / 请勿 fetch)
- 事故前史：#185 / #186 / #241 (同根因三次复发) · #244 (集群外服务发现，DNS case D/E 依赖)

---

**Skill 版本**: 0.1.0
**最后更新**: 2026-07-15
**维护者**: 10CG Infrastructure Team
