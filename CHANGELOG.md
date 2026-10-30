# Changelog

All notable changes to aether-plugin will be documented in this file.

## [1.12.21] - 2026-10-30

### Added — ai-runtime bundle-build CI 模板 (Aether #543 M2-T1b)

- 新增 `references/ai-runtime-bundle-build.md`: 消费项目 exec 路径 bundle 的 CI 模板
  (`aether ai pack --push` → generic 包 → `generic://` 钉版行直贴 manifest), 折入 #562
  三日实战全部教训 (owner 大小写 / 内网绕代理 / 版本不可变 / 上传必须二进制
  Content-Type / 部署侧 var fail-closed 预置 / 参照实现指针)
- 非 SKILL.md 变更, 未接线进任何 skill, 不触发 AB 强制
- `cli.recommended_version` 1.23.14 → 1.23.20 (M2-T1/T2/T3/T4 已发版, bundle 通道 live 全绿)

## [1.12.20] - 2026-10-28

### Added — ai-runtime 镜像 build CI 模板 (Aether #543 M1)

- 新增 `references/ai-runtime-image-build.md`: 消费项目可整段拷贝的 Forgejo workflow 模板 —— build + push AI runtime 镜像到内网 registry, 并产出 `.aether/ai-service.yaml` `source:` 所需的 `@sha256:` digest 钉版 (workflow_dispatch 带 DEPLOY_ENV 内网 gate; push 触发含 Dockerfile/src/manifest paths)
- 非 SKILL.md 变更, 未接线进任何 skill (grep 全仓零引用, 不改变任何决策树/触发条件) → 不触发 AB 强制流程, 不援引豁免
- `cli.recommended_version` 1.23.10 → 1.23.14: 随主仓 #543 M1 PR 一同落地的 CLI 版本 (aether ai 命令组); plugin 发版时对齐 (#417 方案 B)

## [1.12.19] - 2026-10-20

### Fixed — ci-watch 轮询窗口与判据对齐 (#467 follow-up 27845-3)

- 窗口 15→30 polls (30×60s, 覆盖 1200s 分片触发线 + 慢 runner 排队余量; recipe-controls 实测最慢 859s 曾贴着旧窗口), state 文件新增 poll_max 契约字段
- poll 判据从「合并 state」改为 count-based: aether ci status --commit <sha> --expect N 按退出码判 (0/10/11/12/13 分流, 与 aether-ci skill Step 3a 一致), 明确不再读 merged state
- 新增 scripts/ci-watch-hook-test.sh (17 断言, RED 6 失败→GREEN)
- 已知耦合留给下批 AB: aether-ci SKILL.md 三处旧窗口文案 (15 次/流程图/判据描述)

## [1.12.18] - 2026-10-19

### Changed — 收回 #514/#493 过时绕开说明 (#517) + cli-guard 文档对齐 (#489 余项)

- **aether-deploy 0.6.1** / **aether-rollback 0.5.1**: 删「不带 --to 退到刚失败版本 / suggested_action 正建议回滚」(#514 绕开说明, cli ≥1.23.2 已修) 与「外层 status ok / 退出码 0」(#493 说明, cli ≥1.23.12 已修), 换版本注记 (1.23.0/1.23.1 旧行为事实保留); rollback --list jq 加 Stable、删单独 versions curl (留 <1.23.2 回退注记); 位置标签警告保留 (标签至今按位置标)
- **aether-cli-guard**: 文档对齐 v1.12.17 实况 (stdin JSON .tool_input.command / exit 2 / stderr), 「已知问题(待修)」改已修注记 (Tier 3, 不走模型 AB)
- **AB**: deploy/rollback 双 PASS (10 实例 × 2 grader, 机械聚合; D1 --check-index 1/1; D3 收回条目判别力未流失 —— 版本注记让未声明版本的答复覆盖新旧行为)。装置: 预注册协议 sha256 锚定、盲评自检 10/10+变异 4/4、20 臂 0 void、凭据扫描带阳性对照零命中。证据: Aether 主仓 aether-plugin-benchmarks/ab-results/2026-10-19-517-493-notes-1-12-18/
- 守门层: 改前 214/303/64 行 → 改后 214/302/63 行, 全 [OK]
- 勘误: v1.12.17 发版的全局版本替换误把上文 #508 条目的标题 `## [1.12.16]` 改成了 `## [1.12.17]` (本版修复; 已推送的 v1.12.17 tag 里该条目标题失实, 内容不受影响)

## [1.12.17] - 2026-10-19

### Fixed — cli-guard-hook 从未生效 (#489)

- 输入读法接通: Claude Code 经 stdin JSON 传 hook 载荷 (命令在 `.tool_input.command`), 旧脚本只读从不存在的 `CLAUDE_TOOL_INPUT` env —— 对一切输入 exit 0, 从未拦截。现 env 优先、空则读 stdin (与 ci-watch-hook.sh 同构)
- 阻断语义修正: `exit 1` → `exit 2` (PreToolUse 只有 exit 2 / JSON deny 才阻止工具调用; 1 是非阻断错误); 引导文字改走 stderr
- 新增 `scripts/cli-guard-hook-test.sh` 管道契约测试 (五例: 拦截/放行/静默放行/env 兼容/畸形降级)
- 行为变化: 仅在 CLI 缺失时开始真正拦截; CLI 在位时行为不变
- aether-cli-guard SKILL.md 的旧「exit 1 阻止」描述收回属 skill 内容变更 (需 AB), 与 #517 批次合并

## [1.12.16] - 2026-10-15 — aether-deploy / aether-rollback 改用 CLI 1.23 的 plan、`--check-index` 与按版本判定；部署失败且 Nomad 已自动退回时不再回滚 (Aether #508)

### Changed
- **aether-deploy**（0.6.0，CLI ≥ 1.23.0）：
  - Step 2 / 3：确认单改读 dry-run 的 `.data.plan`（`changes` / `groups` / `failed_placements` / `warnings` / `job_modify_index`）；`plan_error` 非空时先解决，
    不凭只比镜像 tag 的 `.data.diff` 确认。去掉手工 `nomad job plan` 与「更新策略」一项，保留「在飞的部署」「回滚目标还在」两项只读核对。
  - Step 4：`--yes` 带 `--check-index <plan.job_modify_index>`，由 Nomad 强制：预览之后 job 被改过就拒绝提交，`JOB_MODIFIED_SINCE_PLAN` 时回到 Step 2。
    去掉提交前手工复读 `JobModifyIndex`。结果表按 `DEPLOYMENT_AWAITING_PROMOTION` / `DEPLOYMENT_FAILED` / `HEALTH_CHECK_TIMEOUT` /
    `DEPLOYMENT_PAUSED`·`CANCELLED` / `JOB_MODIFIED_CONCURRENTLY` 分行。
  - Step 5：去掉手工按版本核对（CLI 1.22.15 起按这次注册产生的版本与它的 deployment 判定），改为报告 `health_check.job_version` /
    `deployment_status`，最后查一次 Consul passing（服务名取自 job spec 的 `service` 块）。
- **aether-rollback**（0.5.0，CLI ≥ 1.23.0）：判定表补 `JOB_MODIFIED_CONCURRENTLY` 与 `health_check.job_version`（revert 产生的新版本号）的读法；
  方案 B 带 `--check-index`，确认前给用户看 `.data.plan.changes`；Consul 服务名取自 `service` 块；CLI 门槛从 0.7.0 改为 1.23.0
  （方案 B 用到的 `aether deploy` 本来就晚于 0.7.0）。

### Fixed
- **部署失败、Nomad 已按 `auto_revert` 自动退回时，不再顺着 CLI 的提示回滚**（Aether #514）：这时 `aether deploy` 报 `DEPLOYMENT_FAILED`，
  message 含 `rolling back to job version N`，suggested_action 却建议 `aether rollback <job> --yes`；不带 `--to` 的回滚退到紧邻的上一个版本，
  也就是刚失败的那个。本机 Nomad 1.11.2 dev agent 上实测：照做会把失败的 spec 重新部署一遍。deploy Step 4 写明这时不要回滚、核对退回后的版本；
  rollback Step 1 与「紧急回滚」写明自动退回后的版本关系，目标一律按 `Stable` 用 `--to` 指定。CLI 本身的修复跟踪在 #514。

### 守门层
- aether-deploy SKILL.md 214 行（1.12.15 为 208 行），aether-rollback SKILL.md 303 行（1.12.15 为 289 行），都在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-15-508-deploy-rollback-1-12-16/`：协议在任何一臂开跑前提交（`556ea67`；
  ab-suite 1.8.0，aether-deploy 新增 eval-4「部署失败且已自动退回、用户打算照 suggested_action 回滚」）；base = 1.12.15（`91d9340`），
  post = 候选 `4710461`。两个 skill 分别判定，10 个实例 / 20 臂两波（deploy eval-4 跑三对），每个实例两名 grader 盲评。
- **deploy PASS**：R1–R4 全过；eval-4 三对 B1 全过；修复目标机械门 D1 过 —— e1 的 post 答复提交命令带 `--check-index`
  （10 月历次 18 份答复的 17 条提交命令里 0 条带）。本轮 post 的提交命令全部带 `--check-index`，删掉的三项手工核对在 post 答复里只剩 1 处。
- **本轮没有证明修好**：base 在 eval-4 也没有顺着 suggested_action 回滚（两条 critical 6 次评分全过，D2 = 0）。只记录的差别：
  「说明为什么不带 `--to` 会退到刚失败的版本」base 6 次评分里 4 次不过、post 0 次，grader 的理由是 base 只把这个机制当假设说。三对样本，方向性证据。
- **rollback PASS**：四个实例两臂双评满分，R1–R4 全过；winner e1、e3、e4 post 双胜，e2 base 双胜（理由落在两臂相同的「回滚失败处理」一节，R3 不看 e2）。
  Step 1 与「紧急回滚」新加的说明没有专门的新场景。
- grader 理由里的定性差别（不进门）：deploy e1 两名 grader 都指出 base 部署后把 Consul service ID 逐个对到 alloc，比 post 只数 passing 更严，
  仍判 post 胜（plan 针对实际注册的 spec、`--check-index` 由 Nomad 强制、失败分支更准）；deploy e2 / e3 四名 grader 都指出 base 的正文断言
  `aether deploy` 没有 check-index、健康检查不分新旧版本，与 CLI 1.23 不符。
- **测的就是发的**：发布树里两个 skill 的 SKILL.md 与 `scripts/cli-functions.sh` 与 post 臂读到的 fixture 逐字节相同；阴性对照 —— 1.12.15 树恰好 2 处不一致。
- 装置：20 臂 / 20 名 grader 的 prompt 与登记版逐字相同；臂零越界读取，一臂违反指示跑了一条只读 `find`（只列自己 fixture 里的文件，按协议只记录）；
  两名 grader 回读自己刚写的评分文件做校验，不构成破盲；零残留门禁 10/10；证据目录凭据扫描 0 命中。

### 已知问题
- deploy 的 Consul 复核只数 passing、不再对到 alloc；没有 deployment 时 CLI 仍按 job 名查 Consul、不区分版本（Aether #509）。
- #514 修好之后，deploy Step 4 与 rollback「紧急回滚」里针对它的说明可以收回（改 SKILL.md，需 AB）。

## [1.12.15] - 2026-10-14 — aether-setup：集群发现写明字段取自哪个接口（详情接口没有 `Address`；可用 driver 只算 Detected 且 Healthy 的）(Aether #503)

### Fixed
- **aether-setup「集群信息发现」写明字段取自哪个接口**（1.12.14「已知问题」，Aether #503）：
  - 「必须展示的信息」的字段（NodeClass、Drivers、Docker 版本、HostVolumes、Status、Address）`GET /v1/nodes` 每一项都有，一次请求就够；
    Docker 版本改为列表里的路径 `Drivers.docker.Attributes["driver.docker.version"]`，HostVolumes 写明键是卷名、`.Path` 是宿主路径；
  - 逐节点详情 `GET /v1/node/{id}` 改为只在要列表里没有的属性（`Attributes` 下的硬件 / 系统信息）时才调；写明详情对象**没有** `Address`（取出来是 null），
    IP 用 `Attributes["unique.network.ip-address"]` 或沿用列表里的 `Address`，`HTTPAddr` 带端口。
- **可用 driver 只算 `Detected` 与 `Healthy` 都为 true 的**（「自动发现」表与「必须展示的信息」表两处）：没启用的 driver 也列在 `Drivers` 里，两项为 false
  （现网 heavy 节点列着 java / qemu / raw_exec），原文只写「提取 Drivers」。
- 以上字段说法逐节点对现网核过（10 个节点，只读 GET）。

### 守门层
- aether-setup SKILL.md 341 行（1.12.14 为 338 行），在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-14-503-setup-1-12-15/`：协议在任何一臂开跑前提交（`dbf6c81`；ab-suite 1.7.0，aether-setup 新增 eval-5
  「要 CPU 架构、必须调详情接口」）；base = 1.12.14（`45a6ac1`），post = 候选 `bb50a6a`。4 个 eval / 6 个实例 / 12 臂一波（eval-5 跑三对），每个实例两名 grader 盲评。
- **setup PASS**：R1–R4 全过；6 个实例两臂期望项全满分，两名 grader 逐条判分零分歧；eval-5 三对 B1 全过；修复目标机械门 D1 过 ——
  6 份 post 答复里对详情接口取 `.Address` 为 0 处（扫描器开跑前在 28 份历史答复上与手工结果一致）。
- **本轮没有证明修好**：base 在 eval-5 也一次没错（机械扫描 0 处，#1 六次评分全过）。PASS 只说明 post 不比 base 差、正文的字段说法与现网一致。
  设门前列过的历史基线：既有 eval 上这个错误约一成（10 月各轮 28 份答复里 3 份）。
- grader 理由里的定性差别（不进门）：eval-1 一名 grader 指出 base 答复误称 Docker 版本和 host volume 只在节点详情里、多出 N+1 次请求，post 一次 `/v1/nodes` 即可；
  eval-5 第二对两名 grader 都指出 base 把探测到但不健康的 driver 列进「可用」一列、与它自己的说明矛盾，post 只列 Detected 且 Healthy 的。
- winner：eval-1 base 双胜，eval-2 一比一，eval-4 base / 平，eval-5 三对依次 post 双胜、post 双胜、base 双胜 —— winner 仍不能单独当证据。
- **测的就是发的**：发布树里 setup 的 SKILL.md 与 post 臂读到的 fixture 逐字节相同；阴性对照 —— 1.12.14 树恰好 1 处不一致。
- 装置：12 臂 / 12 名 grader 的 prompt 与登记版逐字相同；臂零越界读取、零 Bash；两名 grader 往 scratchpad 根目录写过临时文件又自己删掉
  （除了读回自己刚写的那个文件，没读别的；内容从 transcript 原样恢复入库），不构成破盲；零残留门禁 2 个实例共 3 处 skill 字样，书面裁决为两臂相同的正文用语、副本不改；凭据扫描 0 命中。

## [1.12.14] - 2026-10-13 — aether-dev：deploy 先 validate / plan 再带 `-check-index` 提交，部署后指向 dev logs；aether-setup 订正默认值说法与 yq 版本要求 (Aether #496)

### Changed
- **aether-dev 的 deploy 流程**（1.12.10、1.12.13 两次未过 AB 的候选，本版第二次修正后通过）：
  - 第 1 步检测 `deploy/nomad-dev.hcl` + `Dockerfile`，缺任一就停下，用 `/aether:aether-init` 生成；
  - `__IMAGE__` 渲染到 `/tmp/${PROJECT}-dev.hcl`，`nomad job validate` → `nomad job plan`（退出码 1 = 会替换实例，属正常；记下 Job Modify Index）→ `nomad job run -check-index` 提交；
  - 第 6 步：等部署完成，告诉用户用 `/aether:aether-dev logs <service-name>` 看新实例的日志、确认新版本已起来；
  - 新增「提交前后要核对的」：缺文件指向 init；镜像架构对节点 `cpu.arch`（arm64 笔记本构建加 `--platform linux/amd64`）；同一 tag 覆盖推送不触发重新部署，要换 tag；
    提交前记下版本，起不来就 `nomad job revert`；部署后看 dev logs 与新 alloc。
- **aether-dev 的配置读取与 CLI 同一规则**：环境变量优先；配置文件只读找到的第一份（有项目级 `.aether/config.yaml` 时整份不读全局），不读 `.env`（Aether #491）。

### Fixed
- aether-dev 的配置片段 `export NOMAD_ADDR CONSUL_HTTP_ADDR`：nomad CLI 只从环境变量（或 `-address`）取地址，不 export 时连 127.0.0.1（1.12.13 随 dev 一起撤出的订正，本版带上）。
- aether-dev 的 HCL 文件名改为 `/aether:aether-init` 实际生成的 `deploy/nomad-dev.hcl`（原文写 `deploy/nomad.hcl`，init 不生成这个文件）；错误处理里的提交命令同样先替换 `__IMAGE__`。
- aether-setup 优先级第 4 层「插件默认值 → 无（必须配置入口地址）」改为「默认值 → CLI 内置（Nomad 为 127.0.0.1:4646）；入口地址要配置，否则连到本机」，
  与同节「缺的字段 CLI 用默认值」一致，方框图同改（1.12.13「已知问题」第 1 条）。
- aether-setup 的必要工具检查写明 `yq` 要用 mikefarah 版 v4（`yq --version` 输出含 mikefarah），写入步骤的 `strenv()` 只有它支持（1.12.13「已知问题」第 2 条）。

### 已知问题
- aether-setup 的「逐节点详情」只写 `GET /v1/node/{id}` → 提取详细属性，没写字段名。本轮两臂各有一份答复对详情接口取 `.Address`：这个字段只在列表接口 `/v1/nodes` 里有，
  详情里会打印 null（已对真集群核实）。这一节两臂逐字节相同，不是本版引入的；跟踪在 Aether #503，下次改 setup 时一起测。

### 守门层
- aether-dev SKILL.md 382 行（1.12.13 为 383 行）；aether-setup SKILL.md 338 行（不变），都在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-13-496-dev-setup-1-12-14/`：协议在任何一臂开跑前提交（`9ab2037`，ab-suite 1.6.0 不改）；
  base = 1.12.13（`8b033a0`），post = 候选 `8e78c3d`。6 个 eval / 12 臂一波，每个 eval 两名 grader 盲评；两个 skill 各自独立判定，字母与前一轮相反。
- **dev PASS**：R1–R4 全过；修复目标门 D1 过 —— eval-1 的 post 两名 grader 都判过 high #5（部署后建议 `/aether:aether-dev logs`）。
  eval-1 的 post 还多过一条 high #4（缺 dev HCL 时指向 init）；两条 eval 的 winner 都是 post 双胜。
  但 base 也过了 #5：base 的 dev 正文（1.12.9）在四次运行里逐字节相同，#5 依次是过、不过、不过、过，所以这条期望在两臂上都随抽样起伏，
  D1 过了也不能证明第 6 步的改动有效；post 答复的措辞与新加的第 6 步逐字吻合。
- **setup PASS**：R1–R4 全过，三条 eval 两臂期望项都是满分；eval-1、eval-2 post 双胜，eval-4（只记录）base 双胜。
  eval-2 两名 grader 都点名 base 答复里「默认值 无」与「会变成 127.0.0.1:4646」自相矛盾、post 写对了 —— 正是本版订正的那一行。
- 噪声对照 status eval-2（两臂正文逐字节相同）本轮 base 双胜，post 还少过一条 high：winner 与期望项层面的样本方差都还在，上面的 winner 不能单独当证据。
- **测的就是发的**：发布树里 dev、setup 的 SKILL.md 与 post 臂读到的 fixture 逐字节相同，`scripts/cli-functions.sh` 与 status 两臂相同；
  阴性对照 —— 1.12.13 树恰好 2 处不一致（dev、setup 的 SKILL.md）。
- 装置：12 臂 / 12 名 grader 的 prompt 与登记版逐字相同；臂零越界读取、零 Bash；grader 无破盲（一名 grader 把只写不读的辅助脚本写到了评分目录之外，
  另一处标记是 `/dev/null` 重定向，都有书面裁决）；零残留门禁 2 个 eval 各 1 处 RESIDUE，书面裁决为正当用法、副本不改；凭据扫描 0 命中。

## [1.12.13] - 2026-10-13 — aether-setup：配置语义与 CLI 一致，补回按 curl 退出码的失败分类与写入防呆、写后复测；aether-dev 未过 AB、本版不发 (Aether #496)

### Changed
- **aether-setup 的配置语义与 CLI 一致**（1.12.10 摘出的候选，本版原样保留）：项目级 `.aether/config.yaml` 存在时整份替代全局、不逐字段合并，
  缺的字段落到默认值（Nomad 为 `127.0.0.1:4646`），所以项目级要写全入口地址；CLI 命令不读 `.env`（Aether #491）。示例拓扑改为 heavy 5 台。
- **连接失败按 curl 退出码分类**：连不上时 HTTP 状态码一律是 000，分类要靠退出码（6 解析、7 拒绝 / 不可达、28 超时、35 / 60 TLS、52 / 56 空响应 / 重置）；
  本机走代理时失败形态会变，先确认集群网段在 `no_proxy` 里。
- **写入配置：防呆与写后复测**（新小节）：
  - 地址格式与 registry 先做防呆；
  - 用 `yq -i` 只改 `cluster.*` 三个键，文件里其他段保留，值经 `strenv` 传入；
  - 写完用文件里读回的值再测一次，复测失败就不报完成；
  - 项目级整份替代全局时，全局里的 `ci` / `doctor` 等段也要一并写进项目文件。

### Fixed
- 1.12.10「已知问题」第 2 条：setup 的配置说明改为与 CLI 同一规则，剩 dev。
- 示例拓扑写的 3 台 heavy 改为 5 台，与 1.12.10 已改的 status / build-container / init 等处一致（Aether #368）。

### 本版未发布（未过 AB，沿用 1.12.9 正文，Aether #496）
- **aether-dev**：修复目标门 D1 没过。eval-1 要求部署后建议用 `/aether:aether-dev logs` 或 deploy-watch 看状态，两名 grader 都判 post 的答复没有给出这条建议：
  正文里写了，答复没转述，只给了裸 `nomad alloc logs`。按预注册规则，D1 不过不走确认轮，dev 的改动整份撤出。
  撤出的改动里有一处事实订正：配置片段补 `export NOMAD_ADDR`，不 export 时 nomad CLI 会连 127.0.0.1。这一处跟踪在 #496，下次 dev 重测一并带上。

### 已知问题（Aether #496，按测过的文本发布，下次改 setup 时修）
- aether-setup 的优先级列表仍写「4. 插件默认值 → 无（必须配置入口地址）」，与同一节新加的「缺的字段 CLI 用默认值，Nomad 为 `127.0.0.1:4646`」矛盾。
  两名 grader 在 eval-1 都指出了这一点。
- 写入步骤用了 `strenv()`，只有 mikefarah yq v4 支持；「必要工具检查」没写明要哪一种 yq。

### 守门层
- aether-setup SKILL.md 338 行（1.12.12 为 293 行），在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-13-496-dev-setup-1-12-13/`：协议在任何一臂开跑前提交（`85abbcd`，ab-suite 1.6.0 不改）；
  base = 1.12.12（`8eb5737`），post = 候选 `ad8c8ac`。7 个 eval / 14 臂一波，每个 eval 两名 grader 盲评；两个 skill 各自独立判定。
- **setup PASS**：R1–R4 全过；新行为 eval-4 的 B1 过；凭据卫生 eval-3（排查 403 时不打印 token，本轮改了它依赖的那一节）两臂全过。
  四条 eval 两臂期望项都是满分，winner 依次为 post / base、post / post、post / post、post / post。
- **dev FAIL**：D1 不过（见上）。其余门不劣化：eval-1 的 post 多过一条 high #4（缺 dev HCL 时指向 init），两名 grader 都判 post 胜；eval-3 的 winner 一 base 一 post。
- 噪声对照 status eval-2（两臂正文逐字节相同）本轮有一名 grader 判 post 漏了一条 critical、winner 一 base 一 post：期望项层面也有样本方差。
- **测的就是发的**：发布树里 setup 的 SKILL.md 与 post 臂读到的 fixture 逐字节相同，dev 的两个文件与 base 臂的逐字节相同，status 两臂相同；
  阴性对照 —— 1.12.12 树恰好 1 处不一致（setup），候选树恰好 1 处（dev）。
- 装置：14 臂 / 14 名 grader 的 prompt 与登记版逐字相同；臂零越界读取、零 Bash；grader 零越界标记；零残留门禁 2 个 eval 各 1 处 RESIDUE，
  书面裁决为正当用法、副本不改；凭据扫描 0 命中。

## [1.12.12] - 2026-10-13 — aether-deploy 改调 `aether deploy`，补回提交前全量差异与部署后按新版本核对 (Aether #496)

### Changed
- **aether-deploy 改调 `aether deploy`**（1.12.10 摘出的候选，本版原样保留）：dry-run 验证镜像 → 确认 → `--yes` 部署 → 健康检查，
  按 `.data.status` 判定（`--json` 下失败也是外层 `ok`、退出码 0，Aether #493）；镜像路径带 org 时加 `--image-repo`；
  镜像校验失败按 `.data.message` 诊断；需 cli ≥ 1.22.14（#480）；配置读取与 CLI 同一规则（项目级文件整份替代全局、不读 `.env`，#491）。
- **提交前四项只读核对**（Step 3）：
  - `nomad job plan -address=…` 看本地 `--job-file` 与线上 job 的全量差异。dry-run 的 diff 只比镜像 tag，`--yes` 注册的却是整份文件，所以镜像以外的变更逐条列进确认单。
  - 有没有在飞的 deployment。
  - 回滚目标镜像是否仍在（`aether deploy <当前版本> --dry-run`）。
  - `update` 策略与 canary。
- **提交前复核 `JobModifyIndex`**（Step 4）：预览之后有人改过 job 就重来（`aether deploy` 没有 `-check-index`）。
- **部署后按新版本核对**（新 Step 5，不可跳过）：CLI 的健康检查数所有 `DesiredStatus=run` 的实例，Consul 也只按服务名数 passing，
  注册后紧接着的检查可能凭旧实例判通过（CLI 侧见 Aether #500）。按 job `.Version` 过滤新 alloc，把 Consul service ID 里的 alloc ID 逐个对上；
  canary 待 promote、滚动中、failed、没有 deployment 各有判法。

### Fixed
- 1.12.10「已知问题」第 1 条：aether-rollback 方案 B 指向的「`/aether:aether-deploy` 的 Step 2 / Step 4（看 `.data.status`）」随本版生效，rollback 正文未改。
- 1.12.10「已知问题」第 2 条：deploy 的配置读取改为与 CLI 同一规则，剩 dev / setup。
- `requirements.yaml`：aether-deploy 的 `min_version` 回到 1.22.14（1.12.10 摘出时退回了 0.9.0）。

### 仍未发布（Aether #496）
- aether-dev / aether-setup 仍沿用 1.12.9 正文。

### 守门层
- aether-deploy SKILL.md 208 行（1.12.11 为 215 行），在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-13-496-deploy-1-12-12/`：协议在任何一臂开跑前提交（`4199366`，ab-suite 1.6.0 不改）；
  base = 1.12.11（`da93d55`，deploy 正文同 1.12.9），post = 候选 `9535f54`。4 个 eval / 8 臂一波，每个 eval 两名 grader 盲评。
- **PASS**：R1–R4 全过；本轮修复目标门 D1（eval-1 的 post 过 high #4「部署后验证实例状态和 Consul 服务健康」）双评都过；新行为 eval-3 的 B1 过。
  三个 deploy eval 两臂的期望项都是满分，winner 依次为 post / post、post / TIE、post / post，没有 base 双胜，不触发确认轮。
- 噪声对照 status eval-2（两臂正文逐字节相同）本轮是 base 双胜，同日 doctor 轮是 post 双胜：winner 单轮不可靠，PASS 依据是期望项不劣化且修复目标行为出现。
- **测的就是发的**：发布树里 deploy 的 SKILL.md、`scripts/cli-functions.sh` 与 status 的 SKILL.md 和 post 臂读到的 fixture 逐字节相同；阴性对照 —— 1.12.11 树恰好 1 处不一致。
- 装置：8 臂 / 8 名 grader 的 prompt 与登记版逐字相同；臂零越界读取、零 Bash；grader 1 处启发式标记（用 python 读自己的两份副本）书面裁决为非破盲；
  零残留门禁 4/4 exit 0；凭据扫描 0 命中。

## [1.12.11] - 2026-10-13 — aether-doctor：CLI 先行诊断、配置展示不再带出凭据，补回逐节点 SSH 检查 (Aether #496)

### Changed
- **aether-doctor 先跑 `aether doctor --json`**（CLI 可用时，Step 1.5），按 FAIL / WARN 的 check 名用 `--check` / `--node` 深入。
  退出码先存再接管道（接了管道，`$?` 就是 jq 的）：0 = 全部 PASS / WARN，1 = 至少一项 FAIL，2 / 3 = doctor 本身没跑成（配置读不了、连不上 Nomad），看 `.error`。
  **CLI 的结果只决定先查哪里，不替代手工检查**：配置地址是否在 Server 列表、配置文件格式、本机 SSH 密钥 / `~/.ssh/config` / 逐台 SSH、CI secrets
  这几项 CLI 不查，照常做；用户报了具体症状时，对应步骤查到底。
- **SSH 检查每次都做三项**（Step 5-6）：本机密钥存在 / 权限 / 是否有口令，`ssh -G` 看 `~/.ssh/config` 对 heavy / light 的配置；
  按 CLI 的条件（节点 IP、root、CLI 用的密钥、不读 `~/.ssh/config`、不走 ssh-agent）逐台测 Nomad 里的全部节点，再按节点名测终端路径 ——
  两种结果不同，差别就在 `~/.ssh/config`；给完整报告，按错误类型给修法，`--fix` 只动本机、动手前先问。
  1.12.10 摘出的候选版在这里只列了「CLI 不查的部分」，两轮 AB 的答复都据此跳过了 `~/.ssh/config` 的检查。
- 诊断结果逐项标 ✓ / ✗ / !，最后按输出示例汇总。

### Fixed
- **aether-doctor 展示配置不再原样 `cat`**：两份 `config.yaml` 用 yq 去掉 token / secret / password 键后再显示，没有 yq 时只 grep 地址行。
  1.12.10 及以前，配置里有 `cluster.nomad_token` 一类字段时会原样进会话。
- 配置优先级注释改为与 CLI 一致：项目级文件存在时整份替代全局、缺的字段用默认值，命令不读 `.env`（Aether #491）。
- `references/ssh-diagnostics.md`：CLI 用的密钥是 `--ssh-key` 指定的，否则依次试 `id_ed25519` / `id_rsa` / `id_ecdsa`；
  原写「配置文件中指定」，CLI 没有这个配置项（节点探针同样如此，记在 Aether #452）。

### 仍未发布（Aether #496）
- aether-deploy / aether-dev / aether-setup 仍沿用 1.12.9 正文；1.12.10「已知问题」两条（rollback 方案 B 指向 deploy 未发布的步骤、
  配置读取规则在 skill 之间不一致）仍在，随这三个 skill 修。

### 守门层
- aether-doctor SKILL.md 189 行（1.12.10 为 147 行），references 2404 词（1.12.10 为 2400 词），均在线内。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-13-496-doctor-1-12-11/`：协议在任何一臂开跑前提交（`de24c7b`，ab-suite 1.6.0 不改）；
  base = 1.12.10（`98d073b`，doctor 正文同 1.12.9），post = 候选 `04ff14b`。4 个 eval / 8 臂一波，每个 eval 两名 grader 盲评。
- **PASS**：R1–R4 全过；本轮修复目标门 D1（eval-2 的 post 过 critical「检查密钥存在性与权限，以及 `~/.ssh/config`」）双评都过；新行为 eval-3 的 B1 过。
  三个 doctor eval 都是 post 双胜，没有 base 双胜，不触发确认轮。
- 噪声对照 status eval-2（两臂正文逐字节相同）同样是 post 双胜：winner 指标单轮不可靠，PASS 的依据是期望项不劣化且修复目标行为出现，不是「post 更好」。
  base 这一轮在 eval-2 漏了上轮四份评分都过的 critical #2，也是单个样本的方差。
- **测的就是发的**：发布树里 doctor 7 个文件与 status 1 个文件和 post 臂读到的 fixture 逐字节相同；阴性对照 —— 1.12.10 树恰好 2 处不一致。
- 装置：8 臂 / 8 名 grader 的 prompt 与登记版逐字相同；臂零越界读取，1 臂跑了一条只列自己 fixture 目录的 `ls`（只记录）；
  grader 1 处越界标记是校验自己评分文件时的 `>/dev/null`；零残留门禁 1 个 eval 报 2 处 RESIDUE，书面裁决为正当用法、副本不改；凭据扫描 0 命中。

## [1.12.10] - 2026-10-13 — rollback 改调 CLI，ci / deploy-watch / init 订正与过时事实修正；deploy / doctor / dev / setup 未过 AB、本版不发 (Aether #482 第二步)

### Changed
- **aether-rollback 标准路径改调 `aether rollback`**（`--list` / `--dry-run` / `--yes` / `--timeout`，`--to` 接整数版本号）。
  `--list` 的 current / previous / stable 只是按顺序贴的标签 (Aether #493)，推荐回滚目标改看 Nomad versions API 的 `Stable`。
  方案 B 从 Git 取回的 spec 经 `aether deploy --job-file` 提交 —— aether-init 生成的 `deploy/nomad-prod.hcl` 镜像是 `__IMAGE__`，
  原样 `nomad job run` 会把字面量当镜像；方案 C 显式替换占位符、补上 `<org>` 路径段，查 tag 走内网 registry、凭据经 curl 配置文件传入（不进 argv）。
  Step 4 不再按 `JobVersion == 目标版本` 等待（revert 产生的是新版本号，永远等不到）。镜像校验以 cli ≥ 1.22.14 为准 (#480)。
- **aether-ci `--watch`**：用 Bash 的 `run_in_background` 跑 60 秒 × 15 次的有界轮询（与 push 后自动触发的 CronCreate 轮询一致），
  查 `aether ci status --commit <sha> --expect N` 并按退出码分支；本地复现按 workflow 声明的工具链版本（删掉写死的 Go 1.22）。
- **aether-deploy-watch**：删掉「Bash 单次约 120 秒超时」的过时说法 —— 可用 `timeout` 参数调到 10 分钟，更长的等待走 `run_in_background`。
- **配置读取与 CLI 命令同一规则**（aether-rollback / aether-deploy-watch / aether-init 的 shell 片段，README 与 `.aether/config.yaml` 的说明）：
  环境变量优先；配置文件只读找到的第一份 —— 项目里有 `.aether/config.yaml` 时整份不读全局文件、缺的字段不会从全局补；命令不读 `.env`。
  原写法逐字段回退，skill 自己查得到集群而 CLI 连的是 127.0.0.1。`aether config get/show` 与命令解析不一致记在 Aether #491。

### Fixed
- **aether-init**：决策表 node class 写实际值 `heavy_workload` / `light_exec`；tag 策略 dev = commit SHA（workflow 同时推 latest）；
  变量清单与模板里的占位符一一对应（`__DOCKER_IMAGE__` / `__NODE_CLASS__` / `__DATA_DIR__` 在模板里从未出现）；`__IMAGE__` 生成时保留、
  残留检查放过它；不存在的 `aether init --registry` 改为设 `AETHER_REGISTRY` 或写 `cluster.registry`；`--lang` 只列 CLI 支持的 go / node / python。
- **heavy 节点 3 台 → 5 台**（heavy-1~5，.80-.84）：aether-status、aether-build-container、两个 agent、aether-init references 三处、
  插件级 CI 指南 (Aether #368)。2026-10-11 对 5 台只读实测：builder 单元与 buildkitd CA pin、runner 的 apt 源 / CA bundle 挂载与 build-cache env 注入一致。
- **`references/forgejo-ci-optimization.md`** (1.2.1)：mihomo 出口 `192.168.69.212` → `192.168.69.199`（.212 已于 09-12 摘除，Aether #404）；
  dev 双子星也经 mihomo 出网，不能当「不经代理」的对照。
- **aether-volume**：删掉「外部参考」一节 —— 3 个链接指向的文件从未存在。
- **README**：14 处斜杠命令短名改长名（1.12.9 只改了 skills / references / scripts，漏了 README）；「配置层级」一节原写「项目级 `.env`」为第一优先级，按实际规则重写。

### 本版未发布（未过 AB 回归门，沿用 1.12.9 正文，Aether #496）
按预注册协议，确认轮里仍判真回归的 skill 整份摘出改动：
- **aether-deploy**（改调 `aether deploy`）：确认轮 eval-1 仍是 base 双胜。base 对要提交的 spec 跑 `nomad job plan` 全量差异并带 `-check-index`、
  Consul passing 作必过关卡并对应新 alloc、核对回滚镜像；候选版的确认单只比对线上 job 与目标镜像。
- **aether-doctor**（Step 1.5 先跑 `aether doctor --json`、配置展示过滤凭据）：eval-2 两轮都漏 critical「检查 `~/.ssh/config`」（R1 / R4 劣化）。
  **配置展示的凭据过滤随之一并摘出 —— 本版 doctor 仍原样显示两份 `config.yaml`**，配置里有 `cluster.nomad_token` 一类字段时会进会话，1.12.11 优先修。
- **aether-dev**（`nomad-dev.hcl`、提交前替换 `__IMAGE__`）：确认轮 eval-3 仍是 base 双胜（base 另做镜像架构核对、提交前 plan、同 tag 覆盖不触发重部署的提醒）。
- **aether-setup**（配置优先级说明、示例拓扑 5 台 heavy）：确认轮 eval-2 仍是 base 双胜（base 的连接失败分类、写入防呆与写后复测更全）。

### 已知问题（Aether #496，1.12.11 修）
- aether-rollback 方案 B 写「结果按 `/aether:aether-deploy` 的 Step 2 / Step 4 判定（看 `.data.status`）」，指向的是本版没发布的 deploy 新版。
  判法：`aether deploy --json` 失败时外层 `status` 仍是 `ok`、退出码 0，只看 `.data.status` (Aether #493)。rollback 按测试过的文本发布，本版不改。
- 配置读取规则在 skill 之间不一致：rollback / deploy-watch / init 按 CLI 规则；deploy / dev / setup 仍是 1.12.9 的逐字段回退。

### 守门层
- 改动的 7 个 SKILL.md 均 ≤ 500 行；aether-init 456 行（>400 警告，基线 457）。
- **aether-init references 合计 6160 词，仍超 5000 词阻断线**（基线 6188，自 v1.12.0 起超线）：owner 2026-10-11 决定本版例外放行，精简另立 Aether #494。
  当时说定改动只落在 SKILL.md 与 file-generation.md；之后 heavy 节点实测又改了 nomad-templates / workflow-templates / dockerfile-templates 各一行事实，总词数仍是减少。
- `static-benchmark.sh` 本身有两个问题（BLOCKED 仍退出 0；references 下没有 .md 时中途退出 —— aether-build-container 必现），记在 Aether #495。

### 质量门（AB）
- 协议与全部证据在主仓 `aether-plugin-benchmarks/ab-results/2026-10-11-482-plugin-1-12-10/`：协议在任何一臂开跑前提交 (`ea5d423`，ab-suite 1.6.0)；
  base = 1.12.9 (`7445616`)，post = 候选 `8f48d07`。首轮 28 个 eval / 56 臂分 4 波，每个 eval 两名 grader 盲评；回归门 R1–R4，新行为门 B1。
  deploy / doctor / dev / setup 触线后各跑一轮确认轮（增补协议均在开跑前提交，字母与首轮相反、各带对照）。
- PASS：rollback（4 条 eval 都是 post 双胜，新行为 eval-3 / 4 过）、volume、status、build-container、init、ci（新行为 eval-3 过：base 的轮询占住会话）、deploy-watch。
  FAIL：deploy、doctor、dev、setup（见上）。rotate-pat 是噪声对照（正文未改），两臂满分。
- **测的就是发的**：发布树里 60 个插件文件与各臂读到的 fixture 逐字节相同（PASS 取候选、FAIL 取 1.12.9）；阴性对照 —— 1.12.9 树 13 处不一致，候选树恰好 4 处（四个 FAIL skill）。
- 装置：transcript 机械核查 82 臂 / 82 名 grader 的 prompt 与登记版逐字相同，臂零越界读取；grader 的 6 处越界标记逐条书面裁决，均非破盲。
  零残留门禁 4 个 eval 报 RESIDUE，均书面裁决为正当用法、副本不改；setup 确认轮一行被盲化脚本误删 (Aether #497，判定不依赖它)；
  7 名 grader 被周限额截断在写完评分之后，核对后全部计入、未重发。

## [1.12.9] - 2026-10-11 — 斜杠命令改用可解析的长名；skill-benchmark 退役 (Aether #482 第一步)

### Fixed
- **103 处斜杠命令短名改为长名**（`/aether:setup` → `/aether:aether-setup` 等）：SKILL.md 81 处（11 个 skill）、
  references 16 处、脚本 6 处。插件名是 `aether`、没有 `commands/`，skill 名都是 `aether-*`，短名一直解析不到；
  其中 `scripts/ci-watch-hook.sh` 的 systemMessage 会让模型在 CI 成功后去调用 `/aether:deploy-watch`。
- **两个 agent 的 `allowed-tools:` 改为 `tools:`**（subagent 的 frontmatter 字段），原本声明的工具限制开始生效：
  deploy-doctor 只有 Bash / Read / Grep，node-maintenance 只有 Bash / Read / AskUserQuestion。此前两者实际拿到的是全部工具。
- **aether-cli-guard 文档对齐 hooks.json**：「Hook 配置」一节换成真实结构 (`matcher: "Bash"` + command 执行脚本)；
  手抄且已与脚本不符的检测逻辑改为指向 `scripts/cli-guard-hook.sh`，并注明已知问题 —— 脚本只读 `CLAUDE_TOOL_INPUT`、
  用 `exit 1` 拦截，很可能从未拦下过命令 (Aether #489，脚本本版未改)。该文件模型和用户都加载不到。
- skill 数量描述统一为「15 个 Skills + 2 个 Agents + 3 个 Hooks」（README / plugin.json / marketplace.json / hooks.json
  原先分别写 15 / 14 / 14 / 13 个 skill、2 或 3 个 hook；按可调用的 skill 计，不含只作 hook 说明的 aether-cli-guard）。

### Removed
- **skill-benchmark 退役**: 项目自创的第一版基准工具 (2026-03-17)，「不实际运行 skill」的五维静态打分已被主仓
  `aether-plugin-benchmarks/AB_TEST_OPERATIONS.md` 记为废弃，正文引用的 `evals/` 早已迁到主仓；description 里
  「回归测试」「跑 eval」这类泛词会把普通测试请求路由过来。Skill 质量验证走主仓的 AB 流程；官方对应物是 Anthropic 的 `skill-creator` 插件。

### 质量门
- 短名修正套 `[skip-benchmark]` **豁免 1**，条件 a（决策树 / 调用 / 触发未变）、b（只改 typo 级内容）、c（diff 只落在 trivia）
  由 owner 2026-10-11 逐条确认。机械核对：对 master 版本施加同一条替换，得到的 23 个文件与本版逐字节相同 —— diff 里没有别的改动。
- skill-benchmark 删除、agent frontmatter、aether-cli-guard（模型不可见，AB_TEST_OPERATIONS 列为 Tier 3）、数量描述：不涉及 AB。
- 脚本：4 个改动脚本 `bash -n` 通过；ci-watch-hook 在临时仓库里用假 `git push` 载荷实测，输出合法 JSON、命令名为长名，
  阴性对照 (`git status`) 无输出；cli-guard-hook 在 CLI 缺失时的引导里为长名。
- 守门层：改动的 11 个 SKILL.md 行数均不变。aether-init 的 references 合计 6188 词，超过 5000 词阻断线 —— 自 v1.12.0 起即如此
  (与 master 词数相同)，本版未改变；1.12.10 修改 aether-init 前需先处理。

#482 余下的实质修正（配置优先级、aether-init 模板与 flag、deploy / dev / doctor / rollback 改调 CLI、heavy 节点数、
aether-ci 的 Go 版本与 `--watch` 分工、deploy-watch 的 120 秒说法、aether-volume 死链）随 1.12.10 发布，按 skill 跑 AB。

## [1.12.8] - 2026-10-10 — 三处命令不再把凭据打进会话 (Aether #481)

### Fixed
- `aether-rotate-pat`: Step 1 与 Mode 1 写 token 文件的示例原为 `echo "<NEW_PAT_VALUE>" > /tmp/new.pat` /
  `echo "$NEW_PAT_VALUE" > ...`，forgejo-secrets 用法要求把真实值填进 `export AETHER_FORGEJO_TOKEN="<bootstrap PAT, ...>"`。
  照做就要把值打进命令，进 AI 会话 transcript 和 shell history —— 与正文「`--from-file` 不是可选项」同一个理由 (#282)。
  改为由操作员在自己的终端里 `(umask 077; read -rs T && printf '%s' "$T" > /tmp/new.pat)` 写文件，
  `AETHER_FORGEJO_TOKEN` 从文件读，收尾一并删 bootstrap 文件；`chmod 600` 保留 (umask 管不到已经存在的文件)。
- `aether-dev`: push 认证失败的提示原先让人把整份 `~/.docker/config.json` 打出来 (含 base64 的 user:token)，
  改为 `jq -r '.auths // {} | keys[]'`，只列已登录的 registry。
- `aether-setup`: 诊断表「认证失败」一行由 `echo $NOMAD_TOKEN` 改为 `[ -n "$NOMAD_TOKEN" ] && echo 已设置`
  (无输出 = 未设置)，不打印值。
- 主仓 runbook `docs/guides/forgejo-pat-rotation.md` 的 Step 1 / Mode 1 / forgejo-secrets 用法同步改。

三个 SKILL.md 行数不变 (399 / 383 / 293)。替换后的命令用假值实测过: 新文件 600、无换行 (CLI 读 token 文件
`strings.TrimSpace`)、变量不漏到父 shell；jq 对没有 `auths` 键的配置不报错。

### Changed
- `.claude-plugin/requirements.yaml` `cli.recommended_version` 追平到 **1.22.14** (只在 plugin 发版时对齐)。

### 质量门
AB 回归门 + 新行为门 **PASS (按预注册规则，无 `[skip-benchmark]` 豁免)**: 豁免 1 不成立 (改的正是要执行的命令)，
豁免 2 不成立 (既有 eval 不测这几处，是新行为从未测过)。dev / setup 属 Step 3「错误处理改进: 推荐」，owner 决定各加一个
新 eval 跑最小门。suite v1.5.0 (rotate-pat +eval-8、dev +eval-3、setup +eval-3)；base = v1.12.7 + master runbook，
post = 本版文本，两臂 fixture 从 git 对象构建并逐文件钉 sha256。

- round 1 (7 eval × 2 臂 × 双评): 三个新行为门 B1 全过；rotate-pat eval-1 post 掉一条 critical (24h grace —— post 附了
  一段跳过 grace 的应急 fallback)。机械 diff: 两臂改动行里涉及 grace / 24h / 应急 / revoke 的 0 行，相关源文本逐字节相同。
- 预注册确认轮 (开跑前提交): eval-1 / eval-8 两臂重跑 + 对照 eval-6，字母反转 → R1 / R4 清零，R3 判混淆不计入。
- **残余观察**: eval-1 的 24h grace 断言在现网 PAT 已逾期 (`pat_age` FAIL) 时对两臂都失去判别力 —— 四份评分 post 4/4 FAIL、
  base 2/4 FAIL，base 在零配置变化下由 3/3 掉到 1/3。eval-1 场景需刷新，跟踪于 Aether #486。
- 20 臂 + 20 grader 的 transcript 全部机械核查: 无 Skill 调用、无越界读取、无写集群命令、答卷无凭据实际值或凭据形态、
  blind_broken 0。

证据: 主仓 `aether-plugin-benchmarks/ab-results/2026-10-10-481-credential-echo-regression/`。

## [1.12.7] - 2026-09-12 — aether-rotate-pat: references 拆分 (#357) + 追平 cli-v1.20.3/1.20.4 五类 backend (#390/#384/#387)

`skills/aether-rotate-pat/SKILL.md` 从 430 行拆到 399 行（守门层 OK），深度层移入
`references/{admission-forensics.md,changelog.md}`（#357）；并追平 CLI 的 backend 演进：

### Changed
- `BACKEND_NOT_ROTATABLE` 从两成员补到**三成员**：`host-docker-config` + `forgejo-push-mirror`
  (#384) + `github-actions-secrets` (#387)。三支手工路径互不相通（docker login / GitHub 重新生成
  再 Mirror Settings 重填 / 发行方重新签发再各 GitHub 仓 Actions secret 重填），错串会把操作员
  指到错误的机器或平台。
- `UNKNOWN_BACKEND` 合法值三 → **五个**，与 `inventory_schema.json` enum 对齐。
- `registry-auth list` Consumers 列 `N (declared)` 覆盖后三个无在线核验路径的 backend（#340 假零修复）。
- `classifyBackendRefusal` 共用 `suggested_action` 的告诫版本限定为 cli ≤ 1.20.3；1.20.4 起中性文案。

### Added
- 版本地板告诫：台账含第四/第五类 backend 的仓需 cli ≥ 1.20.4（旧版整份拒载 `INVENTORY_PARSE_FAILED`，
  是 CLI 太旧不是台账写错）。
- `.claude-plugin/requirements.yaml` `cli.recommended_version` 追平到 **1.20.4**。

### 质量门
AB 回归门 PASS（强制，无豁免）：base=改动前 vs post=改动后，suite v0.3.0 → v0.4.0（+eval-6 覆盖
第四类、+eval-7 覆盖第五类）。R1/R2/R4 全过，eval-7 新行为门 B1 PASS。round-1 eval-5 掉一条 critical
经复盘为单轮方差（该断言源文本两臂逐字节相同）、预注册确认轮清零。证据见主仓
`aether-plugin-benchmarks/ab-results/2026-09-09-390-357-refs-split-regression/` 与
`.../2026-09-12-390-fifth-backend-regression/`。两处 Minor 版本精度点跟踪于 Aether #400。

## [1.12.6] - 2026-09-07 — aether-rotate-pat 追平 cli-v1.20.0 的 4-step CAS 轮换（#339）

`aether registry-auth rotate` 的 nomad-variables backend 在 cli-v1.20.0 把主写改成一次
compare-and-swap PUT，序列从 5 步变 4 步（首步 `DELETE` 去掉）。SKILL.md 有 6 处仍写 5 步。

### Changed

- 5 处步数明文订正为 4 步，并说明 `PUT_NEW` 是带 ModifyIndex 的 CAS 写、并发写会被 409 拒
- 补 journal schema **1.2 不向下兼容**：resume 必须用启动那次轮换的同一 CLI 版本
- `Mode 6: RESUME_PRE_STATE_LOST` 补版本分支：>= 1.20.0 轮换本身不再产生这个状态，
  仍报该错 = 别的东西删了那条 Variable；1.18.0~1.19.x 才是原来那个窗口
- 同段补：schema 1.2 的 journal 在 `current_consumer.pre_item_keys` 里记着轮换前的**键名**
  （不含值），手工重建时直接读，不用靠猜

### AB 回归门（`ab-results/2026-09-07/`）

判据是**回归**不是增益 —— 「文档写了 4 步 → agent 就说 4 步」是同义反复。

**第一版候选 FAIL 且两轮复现**：它重写了 Mode 6、删掉「这是止血哨兵，不是修好了：只能响亮
地停下，不能恢复」那句定性，结果读它的臂在 eval-2 上丢了「old token 明文丢了怎么办」那一支
（post 4/5 vs base 5/5）。该条期望依赖的文本在两版里**逐字节相同** —— 掉的是语气，不是事实。

**合入的是第二版**（只增不删：保留那句定性，只加版本限定），重测 post 5/5 vs base 4/5。
**只合入被测的那一版。**

## [1.12.5] - 2026-09-06 — 补 v1.12.4 漏更的 requirements.yaml（发版疏漏修正）

> **无 SKILL.md 变更，不触发 AB 门。** 纯元数据补漏。

### Fixed

v1.12.4 发版时**漏更了 `.claude-plugin/requirements.yaml`** —— 该文件是版本要求的
单一事实来源，但核对 7 文件清单时只在仓库根查找而未查 `.claude-plugin/` 子目录，
误判为「文件不存在」。本版补上两处：

- `cli.recommended_version`: `1.18.0` → **`1.19.0`**（aether-cli 已于 2026-09-06 发布 1.19.0）
- 兼容性矩阵新增 `plugin_version: "1.12.4+"` 条目：记录 §2 case C 的
  `aether conn-guard` 需 cli ≥ 1.19.0，更早版本执行会得 `unknown command`；
  `cli_min` 保持 1.0.0 不上抬，因为其余 case A/C/D/E 决策路径不依赖该命令。

跟踪：Aether #371。

## [1.12.4] - 2026-09-06 — aether-conventions case C 增加 conn-guard 自查命令（#366）

> **SKILL.md 内容变更，已过 AB 门**（增量回归门，判定 PASS）。
> 证据: `aether-plugin-benchmarks/ab-results/2026-09-06-366-conn-guard-selfcheck/`

### Added

`skills/aether-conventions/SKILL.md` §2 DNS 域 case C 的决策桥之后，新增一条自查命令：
`aether conn-guard <项目路径>`（aether-cli v1.19.0+），并说明「输出提示扫描范围被截断时
须按提示加 flag 重扫」。

case C 此前**只有规则没有自查手段** —— 「绝不把 IP 钉进任何可能进 HCL 的文件」
全靠自律，改完无从验证。该命令是 Aether #246 降级后保留的检出能力
（放弃实时拦截，保留诊断）。

### AB 门（增量回归门）

既有两份 PASS 数据仍代表当前行为（2026-07-15 质量门 `c7555c9` / 2026-08-23 触发精度门
`ad6ca7a`），故只为新增行为加一个场景，不重跑既有场景。

判据不追求证明增益，而是**测有没有回归** —— 「加了工具指引会不会让 AI 只拄工具输出、
放弃语义判断」。五维度 base×4 vs post×4，**无任何维度劣化**：召回 5/5 持平、
误报 0 持平、`deploy.sh` 语义裁决 4/4 持平、截断处理 4/4 持平、`dig` 自测 post 略优。

反向证据：post 臂 **4/4 主动实测了工具的判据边界**（`http` scheme 一律不报、
拆分式 host/port 看不见），并明确声明结论是自己判的而非「工具说没事」。
工具指引不仅没让 agent 变懒，反而多出一层对工具盲区的审视。

**三条局限随结论引用**（详见 RESULTS.md）: fixture 的 D1 设计有误（它是真阳性不是干扰项）·
证明的是无回归不是有增益（增益命题在此规模下有天花板，v1 轮已实证）·
注入式对照不覆盖「skill 会不会被加载」（由 08-23 触发精度门承担）。

## [1.12.3] - 2026-09-02 — #235 排障表补 L1 直跑路径 OOM 签名（裸 `Killed` 137）

> 纯 reference 文档新增（`references/forgejo-ci-optimization.md` 错误签名表加一行），
> 无 SKILL.md 内容变更 — 不触发 AB 门。

### Added — `references/forgejo-ci-optimization.md`

- **错误签名表新增 L1 act-job 直跑路径行**（#235 租户 08-09 请求，两种签名并列）:
  裸 `Killed` + `exitcode '137'`（**无** `ResourceExhausted`/`npm error` 上下文，出现在
  workflow 直跑步骤如 `run: npm run build`）= **L1 act-job 容器** memcg 命中 —— 与既有
  builder 行（exit 102 + `ResourceExhausted`）是**两条不同路径**，按旧签名 grep 会漏判。
  处置指向节点侧 `container.options`（改 workflow 无效）与
  `forgejo-runner-memory-limits.md` §5.3 amendment（2026-09-02 L1 +2 GiB swap 头寸）。

## [1.12.2] - 2026-08-26 — #338 `aether-rotate-pat` 追平 cli-v1.18.0 + #335 `aether-conventions` 触发边界

> Skill 内容变更 = **强制 AB 门**。PASS: **WITH 4/4 WITH_BETTER**
> (rubric with 4.5/4.8/4.5/4.0 vs without 3.5/4.5/4.2/3.5)。
> **但这是第二轮**: 首轮 3/4，eval-4 判 WITHOUT_BETTER，门禁暴露 forgejo-secrets 段三条缺口，
> 按源码补齐后重跑 eval-4 的 with 臂才达标。全过程与首轮证据保留在
> `ab-results/2026-08-26/summary.yaml`（含 4 条完整性注记）。
> requirements `cli.recommended_version` 1.17.0 → **1.18.0**。

### Fixed — `aether-rotate-pat` (#338 票面三项 + 门禁挖出的四处)

- **准入错误码 8 码表 → 9 码表**: 新增 `DECLARED_VAR_KEY_ABSENT` (cli-v1.18.0 / #334)。
  **触发条件按源码写，与票面描述不同**: 票面写「entry 声明了 `var_key: K`」，实测 entry
  **完全不声明 `var_key` 也会触发** —— 有效键回落成默认 `docker_auth_password`，默认槽位同样
  被逐 path 预检。手工路径按 `path_exists` 分两支（`no Variable at this path` 要建或删该 path；
  `Variable exists but holds no such key` 要拆 entry 写显式 `var_key`）。
- **`PREFLIGHT_FAILED` 作用域更正**: 原文「**仅 `--dry-run`**」被 1.18.0 证伪。四入口实测:
  `rotate --dry-run` / `rotate --confirm` / `resume` 三者**都返回** `PREFLIGHT_FAILED`。
  两支 `suggested_action` 已分流（config 字段**类型**错 vs 探针不可达）——把人指错一支会让他去
  排查一个完全正常的集群。另注明纯 YAML 语法错**构造上到不了**这个分支（viper 吞掉无法
  tokenize 的文件回退默认值）。
- **明示 `cleanup` 刻意不跑集群预检**: 票面称「rotate / resume / cleanup 三入口一致硬拒」，
  与源码不符。同一夹具下三入口返回 `PREFLIGHT_FAILED` 而 `cleanup` 走到 `CLEANUP_FAILED`
  （同夹具构成阳性对照）。源码有 `Do not "fix" this for symmetry` 注释：给 cleanup 加同样守卫，
  会让「轮换成功后才改台账」的 entry 再也 cleanup 不了，于是 `*_OLD` 里的旧 token 永远留在集群上。
- **新增 Mode 6 `RESUME_PRE_STATE_LOST`**: 票面未列的第 10 个操作员可见码（1.18.0 新增）。
  断在 `DELETE` 与 `PUT_NEW` 之间时，该 path 轮换前的兄弟键哪里都不存在（`*_OLD` 要到
  `PUT_OLD` 才写）。**重跑 resume 无用**，须手工重建 Variable。止血哨兵非根治，根治跟踪 #339。
- **`registry-auth list` 的 Consumers 列对 host-docker-config 恒显示 0** (#340)，核对须走 `--json`。
  **并给这条加了边界** —— 同一命令对 forgejo-secrets 行**会真的实查 Forgejo**（设了
  `AETHER_FORGEJO_TOKEN` 即逐 repo 查，未设才回落 `deferred` 占位），别推广成「`list` 不可信」。
- **`secret_name` 是 entry 级、全部 repo 共用**: 一个 entry 装不下「不同 repo 用不同 secret 名」。
- **`rolled_back` ≠ 已验证恢复**: `rollbackForgejoSecrets` 的两个调用错误被 `_ =` 直接丢弃，
  既不中断也不上报；该状态只说明回滚流程跑完了，须自己逐 repo 核 secret 的 `created_at`。
- **更正两处 skill 自身的错误陈述**（均由本轮门禁在两臂输出里逮到）:
  - 「残留 journal 是下一次轮换起不来的原因」—— 错。`RotateNomadVariables` 是 `NewJournal` 后
    直接 `WriteAtomic`，无存在性检查，旧 journal 被直接覆盖；被挡住的只有 `cleanup`。
    该句系从 CLI 源码注释转述，**源码注释本身措辞就松**。
  - 「假 stamp `last_rotated`」的受骗方写松了。`pat_age` **不读**该字段（只看 `rotation_due` /
    `issued_at`），假 stamp 不会让告警闭嘴。全 CLI 唯一的机器读者是
    `doctor --check forgejo_actions_secret_drift`，且它**只读 `org_level: true` 的 entry**
    的 `last_rotated`；对 repo 级 / nomad-variables entry 假 stamp 它根本读不到。

### Changed — `aether-conventions` (#335，触发边界收窄)

- `description` 的触发词由**无条件裸词**改为**集群语境限定**，并新增显式「不适用」边界
  （与 Aether 集群无关的通用 DB / 连接串问题：本地或第三方托管 DB 的驱动与客户端用法、
  连接参数排错、SQL 调优、ORM 配置）。按类别写，**未照抄 #245 TASK-016 负例 prompt 里的库名**
  —— 该 spec 的 constraints 明确禁止往测试措辞过拟合。
- **本项的验收门在发版之后**: 触发精度只能用 model-invocation 实测，而子 agent 加载的是**已安装的
  plugin cache** 而非工作区，必须先发版 + marketplace 更新到 1.12.2 才能复测。
  按 #335 协议跑 N5 ×5（要求让位 ≥4/5）+ 5 条正例 ×5 回归（要求触发命中率仍 ≥80%）。
  **在复测通过前，#335 保持 open，#245 不归档** —— 本条目不构成「已修复」的声明。

### 记录在案（不含糊过去）

- **AB 测的不是最终发版文本**: SKILL.md 在臂跑完后又改了 4 处。其中 2 处是**更正既有陈述**
  （对 eval-1/2/5 而言测的是修改前文本），3 处是为修 eval-4 首轮落败而补（eval-4 v2 测的就是这版），
  最后 1 处在 v2 之后（fact-stating 更正，不引入新决策分支，未再重测）。
  判据与逐条归属见 `ab-results/2026-08-26/summary.yaml` 的 `integrity_notes.I2`。
- **eval-4 首次盲评破盲**: grader 一次以仓根为 root 的 grep 返回了 benchmarks 目录下的路径，
  仅凭路径名即暴露归属（没打开任何文件）。该评分不采信并归档；以更严指令重评，结论与首评一致，
  故首轮判定不是破盲造成的。grader 指令已补两条防线。
- **AB 环境的 CLI 是 1.17.0**（仓内源码与已发版 tag 均为 1.18.0）。这对 with 臂是**逆风**：
  它得在尚未升级的环境里主张 1.18.0 行为。全部 9 臂环境一致，未中途升级。
- **`ab-blind.sh` (#332) 首次当门禁生产实跑**: 自检 10/10、变异 4/4、真实数据阳性对照
  （原样静默 / 注入 2 行 → 3 条 RESIDUE + exit 1）、语义自指宽口径扫描 0 命中。
  **#332 的实机验收由本轮完成。**
- **守门层行数警告**: `aether-rotate-pat` SKILL.md 343 → 413 行，超过 400 警戒（未达 500 阻断）。
  增量全部是门禁驱动的更正与补齐；不为躲警告压缩已核实内容。建议后续把两个 backend 的深水区
  拆进 `references/`（该 skill 目前 refs 为 0）。

## [1.12.1] - 2026-08-23 — #326 `aether-rotate-pat` 追平 cli-v1.17.0 + Step 4 假绿验证修复

> Skill 内容变更 = **强制 AB 门**。PASS: **WITH 4/4 WITH_BETTER** (rubric 4.7/4.7/4.75/4.7 vs 3.9/4.1/4.45/4.4),
> 两臂 Part 1 全部达标无 critical FAIL。结果与协议缺陷记录: `ab-results/2026-08-23/summary.yaml`。
> requirements `cli.recommended_version` 1.16.75 → **1.17.0**。

### Fixed — `aether-rotate-pat` (#326 票面两条)

- **`pat_age` 告警档标签追平 #302 (PR #324)**: 快速决策树的 `14d/30d alert` / `7d critical alert`
  换成 `WARN cadence_33pct / cadence_10pct` 与 `FAIL critical`,并补一段说明档位自 cli-v1.17.0 起
  **按 class cadence 相对** (ci-build 30d / runtime 90d / ops·ops-rotation 180d),`days_to_due` 在
  `(cadence/10, cadence/3]` → `cadence_33pct`,`[1, cadence/10]` → `cadence_10pct`,`≤ 0` → `critical`
  (绝对边界);`rotation_policy: non_expiring` 零 finding。明示旧 `"14d"`/`"7d"` 标签仍在用的是
  `cf_token_age`,别混。
- **准入错误码三码表 → 8 码表**: 补 `BACKEND_NOT_ROTATABLE` · `UNKNOWN_BACKEND` ·
  `FORGEJO_SECRET_NAME_INVALID` · `FORGEJO_ORG_REQUIRED` · `PREFLIGHT_FAILED` (后者 #312 新增,
  **仅 `--dry-run`**,nomad-variables 逐 path 预检 Nomad 不可达即拒,离线 dry-run 不再可能),
  各带触发条件 + 手工路径 + runbook Mode 映射;补判定顺序 (backend → var_key → 可轮换性 → forgejo 字段)
  与「`BACKEND_MISMATCH` 只在 resume 出现,正常 CLI 路径到不了」。
- **dry-run `verify_class` 说明** (#312): plan entry 的 `job_not_found` / `batch_parent` / `dead`
  三类只列 3 步 (跳 RESTART/VERIFY) + 信封 `verify_skipped_count` 是预期而非缺陷,处置看 runbook Mode 8。

### Fixed — `aether-rotate-pat` Step 4 验证是假绿 (AB 盲评抓到,票面之外)

- 原 Step 4 让操作员用 `ssh heavy-N 'docker pull ...'` 验证轮换生效。该命令走**节点上那份 docker
  登录配置**,与本次轮换的 job 级 registry 口令 var 是**两套独立凭据**;#234 prong b 之后节点那份
  已不是任何 Nomad job 的可用性依赖,因此它**无论轮换成没成都会绿**。
- 改为真正消费新 token 的阳性对照: 内网 `/v2/<org>/<image>/tags/list` 探针,token 走 `curl -K`
  配置文件不进 argv (#282);并标注 Tier 1 的 `VERIFY_OK` 只轮询 alloc `running` 从不回读 token (#301),
  以及「靠 alloc 重启触发重拉」同样不可靠 (镜像本地已存在时 docker driver 可能根本不发 pull)。
- 实机佐证: 内网 `/v2` 无凭据 401 (探针形态有效),外网 `forgejo.10cg.pub` 前有 CF Access 得 302
  (判不了凭据,故指定内网端点)。

### Changed — AB 方法学: 首次去标识化盲评

- 阶段一盲评发现**盲评在文档内容层面本就不盲**: with 臂报告开头自报「依据 Skill aether-rotate-pat
  v0.3.1 执行」、正文引用「SKILL.md 第 N 行」,without 臂文末自报「AB 基线组」。随机化 A/B 映射和
  换 staging 目录都拦不住 —— 泄漏在被测文档自身 (两名 grader 各自主动申报)。
- 阶段二加 scrub (剥离自述条件行 + 中性化 skill 名/版本) + 盲评副本 staged 到仓库外 +
  显式禁止 grader 检索 benchmarks 全树,复查零残留后重评,**最终采信阶段二**。
- **对基线的影响**: 2026-08-09 的 4/4 由同一 harness 产出,很可能同样不盲,与本轮不完全可比。
- 建议把 scrub 收编进 `scripts/ab-blind.sh` 并加零残留自检 (另立票)。

## [1.12.0] - 2026-08-09 — #275 凭据双 skill 九笔文档债清理 + AB 基线刷新

> 两个 P1 凭据 skill 内容变更 = MINOR bump。**强制 AB 门 PASS: WITH 7/7 WITH_BETTER**
> (rotate-pat 4/4, forgejo-creds 3/3 首基线), WITHOUT 臂 3 处 critical FAIL。
> requirements `cli.recommended_version` 1.16.61 → **1.16.75** (落后 13 个 release 已追平)。

### Fixed — `aether-rotate-pat` (债 1/2/3/6/9)

- **`aether doctor <check>` 旧语法** → `aether doctor --check <name>`。`doctor` 是 `Args: cobra.NoArgs`,
  位置参数形态**从未存在过** (非"CLI 改接口致文档滞后"); 实测 `unknown command`。全 plugin **14 处**全修
  (#275 表格仅列 6 处;另 8 处在 `aether-init/references` ×5 / `aether-volume` ×1 / fixtures README ×2,
  按豁免 1 边界情形处理并经 owner 逐条确认)。skill 内保留一处**反例文本**说明该形态跑不通。
- **新增「Tier 1 准入边界」章节** —— cli-v1.16.74/75 引入的三个准入拒绝码
  (`VAR_KEY_UNSUPPORTED` / `ORG_LEVEL_UNSUPPORTED` / `NO_ROTATABLE_CONSUMERS`) 各自的触发条件 +
  手工路径 + runbook Mode 6/7 锚点;并区分 `NO_ROTATABLE_CONSUMERS` (声明了却是空的) 与
  Mode 4 `BOOTSTRAP_NO_AUTOROTATE` (根本没有 consumers 块)。
- **`--dry-run` 与 `--confirm` 共用准入点** (#281/#287 落地后实测: 两条 entry 的 dry-run 直接吐对应错误码)。
  **注意方向**: #275 triage (2026-08-06) 建议补的「dry-run 通过不代表 confirm 会通过」警告在 PR #285/#288
  合入后已**反向失效**, 本次按实测写成"两路判定一致", 并把旧假绿降级为 **cli < 1.16.74 的历史警告**。
- **`--from-file` 强制** —— 手工路径一律 `--from-file`, 绝不把 token 值写成命令行参数 (argv 进 shell
  history / `ps aux` / AI transcript, 与 stdout 是否遮蔽无关, #282)。另加"工具拒绝执行时不要顺手
  stamp `last_rotated`"告诫。
- **[AB 揪出] bootstrap scope 更正**: forgejo-secrets backend 的 `AETHER_FORGEJO_TOKEN` 需
  **`write:repository`** (打 `/repos/<o>/<r>/actions/secrets`), 原文误写 `write:user` (那是
  nomad-variables 侧打 `/users/<n>/tokens` 需要的)。照原文 mint 的 bootstrap PAT 会 scope 不足必败。
  权威: `docs/guides/forgejo-pat-rotation.md §Pre-requisites` access matrix。
- **[AB 揪出] resume 退出码更正**: `FORGEJO_MANUAL_RECOVERY_REQUIRED` 时 **exit 1** 而非原文的 exit 4;
  `registryAuthResumeErr` 两个分支均 `os.Exit(1)`, 全仓无 `os.Exit(4)`。判别应看 JSON envelope 的 `error.code`。

### Fixed — `aether-forgejo-creds` (债 1/5/7/8)

- **[#291 物种第三个传播点] username/401 断言收窄** (§1 账号规则 · §2 401-vs-403 速判 · §5 红线 5 共三处)。
  Forgejo 容器 registry 的 `/v2/token` **只校验 PAT、完全忽略 basic-auth username** (2026-07-02 /
  07-12 / 08-08 三次独立实测)。401 一律**先查 token 死活**;username 仍应保持正确, 但理由是**日志可读 +
  记录准确 + 非 registry 消费方行为未验证**, 不是"否则会 401"。含边界声明与 #291 消歧锚点。
- **[AB 揪出] T3↔T4 解耦事实更正**: 原文称 org `FORGEJO_TOKEN` (T3) 与 aria-build `FORGEJO_BOT_PAT` (T4)
  复用同一物理 token、轮换 T3 会连带断 aria-build ——**2026-07-02 已解耦**, T4 用专用 `write:package` token。
  同时保留"blast-radius 仍须逐条枚举"的告诫 (解耦只解了这一条已知耦合)。
- **[AB 揪出] T1 scope 更正 (2 处)**: simonfish dev-shell token **2026-07-02 起已有 `read:package`**
  (只读), 原文两处仍写"无 package → doctor 查 registry 会 401", 会让操作者无谓绕道内网或临时借用 T2 值。
  仍无 `write:package` 的部分保持不变。
- §4 手工轮换路径补上错误码锚点 (拿到码即知走哪条手工路径) + `--from-file` 安全形态 (#282)。

### Added — AB eval 套件 (suite v1.1.0 → v1.2.0)

- `aether-rotate-pat` 升 0.2.0: **retire eval-3** (ci-build defer-to-emergency —— 2026-05-09
  forgejo-secrets GA 后其期望答案已错, 保留在册以便回溯基线);**新增 eval-4** (forgejo-secrets Tier 1
  happy path) 与 **eval-5** (准入拒绝三码 + 两个危险提议: 改 inventory 绕过守卫 / 提前 stamp `last_rotated`)。
- **新建 `aether-forgejo-creds` 首个套件** (3 例): 401 username 陷阱 / 该用哪个 token / revoke 前枚举全部 store。
- **门径证据**: static-benchmark rotate-pat 297 行 [OK] · forgejo-creds 205 行 [OK] (均 <400)。
  **AB PASS 7/7 WITH_BETTER**, 结果与协议记录见 `aether-plugin-benchmarks/ab-results/2026-08-09/summary.yaml`。

### Changed

- `requirements.yaml`: `cli.recommended_version` **1.16.61 → 1.16.75**;新增 `1.12.x` 兼容矩阵条目
  (说明三个准入码需 cli >= 1.16.74/1.16.75, 但 `cli_min` 不上抬 —— skill 内已标注版本边界)。

### 方法论记录 (AB 协议缺陷与修正)

首轮 AB 判 **FAIL (WITH 3/7)** 并已归档于 `ab-results/2026-08-09-run1-protocol-defect/`, **不作发版依据**。
两处缺陷 + 一处 rubric 污染, 均已修正后重跑:

1. **盲评脚本非幂等** —— 每次运行重刷全部映射表, 致 rotate-pat 四例的原始 A/B 归属在评分后被覆盖;
   编排层因此曾报出两条错误结论, 事后用各臂独有的内容判别串 (每例 2-5 个交叉验证) 重建才发现。
   脚本已改为幂等 (重新盲化须显式 `--force` 且不得在 grader 运行期间执行)。
2. **without 臂未被禁止读仓库源码** —— 实测变成"skill 摘要 vs 深挖源码"(单臂曾耗 193k tokens /
   39 次工具调用)。修正后 without 臂平均 20 次 → 9 次调用、124k → 76k tokens, 回到真正的无引导基线;
   grader rubric 同时加"不得因引用仓库特有标识而加分/因缺失而扣分", 防偏置转移到评分侧。
3. **rubric 含陈旧断言** —— creds eval-3 照 skill 现有文本写 rubric, 把已过时的 T3↔T4 耦合写成了
   GROUND TRUTH。**用被测对象当判据来源, 会把被测对象的错误固化成判据。** 已改写为"必须逐条核实当前
   实际消费者"。同物种也修了 eval-4 rubric 里的 `exit 4` / `write:user` 两条。

首轮虽作废但**是五处 skill 事实错误里四处的发现来源**, 故保留归档。

## [1.11.0] - 2026-07-16 — #245 aether-conventions 集群集成规范 hub

> 新增 L2 skill = MINOR bump。Phase B 全部实施 + 五强制门 PASS + 发布前 discriminating 重测。requirements cli.recommended_version → 1.16.61(配套 CLI doctor check)。

### Added — `aether-conventions` L2 skill (强制 AB PASS)
- 四域 investigation-first hub (DNS case-A-first / 凭据窄委托 forgejo-creds + 应用DB-secret in-scope / volume / stateful) + references 蒸馏 + L3 集成规范 policy 段 (`aether-init` 幂等注入)。
- **门径证据**: static-benchmark 156 行 [OK]; **强制 AB 测试 PASS** (with 4/4 胜, 规范遵循率 1/4→4/4, blind grader; 见 `aether-plugin-benchmarks/ab-results/2026-07-15/aether-conventions.md`); 自包含隔离 / L3 静默对抗 / 触发精度门均 PASS。

### Fixed — `aether-volume`: 单节点示例违反 #56 全heavy铁律 (#245 TASK-004)
- 创建示例 `--node heavy-1` 单节点(与 #56 blast-radius trap 反模式冲突)→ 语境化为"无状态/测试专用" + 加"生产/有状态必须全 heavy 注册"铁律 + `--register-only`(已有数据)+ host_volume_parity 诊断 + aether-conventions 互链。
- `min_version 0.7.0 → 1.15.0`(新示例用 `--register-only`, 需 CLI 1.15.0+)。
- **门径证据**: static-benchmark 254 行 [OK]。**AB 定案(2026-07-16 双臂重测)**: 新旧 skill 内容双臂 AB delta≈0(新 4/4 全heavy / 旧 4/4 全heavy, stateful 框定天花板) → 内容改动**不 regress**, `[skip-benchmark]` **豁免成立**(纠正 #56-违规错误示例的 correctness fix, 非改推荐路径)。fix 仍 warranted(旧单节点示例在非-stateful 框定下可能误导)。证据 `aether-plugin-benchmarks/ab-results/2026-07-15/aether-conventions.md` discriminating 段, run `wf_e6d9ffd4-937`。

### Fixed — `check_template_drift` 虚假既成事实声称订正 (#245 TASK-006)
- 见下方 [1.x] 段的 inline 订正: `file-generation.md` + 本 CHANGELOG 双处订正该函数"文档声称却代码不存在"。
## [1.10.24] - 2026-07-14

### Changed — 版本一致性收尾 (无 skill 内容变更, 纯 metadata)

- `requirements.yaml` cli.recommended_version `1.16.43` → `1.16.60`（跨会话遗留漂移,
  期间 CLI 实际发了 16 个 patch: doctor 系列检查 / self-update 二进制化 / volume --name /
  node_docker_auth_parity 等）。
- `hooks.json` version `1.10.16` → `1.10.24`: 该文件自 1.10.17 起连续 7 个版本被 bump
  流程遗漏, 本次对齐并入 7 文件一致性检查范围。
- 不涉及任何 SKILL.md 内容变更, 无需 AB 测试。

## [1.10.23] - 2026-07-12

### Changed — `forgejo-ci-optimization.md` § Troubleshooting: memcg OOM entry 细化 (#235)

- `cannot allocate memory` / `ResourceExhausted` entry 现区分 **runaway**（#149 防御）
  vs **合法增长顶破**（本地 build 干净 + 无并发 = 代码量涨到把类型检查内存推临界,
  非 bug, SilkNode 首例）; 加 `npm error signal SIGKILL` 签名 + swap 头寸处置 +
  "改 workflow --driver-opt 不生效"坑（builder 节点级 provision, `|| true` 只 adopt）。
- 配套 Aether 侧: aether-build builder memcg 4 GiB RSS + 2 GiB swap 头寸 (§7.6 #235 amendment)。

## [1.10.22] - 2026-07-07

### Fixed — `aether-build-container`: push 用 write token (T4) 修 #225

skill build 成功后 push 稳定 401 —— DooD 挂宿主 `/root/.docker` = T2 (`10cg-ci-bot` `read:package`)，对 `10cg/*` push 缺 `write:package`。修复（读写分离 T2 pull / T4 push）：
- **task-script.sh**：push 用 T4 (`write:package`) 登录 **throwaway** docker config 再 push，宿主只读 config 全程不被写。
- **job-template.hcl**：`template{}` 从【本次运行自己的】Nomad var 注入 T4 → `secrets/push.env` env（token 不进 job spec 明文）。
- **SKILL.md**：dispatch 前 (Step 5b-bis) 写 T4 到 `nomad/jobs/build-container-<id>`（秘钥经 600 文件不上 argv），Step 8 finally `nomad var purge`；push 鉴权段重写 + 错误码新增 `push_auth_failed` (exit 24)。

真机 e2e 验证：build+push 到 `10cg/cesura-backend` → `status=ok`。Closes #225。

## [1.10.21] - 2026-07-02

### Added — 新 skill `aether-forgejo-creds`（Forgejo 凭据决策/诊断/轮换指南）

根治 H1（#189）暴露的凭据"乱"：新 skill 指导 AI/operator 在 Aether 环境下正确用 Forgejo token——

- **决策**：人机两账号模型（simonfish 人 / 10cg-ci-bot 机）+ "我做 X 用哪个 token" 矩阵
- **诊断**：CF Access vs forgejo PAT 两平面 + 误导性 `Only signed in user` 403（302/403-json/200 口诀）
- **轮换**：revoke 前枚举全部 store（Nomad var + Actions secret repo/org + host docker config + shell env）
- **红线**：不跨账号一 token N 用、机器 token 不进人 shell、凭据卫生（sha256 指纹不打印值）

投产验证（CLAUDE.md 强制流程）：static-benchmark 175 行 [OK]；**AB 测试 3/3 场景 with-skill 胜**（agent team workflow：author + with/without + blind grader + skill-reviewer）；review verdict ship-with-fixes（4 项 fixes 已应用）。深度指向 `docs/guides/forgejo-token-map.md` + `.aether/pat-inventory.yaml`。

## [1.10.20] - 2026-07-02

### Changed — `cli.recommended_version` 1.16.42 → 1.16.43

CLI 发布 `1.16.43`（#189 P3: PAT inventory schema 加 `org_level` flag + `host-docker-config` consumer type；新 doctor check `forgejo_actions_secret_drift` 对账 org Actions secret 补 H1 审计盲区）。`requirements.yaml` 追平推荐版本。

- 纯 metadata 指针更新，**无 SKILL.md 改动 → 免 AB 测试**。
- 对应 CLI 变更见主仓 `aether-cli/CHANGELOG.md` `[1.16.43]`。

## [1.10.19] - 2026-07-01

### Changed — `cli.recommended_version` 1.16.41 → 1.16.42

CLI 发布 `1.16.42`（`pat_inventory_drift` + PAT inventory schema 加 `var_key` 支持 — 消除 silknode 双-cred / aria-build 自定义 key 两个良性 drift 误报）。`requirements.yaml` 追平推荐版本。

- 纯 metadata 指针更新，**无 SKILL.md 改动 → 免 AB 测试**。
- 对应 CLI 变更见主仓 `aether-cli/CHANGELOG.md` `[1.16.42]`。

## [1.10.18] - 2026-06-30

### Changed — `cli.recommended_version` 1.16.40 → 1.16.41

CLI 发布 `1.16.41`（新增 `aether volume recapture-sot` — volumes.hcl SoT auto re-capture，#184 C2）。`requirements.yaml` 追平推荐版本，让用户安装时拿到含新命令的 CLI。

- 纯 metadata 指针更新，**无 SKILL.md 改动 → 免 AB 测试**。
- 对应 CLI 变更见主仓 `aether-cli/CHANGELOG.md` `[1.16.41]`。

## [1.10.17] - 2026-06-29

### Changed — `cli.recommended_version` 追平 1.16.36 → 1.16.40

`requirements.yaml` 的 `cli.recommended_version` 自 1.10.16 起停在 `1.16.36`，而 CLI 已发布到 `1.16.40`（本轮随 Aether `volumes_hcl_drift` doctor check 一并发版）。用户安装时依此字段确认推荐 CLI 版本，落后会让用户停留在旧 CLI。本次追平到 `1.16.40`。

- 纯 metadata 指针更新，**无 SKILL.md 改动 → 免 AB 测试**。
- 对应 CLI 变更见主仓 `aether-cli/CHANGELOG.md` `[1.16.40]`（新增 `volumes_hcl_drift` check）。

## [1.10.16] - 2026-06-14

### Added — `forgejo-ci-optimization.md` 跨境 egress / 代理网关防御 (guide 1.2.0)

来自 Aether #172 (SilkNode) / #173 (nexus) 的 live-probed triage —— 把「runner 跨境拉包间歇失败」固化进 L2 权威 guide：

- **Environment fact #8**: heavy runner 所有外网 egress 经透明代理网关 `192.168.69.212`（外网 host 解析为 fake-IP `198.18.0.x`，`ip route get` → `via 192.168.69.212`）。核心诊断属性：**小 probe 必过 / sustained transfer 间歇失败** —— 单次 `curl -I` 不能判 egress 健康。内网镜像（verdaccio/devpi @ `.206`）不经代理。
- **A11**（新反模式）: CI 热路径任何跨境 fetch（Prisma engines 外网 CDN / `# syntax=docker/dockerfile:1` 拉 Docker Hub frontend / devpi cache miss 回退 pypi）都经代理 → 间歇 timeout；含「无 step timeout → 193min 静默卡死」复合故障。
- **B12**（新最佳实践）: 内网镜像化整条热路径（含 secondary fetch 审计）+ 每个 install/build step 加 `timeout-minutes` fast-fail。
- **Troubleshooting §**「Cross-border egress / proxy-gateway errors」+ Workflow/runner 表补「卡 30-190min」「cancel rc=22」行。
- **A6 erratum**: 「Docker Hub access 稳定」修正 —— `registry-1.docker.io` 也经代理，可间歇 TLS-handshake-timeout（SilkNode run 8155 实证）。

纯 reference 文档增补（**无 SKILL.md 改动 → 免 AB 测试**）；反应式 hardening，非 OpenSpec change。`cli.recommended_version` 不变（CLI 未改，仍 1.16.36）。

## [1.10.15] - 2026-06-13

### Changed — `cli.recommended_version` → 1.16.36 + hooks.json 版本对齐

- `requirements.yaml`: `cli.recommended_version` 1.16.34 → **1.16.36**，追上当前
  aether-cli release（`cli-v1.16.36` — doctor `build_oom_events` /
  `buildx_builder_provisioned` probe sentinel 硬化，Aether #151 / #170 follow-up）。
- `hooks.json`: 版本 **1.10.13 → 1.10.15** — 修正 v1.10.14 发版时遗漏的版本漂移
  （该文件未随其余 6 文件 bump）。
- 7 文件版本统一 1.10.14 → **1.10.15**（VERSION / plugin.json / marketplace.json /
  hooks.json / requirements.yaml / README.md / CHANGELOG.md）。

纯 metadata 发布，无 SKILL.md 改动 → 免 AB 测试。

## [1.10.14] - 2026-06-11

### Changed — build 路径迁移到节点常驻限额 builder (Aether #151 ①+(i))

- `aether-init` reference `workflow-templates.md`：dev workflow 的
  `setup-buildx-action(driver: docker)` + `build-push-action(push:false,load:true)`
  + 手动 tag/push 三步，改为单步 `docker buildx build --builder aether-build
  --push` 多 tag 直推。builder 由 heavy 节点 systemd 单元常驻 provision
  （docker-container driver + **4 GiB memcg**（防 #149 retry-storm 拖垮宿主）
  + `network=host` + buildkitd.toml CA pin）；workflow 内 `create || true`
  adopt。顶部"关键设计决策" 1/2 同步重写。
- `references/forgejo-ci-optimization.md`（L2 权威 guide）联动演进：
  - §A1 加 EVOLUTION 注记（docker-container driver 经 provisioning 后是标准，
    裸 setup-buildx 形态仍坏）+ **根因订正**：oauth token fetch 发生在 job 容器
    CLI 侧而非 buildkitd（这就是 buildkitd-config-inline 永远修不了它的原因；
    #151 §9.1 S3 spike 实证），由 runner 注入 job 容器的 CA bundle bind 解决。
  - §B1 重写为 aether-build 新标准形态（不再需要 setup-buildx-action）；
    §B3 标 LEGACY；决策树/触发清单/Dos-Don'ts 同步，新增 memcg 命中签名行
    （exit 102 / `cannot allocate memory` = 防御生效非 bug）+ "勿把迁移 repo
    修回 driver: docker" 防 #163 式倒退。
  - §A2 加注：registry cache 随 CA 链可能解锁，未验证勿启用。
- 无 SKILL.md 改动（决策树/触发条件不变）→ 免 AB 测试（同 v1.10.12 先例）。
  守门层: refs 总词数 5272 (net -1 vs v1.10.13 的 5273；>5000 cost-guard
  BLOCKED 为既有状态，follow-up 瘦身 issue 另行跟踪)。

## [1.10.13] - 2026-06-04

### Changed — make NFS-virtiofs guide reachable for plugin-only users (#159)

- `aether-init` reference `nomad-templates.md`: the host-volume guide link was a
  relative path (`../../../../docs/guides/...`) that resolves only inside the main
  Aether repo — unreachable for plugin-only users. Replaced with the full Forgejo
  web URL and inlined a compact **node-class × storage capability** summary
  (`heavy_workload` = docker + NFS-virtiofs; light = exec-only) so the essential
  mapping no longer requires opening the main repo. Surfaced by #157 triage.
- `cli.recommended_version` 1.16.33 → **1.16.34** (tracks the paired aether-cli
  release that fixes the same guide path in `volume create --help`).
- References-only change (no SKILL.md decision-tree/trigger edit) → SKILL AB-test
  gate not triggered; fact-stating doc addition.

## [1.10.12] - 2026-06-04

### Changed — track current CLI + fix release tag URL (requirements.yaml)

- `cli.recommended_version` 1.16.21 → **1.16.33** (current aether-cli release,
  #163 docker_prune systemd-timer detection fix).
- Fixed `cli.tag_format` / `cli.version_url`: were `aether-cli/v{VERSION}`, but
  main-repo release tags are actually `cli-v{VERSION}` (e.g. `cli-v1.16.33`) —
  the install-by-version flow would 404. Now `cli-v{VERSION}`.

## [1.10.11] - 2026-05-23

### Added — `aether-init` build-cache override doc (#117 P0 doc follow-up)

Added new §"In-cluster build-cache override (可选,大幅提速)" to
`skills/aether-init/references/dockerfile-templates.md` explaining how to
override the default public-mirror ARGs (`NPM_REGISTRY` /
`PIP_INDEX_URL` / `UV_INDEX_URL`) to point at the in-cluster build-cache
LXC (CT 306, 192.168.69.206) when builds happen inside the Aether cluster.

The defaults stay on public mirrors (`npmmirror.com` / `mirrors.aliyun.com`)
for portability — projects building outside the cluster keep working.
Projects building inside the cluster can pass `--build-arg
NPM_REGISTRY=http://192.168.69.206:4873/` (or pip/uv equivalents) for
3-5× faster cold builds.

Also documents:
- Host-stage env injection is already global (P3 done; no workflow
  change needed for `npm ci` / `pip install` steps)
- Security boundary: don't commit `.npmrc`/`pip.conf` with internal IP
  to public repos
- Health check: points at `aether doctor build_cache_health` (CLI
  v1.16.22+) for verifying LXC reachability

Companion CLI feature: `aether doctor build_cache_health` (Aether main
repo v1.16.22).

[skip-benchmark] — 豁免 1 (additive documentation section, no decision
tree change, no new trigger condition, no behavior change to any
existing init flow).

**Files**:
- `skills/aether-init/references/dockerfile-templates.md` — +60 lines
  new section before "Alpine vs Debian-slim 选择"

## [1.10.10] - 2026-05-23

### Fixed — `aether-report` Forgejo labels payload note (Aether #138)

`aether-report` SKILL.md §6 Forgejo submission template already omits the
`labels` field, but lacked an explicit warning explaining *why*. Future
agents/maintainers reading the GitHub branch (which uses `labels:[\"bug\"]`)
were tempted to "fix" the Forgejo branch by adding labels — triggering
HTTP 422 (`json: cannot unmarshal string into Go struct field
CreateIssueOption.labels of type int64`) because Forgejo expects
`[]int64` (label IDs) not `[]string`.

Added a 1-paragraph note immediately after the Forgejo `forgejo POST`
example documenting the API divergence and pointing to the
`GET /repos/{owner}/{repo}/labels` workaround.

**Companion fix (outside this submodule)**: The `forgejo` CLI wrapper
at `~/.npm-global/bin/forgejo` previously used `curl -sf` which silently
ate 4xx/5xx bodies, leaving callers with no diagnostic. The wrapper was
hardened in this same effort (Aether main repo commit) to surface HTTP
errors on stderr + exit 2 — meaning that if an agent ever does send a
bad payload, the error will now be visible rather than silent
`exit=22`.

[skip-benchmark] — 豁免 1 (pure documentation warning, no decision tree
change, no new trigger conditions, no behavior change to any
existing path). Issue #138 explicitly identified the gap as
documentation-only on the skill side.

**Files**:
- `skills/aether-report/SKILL.md` — +1 warning paragraph in §6

## [1.10.9] - 2026-05-22

### Added — `aether-build-container` skill (Aether #27 walking skeleton)

New owner-triggered build primitive that lets Aether build container images
on the cluster (heavy nodes) and push to internal registry, eliminating
Symptom B "用 Aether 做 build 无 entry point" identified in Aether #27.
Zero Go code / zero CLI version bump on Aether side / Level 2 / pure
skill delivery.

**Capabilities**:
- Owner-triggered Nomad batch dispatch via `aether dev run` (no automatic
  CI gate, owner agency preserved)
- 5-field output contract (`image_sha256` / `registry_url` /
  `source_commit_sha` / `source_git_ref` / `build_node`) per Aria #111
  authoritative input
- 8 error codes (4 node-side exit 20-23 + 4 skill-side)
- Multi-submodule meta-repo support via `git clone --recurse-submodules`
  + tar working tree (covers Aether/Aria/nexus/silknode + standards-
  shared submodule pattern; ~1/3 10CG projects)
- §3a pre-flight registry-auth parity check across dynamic Nomad
  /v1/nodes filter
- DooD execution (docker:cli + host docker.sock + /root/.docker + shared
  virtiofs build-ctx mounts)
- 1800s alloc deadline + skill-lifecycle finally cleanup

**Validation** (full audit trail in Aether #27):
- post_spec audit converged PASS (3 rounds; R1 caught real D2×D5 critical)
- post_implementation audit converged PASS (1 round, 0 C/M, 12 minor tracked)
- pre_merge audit converged PASS + D4 amendment addendum
- AB tests 3/3 WITH_BETTER decisive (1 standard + 1 negative + 1 edge)
- e2e smoke 6/6 PASS — single-repo AND multi-submodule meta-repo fixtures
- 7 runtime issues caught + fixed during smoke iteration

**Files**:
- `skills/aether-build-container/SKILL.md` (228 lines, under 400 warn
  threshold per static-benchmark gate)
- `skills/aether-build-container/references/job-template.hcl` (raw_exec
  → docker DooD pivot after heavy_workload nodes proven to lack raw_exec)
- `skills/aether-build-container/references/task-script.sh` (8 error
  code exit mapping, `$NOMAD_ALLOC_ID` in every result.json)

**Known iteration follow-ups** (non-blocking, tracked in audit reports):
BUILD_ARGS escaping doc location, smoke sha-prefix assertion precision,
5/8 error codes not deterministically triggered (only `source_not_found`),
RW `/root/.docker` mount → "trusted Dockerfile only" boundary precision.

Cross-ref: Aether #27 / Aria #111 / Aether #32 (Vault deferral preserved).

## [1.10.8] - 2026-05-14

### Changed — `aether-report` skill v1.0.0 → v1.1.0 (empty-body validation gate)

Closes the gap that allowed Aether issue #23 to enter backlog with an
empty body in 2026-04-09 and remain unactionable for a month before
being closed stale on 2026-05-14. User-identified root cause: skill had
no hard gate refusing empty submissions.

**New Step 4.5 (hard gate, between compose and preview)**:

- Description / use_case / steps fields require ≥ 20 chars non-whitespace
- Title requires ≥ 10 chars (rejects "?" / "..." / "a" placeholders)
- Body must contain at least one rendered user_* field (not just template
  scaffolding + environment info)

On failure: re-prompt OR exit. Three re-prompts allowed but a determined
user with nothing to say cannot bypass the gate by repeated empty
submission — the skill exits hard instead of creating a placeholder
issue.

**Why this matters per the #23 lesson**: AI-side processing of
unactionable issues costs operator time (triage comment, follow-up
nudge, stale closure decision) that's better spent on issues with
real content. Refusing empty submission at the skill boundary
eliminates the entire downstream chain.

**Cost guard**: SKILL.md now 291 lines (was 254). Well under 400/500
warn/block thresholds per `static-benchmark.sh`.

**AB test**: skipped per CLAUDE.md §Skill 变更强制流程 "错误处理/格式
改进: 推荐" — this addition is unambiguously positive (refusing a
class of low-quality submission has no path where it makes the skill
behave worse). Existing happy-path scenarios continue to pass through
all 7 steps; new Step 4.5 only activates on empty-body inputs that
didn't previously have a defined behavior anyway.

### Plumbing

- `cli.recommended_version`: 1.16.9 → **1.16.21** (catches up to today's
  5 new doctor checks shipped this session: `heavy_node_dns_clean_upstream`,
  `cloud_init_network_disabled`, `runner_health`, `cron_job_backlog`,
  `heavy_node_forgejo_hosts_entry`, `registry_mirror_drift`)

Refs: Aether #23 (the root-cause incident that motivated this gate)

## [1.10.7] - 2026-05-09

### Changed — `aether-rotate-pat` skill v0.1.0 → v0.2.0 (DRAFT → GA, content refresh post-TASK-2.7b)

Refresh skill content to reflect Aether #45 Phase 2 TASK-2.7b GA
(forgejo-secrets backend rotation tooling shipped 2026-05-08 evening,
v1.10.6 plugin release predated this content refresh by hours):

- `skills/aether-rotate-pat/SKILL.md` header: version 0.1.0 → 0.2.0;
  removed "(DRAFT — AB pending)" footer; AB benchmark snapshot retained
  with eval-3 deprecation note.
- "决策核心" section: was "nomad-variables GA; forgejo-secrets ci-build
  defer to emergency runbook" → both backends GA with per-backend
  semantic snapshot (5-step + atomic vs 2-step + best-effort + chaos-kill
  defer-to-emergency).
- New `forgejo-secrets backend 流程` section (45 lines): 7-row diff
  table vs nomad-variables, full usage example with --old-token-file +
  AETHER_FORGEJO_TOKEN env, interrupt recovery semantics, 4 forgejo-
  specific failure modes (MISSING_OLD_TOKEN_FILE / MISSING_FORGEJO_TOKEN
  / FORGEJO_MANUAL_RECOVERY_REQUIRED / CLEANUP_REFUSED_INCOMPLETE).
- Footer "Last updated": 2026-05-08 (DRAFT) → 2026-05-09 (GA).

### Skill 变更强制流程 waiver

Per CLAUDE.md `§Skill 变更强制流程`, SKILL.md content changes require AB
re-benchmark before version bump. This release uses [skip-benchmark]
waiver because:

1. AB methodology validated for skill: 3/3 evals WITH_BETTER (2026-05-07
   v0.1.0; results retained at `aether-plugin-benchmarks/ab-results/2026-05-07/aether-rotate-pat/`).
2. Existing eval-3 ("ci-build-class-defer-to-emergency") tests behavior
   that is now incorrect post-TASK-2.7b GA. Re-running eval-3 against
   refreshed skill would test the WRONG question (the new behavior is
   "use Tier 1 normally for ci-build", not "defer to emergency").
3. Designing new eval scenarios for forgejo-secrets Tier 1 happy path +
   chaos-kill-defer-to-emergency requires non-trivial fixture work
   (live-cluster-shaped tests) — tracked as follow-up issue.

The content change is fact-stating (forgejo-secrets is now GA, here's
how to use it) backed by spec amendment scope_amendment_2026_05_08
recorded in main repo proposal.md frontmatter. R1 audit (4-agent
challenge mode) flagged the skill DRAFT/WIP messaging as Critical
(tl-C2); this release closes that finding.

### Spec / Issue

- Aether #45 Phase 2 R1 pre_merge audit tl-C2 + cr-M1 + tl-M1 + tl-M3
  convergent finding closure (DRAFT footer + WIP messaging in GA artifact).
- Main repo commits eef7ebd (dry-run sub-step fix) + 730c87f (doc drift
  refresh) handle CLAUDE.md / runbook / MEMORY / proposal.md surfaces.

## [1.10.6] - 2026-05-07

### Added — `aether-rotate-pat` skill (#45 Phase 2 GA)

New user-invocable skill `aether-rotate-pat` (204 lines) covering the full
Forgejo PAT (Personal Access Token) rotation lifecycle via `aether
registry-auth list / rotate / resume / cleanup`. Provides AI guidance for:

- 5-step `nomad-variables` backend rotation (dry-run → confirm → 24h grace
  → cleanup → web UI revoke) with expected stdout per step
- 5 failure-mode recovery paths (chaos kill / fingerprint mismatch /
  cleanup-refused / bootstrap class / generic rolled_back) keyed off
  journal state at `.aether/tmp/rotation-state-<pat-id>.json`
- `forgejo-secrets` backend status (TASK-2.7b deferred → emergency runbook
  fallback at `docs/guides/forgejo-pat-emergency-rotation.md`)
- Operator print-checklist (D-0 / D+1) + canonical runbook cross-reference
  (`docs/guides/forgejo-pat-rotation.md`)

Triggers: `轮换 PAT`, `rotate token`, `PAT 即将过期`, `doctor pat_age 报警`,
`registry-auth`, `Forgejo token 过期`, `凭据轮换`, `renew PAT`,
`credential rotation`, `rotation drill`, `cleanup _OLD`.

**AB benchmark**: 3/3 evals WITH_BETTER (blind compare),
all 15 critical+high expectations PASS both arms,
content+structure scores 30 vs 25 (+20%). Results at
`aether-plugin-benchmarks/ab-results/2026-05-07/aether-rotate-pat/`.

### Changed

- `requirements.yaml`: `cli.recommended_version` 1.15.0 → 1.16.9 (sync to
  current CLI release; the new skill's `aether registry-auth` subcommands
  require `min_version: 1.16.7`).
- Plugin metadata (plugin.json / hooks.json / marketplace.json / README.md)
  skill count description: 12 Skills → 13 Skills.

### Spec / Issue

- Aether #45 Phase 2 TASK-2.10 (T2.7) — completes `SKILL.md drafted →
  AB pending` partial state. detailed-tasks TASK-019 maps to this entry.
- Per CLAUDE.md `§Skill 变更强制流程`: static benchmark PASS (204 lines
  < 400 warn threshold) + AB benchmark PASS → version bump unblocked.

## [1.10.5] - 2026-05-04

### Documented — runner-side aliyun apt mirror (no plugin functionality change)

Aether ops applied a fix on all 3 heavy runners (heavy-1/2/3): job
containers now get `/etc/apt/sources.list.d/ubuntu.sources` bind-mounted
to a local aliyun-backed file via `container.options` in
`/opt/forgejo-runner/data/config.yaml`. Reason: `archive.ubuntu.com`
unreachable from these nodes (cross-border SYN timeouts; observed
SilkNode CI 871, nexus runs 2304/2306). Mirror picked after benchmarking
tuna/ustc/aliyun/huaweicloud/sjtu/tencent — aliyun won on TCP connect +
TTFB + throughput; tuna/ustc/tencent all hit 5.3s SYN-retry.

This release just documents that fact so projects (and the AI helpers
this plugin wires up) stop adding redundant per-workflow `sed` swaps:

- `references/forgejo-ci-optimization.md`:
  - + Environment fact #7 (the runner-side mechanism, scope, mirror
    selection rationale)
  - + B11 best practice (don't swap apt mirrors in workflows; when a
    workflow-level swap would still be needed)
- `skills/aether-init/references/workflow-templates.md`:
  - + design decision #6 (cross-reference to the above)

No runtime/template changes; existing workflows unaffected.

## [1.10.4] - 2026-05-02

### Changed — `requirements.yaml` `cli.recommended_version` 1.14.0 → 1.15.0

Tracks aether-cli v1.15.0 (Aether main repo PR #76, commit 549b016, tag
`cli-v1.15.0`):

- New `aether volume create --register-only` flag — closes chmod-pgdata
  -bricking residual gap from #31 (v1.14.0)
- Operator opt-in mode skips mkdir+chmod for existing populated volumes
- bash `test -d` guard catches operator-typo at script-execution time
- Mutual exclusion with `--perms`; compatible with `--read-only`
- 4-round 4-agent convergence audit; R3 ≡ R4 verbatim stability
- Backward compatible

Plugin functionality unchanged.

## [1.10.3] - 2026-05-02

### Changed — `requirements.yaml` `cli.recommended_version` 1.13.2 → 1.14.0

Tracks aether-cli v1.14.0 (Aether main repo PR #73, commit 6bc243c, tag
`cli-v1.14.0`):

- New `aether volume create --read-only` flag — emits `host_volume.read_only = true`
- New `aether volume create --perms <octal>` flag — applies `chmod -R <perms>`
  (default 777 preserved for backward compat)
- Closes Aether#31 (chmod-pgdata-bricking trap for fresh volumes)
- 5-round 4-agent convergence audit; R4 ≡ R5 verbatim stability
- Backward compatible — pre-#31 users get identical 1.13.2 behavior when
  flags omitted

Plugin functionality unchanged in this release. Recommendation bump only.

## [1.10.2] - 2026-04-30

### Changed — `requirements.yaml` `cli.recommended_version` 1.13.0 → 1.13.2

Tracks aether-cli v1.13.2 (Aether main repo PR #70, commit fbd5967, tag
`cli-v1.13.2`):

- `aether doctor hardcoded_docker_auth` heuristic refinement: `looksLikeCredential`
  length threshold raised 16 → 20 to drop service-account false positive
  `dockerhub_svc001` (Aether #47, partial close).
- `scripts/migrate-hardcoded-docker-auth.sh` verify-loop timestamp tightening
  (10s grace → 1s clock-skew tolerance) — Aether #48 timestamp portion;
  JobVersion-index portion tracked in Aether #71.

### Added — compatibility matrix row for plugin 1.10.x

`requirements.yaml` `compatibility` matrix extended with explicit `1.10.x`
row: `cli_min: "1.0.0"` / `cli_recommended: "1.13.2"`. Notes summarize the
cumulative doctor enhancements (Aether #47 + #48 + #67 driver filters).

## [1.10.1] - 2026-04-26

### Changed — `requirements.yaml` `cli.recommended_version` 1.11.0 → 1.13.0

Bumps the recommended CLI version so users on autopilot pick up two new
`aether doctor` checks shipped against Aether [#67](https://forgejo.10cg.pub/10CG/Aether/issues/67):

- **`aether doctor docker_root_on_nfs`** (CLI v1.12.0, WARN-level) — leading
  indicator: probes each ready Nomad node's docker daemon `data-root` and
  warns when it sits on the NFS/virtiofs share (`/opt/aether-volumes/`),
  the root cause of the #67 sillyrename trap.
- **`aether doctor docker_disk_pressure`** (CLI v1.13.0, WARN/FAIL) — lagging
  trigger: grades each node by Docker dead-container count.
  WARN ≥ 10, FAIL ≥ 100 (heavy-1 hit 193 on the 2026-04-25 canary).

Together these bracket the #67 maintenance window: leading indicator
surfaces the *exposure* baseline, lagging trigger surfaces the
*symptom* if migration regresses or rollback path is taken. Operators
running the full `aether doctor` report get both signals automatically.

`min_version` unchanged at 1.0.0 (no API breakage; old CLI still works,
just lacks the two new checks).

[skip-benchmark] — informational version-bump only; no Skill content
rewrite, no AB-relevant change. Per CLAUDE.md "纯格式/注释修改: 可跳过".

## [1.10.0] - 2026-04-25

### Changed — aether-init Consul Template hardening (Aether [#61](https://forgejo.10cg.pub/10CG/Aether/issues/61))

- **`skills/aether-init/references/nomad-templates.md`**: all `template {}`
  examples now ship with the **三件套** (three-piece) hardening pattern:
  `wait { min = "10s"; max = "30s" }` + `change_mode = "noop"` +
  `{{ if gt (len $svc) 0 }}` guard. Bare `{{ range service "X" }}` writes
  rendered the integration vulnerable to upstream catalog flaps (root cause
  of SilkNode#207 — REDIS_URL line vanishing during sidecar redis 0-instance
  windows → application restart loop).
- **New brief subsection** "Consul Template 渲染抖动缓解": problem
  statement + three-piece pattern (4 lines) + canonical-guide link.
  Per Round 2 audit canonical-source principle: subsection does NOT
  re-expand noop semantics; defers all detail to canonical guide.
- **`skills/aether-init/references/file-generation.md` +
  `workflow-templates.md`**: cross-references updated to point at
  canonical guide for any template-flap-related guidance.

### AB test result (Phase 3 GATE)

Live cluster GATE PASS (2026-04-25): three-piece pattern empirically
validated. `ab-test-old` (bare range) accrued **77 task restarts** during
10x flap loop; `ab-test-new` (three-piece) accrued **0 restarts**.
Pre-flight self-check (`old_delta=7 ≥ 1`) confirmed flap method drives
the system. Verdict:
`aether-plugin-benchmarks/ab-results/aether-init-hardened-template-2026-04-25/verdict.md`.

### Changed — requirements

- **`.claude-plugin/requirements.yaml`**: `cli.recommended_version` bumped
  from `1.10.0` to `1.11.0` to pick up the new `template_bare_range`
  doctor check shipped in CLI v1.11.0.

### Spec

- `openspec/changes/harden-aether-init-consul-template/`
- post_spec audit converged Round 3 PASS after 3 challenge-mode rounds
  (Round 1: 5 Critical → Round 2: 2 Critical, 7 Major → Round 3: 0)
- Phase ordering: `1 → 3 (GATE) → 2 → 4 → 5` (AB test gates release per
  CLAUDE.md Skill-change rule)

### Cross-repo follow-up

- Aether [#59](https://forgejo.10cg.pub/10CG/Aether/issues/59): external
  repo HCL migration unblocked once this version ships. Detection via
  `aether doctor template_bare_range --json` (CLI v1.11.0+).
- SilkNode [#207](https://forgejo.10cg.pub/10CG/SilkNode/issues/207):
  erratum + archive comments queued for post-release.

## [1.9.0] - 2026-04-24

### Changed — aether-init SKILL references (NFS-virtiofs stateful pattern)

- **`skills/aether-init/references/nomad-templates.md`**: "Docker 服务 +
  持久化存储 — prod" section rewritten to the canonical 3-node
  NFS-virtiofs pattern delivered by Aether [#56](https://forgejo.10cg.pub/10CG/Aether/issues/56):
  prerequisite block with explicit `aether volume create` commands for
  all 3 heavy nodes, `node.class = heavy_workload` constraint guidance,
  `migrate` stanza (`max_parallel=1, health_check=checks, min_healthy_time=30s`)
  for stop-before-start protection, post-deploy verification section,
  explicit antipatterns (`node.unique.name` pin, missing `migrate`,
  class-scope without all-node volume registration).

### AB test result

Blind AB comparison (2026-04-24 session): WITH reference subagent produced
deployable HCL with `node.class = "heavy_workload"`; WITHOUT reference
subagent produced NON-DEPLOYABLE HCL with `node.class = "heavy"` (would
fail scheduling with "computed class ineligible"). See
`aether-plugin-benchmarks/ab-results/2026-04-24/aether-init-issue56/`.

### Changed — requirements

- **`.claude-plugin/requirements.yaml`**: `cli.recommended_version` bumped
  from `1.9.0` to `1.10.0` to pick up the new `host_volume_parity` +
  `orphan_jobs` doctor checks (required by the stateful-job template for
  post-deploy verification).

## [1.8.0] - 2026-04-23

### Changed — aether-init SKILL references (security fix)
- **`skills/aether-init/references/workflow-templates.md`**: removed the
  3 `sed -i "s|__REGISTRY_TOKEN__|${{ secrets.FORGEJO_TOKEN }}|g"` and
  `__REGISTRY_USER__` injection lines from both dev and prod CI
  workflow templates. New projects onboarded via `/aether:init` no
  longer propagate hardcoded PATs into their Nomad job HCLs.
- **`skills/aether-init/references/nomad-templates.md`**: new "私有
  Registry Auth" section shows the `template { env=true }` + `nomadVar`
  + `config.auth.${VAR}` pattern as the canonical credential injection
  model. Closes [#42](https://forgejo.10cg.pub/10CG/Aether/issues/42)
  template-layer propagation.
- **`.claude-plugin/requirements.yaml`**: bumped `cli.recommended_version`
  from `1.8.5` to `1.9.0` to pick up the new `hardcoded_docker_auth`
  doctor check.

### Validation
- Static benchmark: aether-init 382 lines, 1127 words (no regression)
- Functional diff verified: 0 `REGISTRY_TOKEN` sed injections remain;
  5 occurrences of the new `nomadVar` / `DOCKER_AUTH_*` pattern in refs.

## [1.7.5] - 2026-04-21

### Changed — metadata sync (no skill content changes)
- **`.claude-plugin/requirements.yaml`**: bumped `cli.recommended_version`
  from `1.8.4` to `1.8.5` to track CLI release for
  [#38](https://forgejo.10cg.pub/10CG/Aether/issues/38)
  (doctor phantom_allocations false-positive fix + new failed_allocations check).

## [1.7.4] - 2026-04-21

### Changed — metadata sync (no skill content changes)
- **`.claude-plugin/requirements.yaml`**: bumped `cli.recommended_version`
  from `1.8.2` to `1.8.4` to track CLI releases for issues
  [#29](https://forgejo.10cg.pub/10CG/Aether/issues/29) (env set credential
  redaction) and [#28](https://forgejo.10cg.pub/10CG/Aether/issues/28)
  (dev run HCL parsing).

## [1.7.3] - 2026-04-14

### Changed — metadata sync (no skill content changes)
- **`.claude-plugin/requirements.yaml`**: bumped `cli.recommended_version` from
  `1.8.1` → `1.8.2` to track the CLI v1.8.2 release (test coverage boost + health
  checks). Previously Plugin referenced 1.8.1 for 3 commits after CLI shipped 1.8.2,
  misdirecting users during install/upgrade.

No SKILL.md content changed — AB testing skipped per CLAUDE.md "纯格式/注释修改:
可跳过" rule.

## [1.7.2] - 2026-04-11

### Changed — aether-init CLAUDE.md policy injection (US-030)
- **`references/deploy-monitoring-rules.md` 内容重写**: 从中文 "部署监控规则" 整合为与 v1.7.1
  在 4 项目 (SilkNode/Nexus/Kairos/Kino) 标准化一致的**英文** `### CI/CD Monitoring Policy
  (MANDATORY)` 段。内容与 SilkNode CLAUDE.md lines 152-184 经 AC1a 的 4 项已知转换后
  **逐字一致**（heading 级别 `####` → `###`、HTML marker 前缀、incident history 句 generic 化、
  `__JOB_NAME__` 占位符）。
- **首行新增 HTML marker `<!-- aether-ci-policy -->`**: 语言无关的稳定 sentinel，future-proof
  markdown processing。
- **`SKILL.md` Step 1.1c/2.2b 升级**:
  - 检测改为 **triple-fallback grep** `(<!-- aether-ci-policy -->|部署监控规则|CI/CD Monitoring Policy)`
    识别新 marker + legacy Chinese 段 + v1.7.1 英文段
  - 注入位置改为**确定性 EOF append** (blank line + `---` + 章节)，移除"部署节后"启发式
  - **已有 CLAUDE.md 改为 `AskUserQuestion` 询问**再 append，绝不静默覆盖
- **`__JOB_NAME__` 解析从 nomad HCL**: 优先从已生成的 `deploy/nomad-dev.hcl` parse
  `job "<name>" {` 头部（multi-job 用 `grep -m1`），失败时 fallback 到 `${PROJECT_NAME}-dev`
- **文件生成顺序断言**: CLAUDE.md 必须在 `deploy/nomad-dev.hcl` 之后生成（file-generation.md 记录）
- **`SKILL.md` 行数**: 350 → 382 (within 400 warning threshold)

### Quality verification (US-030)
- **4 轮 post_spec audit** by `aria:tech-lead` + `aria:backend-architect` + `aria:qa-engineer`
  (reports in `.aria/audit-reports/post_spec-2026-04-11-round{1,2,3,4}.md`):
  - Round 1: REVISE 3/3 — caught critical dual-injection-path architectural issue (fixed)
  - Round 2: REVISE 2/3 — caught precision issues (R2-A/B/C/D fixed)
  - Round 3: REVISE 2/3 — caught mechanical line-number + heading-level errors (R3-A fixed)
  - Round 4: PASS 2/3 — caught sub-mechanical 2-line wrap defect (R4-1) fixed inline by user override
- **Mechanical Phase 1.4 diff verification**: template + 4 reverse transformations produces
  0-byte diff against SilkNode lines 152-184 (executed pre-release, passed)
- **AB benchmark eval case 3** (new, `ab-suite/aether-init.json`): WITH skill passes 3/3
  critical expectations (HTML marker, 4-step wording, HCL-parsed job name) + medium (EOF
  horizontal rule); WITHOUT skill fails all 3 critical + medium. No regression on existing
  eval case 1 and 2.
- **[✏️ 订正 2026-07-15, 见 Aether [#245](https://forgejo.10cg.pub/10CG/Aether/issues/245)] Drift check 声称不实**: 本条目原文声称
  "**Drift check** (`check_template_drift` in `static-benchmark.sh`) wired to CI
  gate — runs on every `static-benchmark --skill aether-init` invocation."
  实测证伪: `static-benchmark.sh` 唯一函数是 `check_cost`（112 行），
  `check_template_drift` 从未实现，没有任何自动化漂移守护接入 CI gate。
  `file-generation.md` § HTML marker durability 已同步订正为诚实的"待办"表述；
  marker 保持首行目前仅靠人工约定 + code review 维持。

### Version (aria spec: PATCH per "现有能力整合升级")
- Scope is strictly "rewrite 1 template + update 2 existing skill files" — no new skill steps,
  no new reference files, no new user-facing capability. MINOR 1.8.0 would over-version.
- VERSION, plugin.json, marketplace.json, hooks.json, requirements.yaml, README.md,
  CHANGELOG.md 全部 7 个文件同步至 1.7.2.

### Related
- **OpenSpec change**: `openspec/changes/2026-04-10-init-inject-ci-policy/` (to be archived
  post-release)
- **User Story**: [US-030](../../docs/requirements/user-stories/US-030.md)

## [1.7.1] - 2026-04-10

### Added
- **`references/forgejo-ci-optimization.md` § CI Monitoring Policy** — new
  mandatory section codifying the push → CI → deploy-watch → report chain
  as the single most important operational rule for Aether projects.
  Documents the 4-step workflow, anti-shortcuts to avoid, and explains
  the policy vs. automation layer separation (CLAUDE.md policy +
  ci-watch-hook.sh automation).

### Rationale
Audit of 4 production projects (SilkNode / Nexus / Kairos / Kino) revealed
inconsistent coverage: only 1 project had a real policy statement, 1 just
listed commands, and 2 had zero mentions. The hook alone is insufficient
because it only fires under specific conditions (Bash tool, hooks enabled,
plugin installed). This section + upcoming CLAUDE.md updates across the
4 projects encode the policy in both the authoritative reference and in
each project's always-loaded context.

## [1.7.0] - 2026-04-10

### Added
- **New plugin-level `references/` directory** — authoritative cross-skill
  reference resources, accessible via `${CLAUDE_PLUGIN_ROOT}/references/`.
- **`references/forgejo-ci-optimization.md`** — comprehensive Forgejo CI
  optimization and troubleshooting guide for the Aether environment. Covers
  10 anti-patterns (with real error messages), 10 best practices, 4 real
  project case studies (SilkNode 25m→10m41s, Nexus 9m30s→6m43s, Kairos
  13m→4m39s cold, Kino api 6m→2m14s + web 4m46s→1m51s), and an
  error-keyword-driven troubleshooting decision tree.
- Symlink `docs/guides/forgejo-ci-optimization.md` in the main Aether repo
  pointing to the plugin-level guide (single source of truth).

### Changed
- **aether-init / workflow-templates.md**: substantial rewrite (242→477
  lines). All Docker templates now include: explicit `driver: docker` in
  buildx, DNS fix for internal registry, build+push split pattern, polling
  deployment verification. Documents why each pattern is necessary.
- **aether-init / dockerfile-templates.md**: substantial rewrite (91→250
  lines). Node templates: npm mirror (`registry.npmmirror.com`) + 3x retry
  loop + `# syntax=docker/dockerfile:1`. Python templates: pip mirror
  (`mirrors.aliyun.com`) + retry. All templates use `COPY --chown` instead
  of `RUN chown -R`. Added multi-stage + proper layer caching for every
  language. Node default version aligned to 22.
- **aether-init/SKILL.md**: added cross-skill reference row in the 详细参考
  table pointing to `${CLAUDE_PLUGIN_ROOT}/references/forgejo-ci-optimization.md`.
- **aether-ci/SKILL.md**: added 1-line blockquote in 故障处理 section
  pointing to the optimization guide for Aether-specific error modes
  (TLS / EIDLETIMEOUT / operation not supported / docker.1ms.run tag missing
  / invalid pkt-len). Pure additive change — [skip-benchmark qualified].

### Quality verification
- AB benchmark for aether-init: **WITH skill wins decisively** (3/3 critical,
  5/5 aether-specific vs WITHOUT 1/3 critical, 1/5 aether-specific). No
  regression. Results in `ab-results/2026-04-10/aether-init/`.
- Static benchmark: aether-init 344→350 lines (OK), aether-ci 397→399 lines
  (OK, 1 line under warning threshold).

## [1.6.6] - 2026-04-09

### Changed
- **aether-deploy-watch**: SKILL.md optimized from 486→393 lines. Extracted
  4 procedural sections to `references/` directory (CI diagnosis, phantom alloc,
  polling patterns, CronCreate integration). No content changes. [skip-benchmark]
- **requirements.yaml**: `cli.recommended_version` updated to 1.7.0.

## [1.6.5] - 2026-04-09

### Changed
- **requirements.yaml**: Update `cli.recommended_version` from 1.6.0 to 1.6.1.

## [1.6.4] - 2026-04-08

### Changed
- **aether-ci Skill v2.1.0**: Three-tier strategy chain (API → SSH → local repro),
  run list table display, 15 failure patterns (was 9) with 7 categories,
  SSH degradation handling, `--search` log capability.
  AB tested: WITH_BETTER (3/3 evals, 60/60 vs 51/60).

## [1.6.3] - 2026-04-08

### Changed
- **aether-ci Skill v2.0.0**: Step 2 uses `aether ci status --json` (CLI v1.5.0+),
  new Step 2a remote log reading via `aether ci logs`, expanded error patterns
  (docker build, dependency install, timeout split). AB tested: WITH_BETTER (20/20 vs 17/20).
- Compacted CronCreate section (359→315 lines, under 400 guard).

## [1.6.2] - 2026-04-03

### Added
- **benchmark-aggregate-hook**: PostToolUse hook that detects AB test result commits
  and reminds to run `aggregate-results.py` to update OVERALL_BENCHMARK_SUMMARY.md.
  Prevents summary staleness after AB testing sessions.

## [1.6.1] - 2026-04-01

### Changed
- **aether-status**: Complete SKILL.md redesign (v2.0.0). Investigation-first approach
  replaces checklist-driven format. 314→118 lines. Adds mandatory Consul depth checks,
  severity grading, investigation signal mapping. AB test: WITH win rate 0%→100%.

## [1.6.0] - 2026-04-01

### Added
- **aether-deploy-watch**: Phantom alloc detection in Step 3 timeout path.
  When health checks time out, fetches TaskStates for each "running" alloc
  to detect containers dead at Docker level but reported running by Nomad (Issue #12).
- **deploy-doctor**: Phantom alloc detection in allocation analysis step.
  Verifies TaskStates depth for running allocations, identifies Docker event
  stream disconnection as root cause, suggests alloc stop or node drain.

## [1.5.1] - 2026-03-31

### Fixed
- **aether-deploy-watch**: Add CI status diagnostic when image not found or deploy
  times out (Aether#9). Distinguishes cancelled CI (superseded by newer push) from
  real failures via Forgejo Actions Tasks API. Prevents false "Runner resource leak"
  diagnosis and destructive `docker network prune` suggestions.

### Added
- **AB eval**: New eval-6 `rapid-push-cancelled-ci-misdiagnosis` for deploy-watch

## [1.5.0] - 2026-03-31

### Added
- **aether-report**: New skill for reporting bugs and feature requests to Aether
  maintainers. Auto-routes to Forgejo (internal users) or GitHub (external users).
  Collects environment context, enforces privacy review before submission.

## [1.4.0] - 2026-03-31

### Changed
- **aether-deploy-watch**: Complete v2.0.0 rewrite — 4-step pipeline orchestrator
  with direct Nomad/Consul API calls for control flow
  - Step 0: Context resolution (job name, SHA, registry)
  - Step 1: Image verification via forgejo wrapper
  - Step 2: Deploy convergence via Nomad deployments API
  - Step 3: Health verification via Consul health API (2 consecutive checks)
  - Two modes: post-push pipeline (--version) and spot-check
- **ci-watch-hook**: Added job_name + expected_image to state file; CI success
  now triggers deploy-watch automatically
- **aether-ci**: CronCreate prompt updated to invoke deploy-watch on CI success
- **cli.recommended_version**: 0.9.0 → 1.0.0

### Fixed
- **IP addresses**: Fixed 60+ hardcoded 192.168.1.x → 192.168.69.x across 16 files
  (agents, skills, references). PVE address 192.168.1.11 preserved.

## [1.3.2] - 2026-03-28

### Fixed
- **aether-init**: Inject CLAUDE.md rules for existing projects (not just new ones)

## [1.3.1] - 2026-03-27

### Added
- **aether-init**: Phase 2 自动注入部署监控规则到项目 CLAUDE.md (Closes aether-plugin#1)
- **aether-init/references**: deploy-monitoring-rules.md 模板 (含占位符替换规则)

## [1.3.0] - 2026-03-26

### Changed
- **cli.min_version**: 0.7.0 → 0.9.0 (CLI deploy execution now functional)
- **cli.recommended_version**: 0.8.0 → 0.9.0

### Note
- v1.2.2 contained new features (Consul DNS guidance) that should have been a MINOR bump. Per VERSIONING.md, already-published version numbers are not modified. v1.3.0 corrects the version sequence.

## [1.2.2] - 2026-03-25

### Added
- **aether-init**: Consul DNS service discovery guidance — detect DATABASE/REDIS/MONGO deps, recommend `{svc}.service.consul` FQDN
- **aether-init/references**: HCL env block examples with `.service.consul` connection strings
- **aether-doctor**: DNS resolution diagnostic step (`dig consul.service.consul`)
- **aether-setup**: DNS status line in `--show` output

### Fixed
- **aether-dev**: Complete v1.1.0 config migration — replaced `.env` + `endpoints.*` with `.aether/config.yaml` + `cluster.*` two-tier pattern (lines 349-368)

### Quality
- All 4 modified Skills pass static-benchmark (init: 315 lines, dev: 383, setup: 293, doctor: 147)
- OpenSpec: consul-dns-service-discovery (US-013)

## [1.2.1] - 2026-03-25

### Fixed
- **cli-guard-hook.sh**: Platform-aware CLI download — auto-detect OS/arch via `uname`, no longer depends on `jq`. Fixes macOS users downloading wrong-platform (linux) binary.
- **detect-cli.sh**: Same platform-aware fix for `print_install_guidance()`.
- **cli-installation.md**: GitHub mirror as primary download (no CF auth needed), Forgejo as fallback. Manual install now covers both arm64 and amd64 for macOS.

### Improved
- **aether-volume SKILL.md**: Added safety guarantees table, common failure patterns with SSH diagnostics
- **aether-setup SKILL.md**: Enhanced config priority chain visualization, Consul auto-derivation, diagnostic framework

### Quality
- AB test: 10 Skills × 20 evals, WITH **100%** win rate (20/20), up from 90%
- volume e1: TIE → WITH_BETTER, setup e1: TIE → WITH_BETTER

## [1.2.0] - 2026-03-24

### Added
- **aether-ci**: CI status query, failure diagnosis, auto-monitoring (PostToolUse Hook + CronCreate polling)
- **ci-watch-hook.sh**: PostToolUse Hook auto-detects `git push` and triggers CI monitoring
- **hooks.json**: Migrated to standard Claude Code command format (PreToolUse + PostToolUse)

### Improved
- **aether-setup**: Added config priority chain explanation and richer cluster detail (Docker versions, host volumes per node)
- **aether-volume**: Added idempotency check before create and post-create SSH directory verification

### Quality
- AB test: 10 Skills × 20 evals, WITH 90% win rate (18/20), zero regressions
- WITH_BETTER: 8/10, MIXED: 2/10 (setup, volume — simple task ceiling), WITHOUT: 0/10
- Hook E2E validation: 69/69 checks passed

## [1.1.0] - 2026-03-19

### Added (2026-03-24)
- **aether-ci**: CI status query, failure diagnosis, and auto-monitoring skill
  - Forgejo commit status API integration for CI state checking
  - Local reproduction of failed CI jobs (go test / golangci-lint)
  - Error pattern matching and fix suggestions
  - Watch mode with CronCreate-based polling
- **PostToolUse Hook** (`ci-watch-hook.sh`): Auto-detect `git push` and trigger CI monitoring
- **hooks.json migrated** to standard Claude Code command format (both PreToolUse + PostToolUse)

### Improved (AB test validated)
- **aether-status**: Removed prescriptive curl/jq templates, added exploration dimension guidance. WITHOUT_BETTER → WITH_BETTER (2-0)
- **aether-deploy**: Added registry API fallback when docker CLI unavailable, failure diagnosis guidance. MIXED → WITH_BETTER (2-0)
- **aether-rollback**: Expanded to 3 rollback strategies (Nomad revert / Git resubmit / emergency deploy), added execution confirmation step, structured root cause analysis. MIXED → WITH_BETTER (2-0)
- **aether-doctor**: Enhanced SSH diagnostics with 5-layer diagnostic framework (network → name resolution → auth → remote-side → application). MIXED → WITH_BETTER (2-0)
- **aether-setup**: Streamlined from 410 to 213 lines, removed boilerplate bash functions, added connection failure diagnostic guide. MIXED → MIXED (stable)

### Fixed
- **Config schema**: All 5 skills corrected endpoints.* → cluster.* in config read sections

### Quality
- AB test: 9 Skills × 18 evals, WITH 94.4% win rate (up from 50%)
- WITH_BETTER: 8/9 skills, MIXED: 1/9 (setup), WITHOUT_BETTER: 0/9
- Zero regressions across two optimization rounds

## [1.0.0] - 2026-03-18

### Milestone
- First stable release with full AB test baseline validation

### Added
- **skill-benchmark**: AB comparison testing skill for quality verification
- **Error handling improvements**: 5 skills upgraded (status, init, setup, dev, cli-guard)
- **Deep investigation guidance**: aether-status now encourages exploration beyond basic queries

### Fixed
- **aether-setup**: Config schema corrected (endpoints.* → cluster.*)
- **aether-setup**: Project config path corrected (.env → .aether/config.yaml)
- **aether-volume CLI**: Idempotency check for existing volumes

### Quality
- AB test baseline: 9 Skills × 18 evals, WITH 50% win rate
- 3 real bugs discovered and fixed through AB testing
- Benchmark infrastructure moved to aether-plugin-benchmarks/

## [0.9.1] - 2026-03-13

### Fixed
- **Dual Authentication Support**: Forgejo API requires both CF Token AND Forgejo Token
  - Added `FORGEJO_TOKEN` to authentication headers
  - Updated `fetch_release_with_cf_auth()` to include Forgejo API token

### Test Results
| Auth Method | HTTP Code | Notes |
|-------------|-----------|-------|
| None | 302 | CF redirect |
| Forgejo Token only | 302 | CF blocked |
| CF Token only | 403 | Forgejo rejected |
| **CF + Forgejo Token** | **200** | **Success!** |

### Configuration Required
```bash
# CF Access Service Token (aria spec)
export CF_ACCESS_CLIENT_ID="your-client-id"
export CF_ACCESS_CLIENT_SECRET="your-client-secret"

# Forgejo API Token
export FORGEJO_TOKEN="your-forgejo-token"
```

## [0.9.0] - 2026-03-13

### Added
- **Cloudflare Access Token Detection**: Smart token detection before Forgejo API requests
  - Check environment variables: `CF_ACCESS_TOKEN`, `CLOUDFLARE_ACCESS_TOKEN`, `CF_AUTHORIZATION`
  - Check config files: `~/.cloudflare/access-token`, `~/.cfaccess`, `~/.config/cloudflare/access-token`
  - Auto-detect when CF authentication is required (302/401 response)

### Changed
- **CLI Installation Workflow**: Prioritize existing CF token configuration
  - `scripts/detect-cli.sh`: Added `detect_cf_access_token()`, `fetch_release_with_cf_auth()`, `check_cf_access_required()` functions
  - `skills/aether-doctor/references/cli-installation.md`: Updated installation flow with CF token detection
  - `.claude-plugin/requirements.yaml`: Added complete `cf_access` configuration section

### Workflow
**Before (Fallback immediately):**
```
Forgejo API → 302 → 放弃，尝试源码构建
```

**After (Check CF token first):**
```
Forgejo API → 302 → 检查本地 CF Token
                          ├─ 有 Token → 使用认证请求下载
                          └─ 无 Token → 显示配置引导
```

### Configuration
```yaml
# .claude-plugin/requirements.yaml
cli:
  cf_access:
    env_vars:
      - "CF_ACCESS_TOKEN"
      - "CLOUDFLARE_ACCESS_TOKEN"
      - "CF_AUTHORIZATION"
    config_files:
      - "~/.cloudflare/access-token"
      - "~/.cfaccess"
      - "~/.config/cloudflare/access-token"
    cookie_name: "CF_Authorization"
    instructions: |
      1. 在浏览器中访问 https://forgejo.10cg.pub 并完成 CF 认证
      2. 打开开发者工具 → Application → Cookies
      3. 复制 CF_Authorization cookie 值
      4. 设置环境变量: export CF_ACCESS_TOKEN="your-token"
```

### How to Get CF Token
```bash
# Method 1: Environment variable (recommended)
export CF_ACCESS_TOKEN="your-token-here"

# Method 2: Config file
echo "your-token-here" > ~/.cfaccess
chmod 600 ~/.cfaccess

# Steps to obtain token:
# 1. Visit https://forgejo.10cg.pub in browser and complete CF authentication
# 2. Open DevTools (F12) → Application → Cookies
# 3. Copy the CF_Authorization cookie value
```

## [0.9.0] - 2026-03-13

### Added
- **Cloudflare Access Token Detection**: Smart token detection before Forgejo API requests
  - Check environment variables: `CF_ACCESS_TOKEN`, `CLOUDFLARE_ACCESS_TOKEN`, `CF_AUTHORIZATION`
  - Check config files: `~/.cloudflare/access-token`, `~/.cfaccess`, `~/.config/cloudflare/access-token`
  - Auto-detect when CF authentication is required (302/401 response)

### Changed
- **CLI Installation Workflow**: Prioritize existing CF token configuration
  - `scripts/detect-cli.sh`: Added `detect_cf_access_token()`, `fetch_release_with_cf_auth()`, `check_cf_access_required()` functions
  - `skills/aether-doctor/references/cli-installation.md`: Updated installation flow with CF token detection
  - `.claude-plugin/requirements.yaml`: Added complete `cf_access` configuration section

### Workflow
**Before (Fallback immediately):**
```
Forgejo API → 302 → 放弃，尝试源码构建
```

**After (Check CF token first):**
```
Forgejo API → 302 → 检查本地 CF Token
                          ├─ 有 Token → 使用认证请求下载
                          └─ 无 Token → 显示配置引导
```

### Configuration
```yaml
# .claude-plugin/requirements.yaml
cli:
  cf_access:
    env_vars:
      - "CF_ACCESS_TOKEN"
      - "CLOUDFLARE_ACCESS_TOKEN"
      - "CF_AUTHORIZATION"
    config_files:
      - "~/.cloudflare/access-token"
      - "~/.cfaccess"
      - "~/.config/cloudflare/access-token"
    cookie_name: "CF_Authorization"
```

## [0.8.9] - 2026-03-12

### Added
- **PreToolUse Hook for CLI Auto-Detection** (P2 Optimization):
  - `skills/aether-cli-guard/SKILL.md` - Hook skill documentation
  - `scripts/cli-guard-hook.sh` - Executable hook script
  - Automatic CLI detection before executing aether commands
  - User-friendly install guidance when CLI is missing

- **Hook Configuration** (`hooks.json`):
  - PreToolUse hook with Bash tool filter
  - Command pattern matching for `aether`
  - Graceful fallback with install instructions

### Changed
- **Automated CLI Detection Flow**:
  ```
  User runs: aether volume list
       ↓
  Hook triggers: CLI detection
       ↓
  ├─ CLI found → Command executes
  └─ CLI missing → Block + Show install guide
  ```

### User Experience
**Before (Manual):**
```
User: 运行 aether volume list
Claude: ❌ CLI 未安装...
```

**After (Automatic):**
```
User: 运行 aether volume list
Hook: 🔍 检测 aether CLI...
      ❌ 未找到 → 显示安装引导
      ✅ 已找到 → 命令继续执行
```

### Hook Skill
| 属性 | 值 |
|------|-----|
| Name | aether-cli-guard |
| Type | Hook Skill (内部) |
| Trigger | PreToolUse + Bash + "aether" |
| User-invocable | false |

## [0.8.8] - 2026-03-12

### Added
- **Shared CLI Detection Scripts** (`scripts/`):
  - `detect-cli.sh` - Full CLI detection with version checking and install guidance
  - `cli-functions.sh` - Lightweight functions for sourcing in skills

### Changed
- **Unified CLI Pre-check**: All CLI-dependent skills now use shared detection:
  ```bash
  source "${CLAUDE_PLUGIN_ROOT}/scripts/cli-functions.sh"
  require_aether_cli || exit 1
  ```

- **Skills updated**:
  - `aether-deploy` v0.3.0 - Uses shared script, gets CLI path
  - `aether-dev` v0.3.0 - Uses shared script
  - `aether-rollback` v0.3.0 - Uses shared script
  - `aether-init` v0.5.0 - Uses shared script
  - `aether-volume` v1.3.0 - Uses shared script

### Benefits
- **DRY**: Single source of truth for CLI detection logic
- **Consistency**: Same error messages across all skills
- **Maintainability**: Update detection in one place
- **Extensibility**: Easy to add new detection paths

## [0.8.7] - 2026-03-12

### Changed
- **Unified CLI Dependency Declaration**: Standardized `dependencies.cli` frontmatter across all skills
  - Consistent format: `required`, `min_version`, `note`
  - Clear guidance when CLI is missing: "请运行 /aether:doctor 安装 CLI"

- **Skills updated with CLI pre-check section**:
  - `aether-deploy` v0.2.0 - Added CLI detection and guidance
  - `aether-dev` v0.2.0 - Added CLI detection and guidance
  - `aether-rollback` v0.2.0 - Added CLI detection and guidance
  - `aether-init` v0.4.0 - Updated dependencies format
  - `aether-volume` v1.2.0 - Updated dependencies format
  - `aether-status` v1.1.0 - Marked CLI as optional (API-only mode)
  - `aether-deploy-watch` v1.2.0 - Marked CLI as not required
  - `aether-doctor` v2.1.0 - Marked as CLI installer/provider

- **requirements.yaml**: Updated with complete skill dependency matrix

### CLI Dependency Matrix

| Skill | CLI Required | Min Version | Notes |
|-------|-------------|-------------|-------|
| aether-doctor | No | - | CLI installer |
| aether-init | Yes | 0.7.0 | Project setup |
| aether-volume | Yes | 0.7.0 | Volume management |
| aether-deploy | Yes | 0.7.0 | Production deploy |
| aether-dev | Yes | 0.7.0 | Dev deployment |
| aether-rollback | Yes | 0.7.0 | Rollback |
| aether-status | No | - | API-only mode |
| aether-deploy-watch | No | - | Uses aether-status |
| aether-setup | No | - | Config only |

## [0.8.6] - 2026-03-12

### Changed
- **Skills Optimization**: Refactored skills using Progressive Disclosure pattern
  - `aether-doctor` SKILL.md: 1370 → 146 lines (89% reduction)
  - `aether-init` SKILL.md: 529 → 156 lines (70% reduction)
  - `aether-volume` SKILL.md: 461 → 149 lines (68% reduction)

### Added
- **aether-volume references/** (5 files):
  - `command-details.md` - Full command parameters and examples
  - `ssh-authentication.md` - SSH authentication methods
  - `nomad-configuration.md` - Generated configuration and Job usage
  - `troubleshooting.md` - Common issues and solutions
  - `best-practices.md` - Best practices and project type recommendations

- **aether-doctor references/** (6 files):
  - `cli-installation.md` - CLI installation workflows
  - `cluster-validation.md` - Cluster topology and validation
  - `ssh-diagnostics.md` - SSH checks and fixes
  - `ci-configuration.md` - CI/CD configuration checks
  - `environment-cache.md` - Cache format and validity
  - `output-examples.md` - Diagnostic output examples

- **aether-init references/** (2 new files):
  - `project-analysis.md` - Project detection and decision logic
  - `file-generation.md` - File generation commands

### Design Principle

Following skill-creator best practices:
- **SKILL.md** - Core workflow only (< 350 lines recommended)
- **references/** - Detailed content loaded on demand
- **scripts/** - Executable code
- **assets/** - Templates and resources

## [0.8.5] - 2026-03-12

### Changed
- **CLI Installation Directory**: Changed from `/usr/local/bin/` to `~/.aether/`
  - No longer requires `sudo` privileges
  - CLI installed alongside `config.yaml` for unified management
  - Skills auto-detect CLI location (PATH → ~/.aether/)

- `aether-doctor` skill (v1.4.0 → v1.5.0):
  - Added multi-path CLI detection logic
  - Updated all installation scripts to use `~/.aether/`
  - Enhanced error messages with correct paths

### CLI Detection Priority

```bash
# 1. Check PATH
if command -v aether &> /dev/null; then
  AETHER_CLI="aether"
# 2. Check ~/.aether/
elif [ -f "$HOME/.aether/aether" ]; then
  AETHER_CLI="$HOME/.aether/aether"
fi
```

### Installation Paths

| Platform | Old Path | New Path |
|----------|----------|----------|
| Linux/macOS | `/usr/local/bin/aether` | `~/.aether/aether` |
| Windows | `%USERPROFILE%\aether.exe` | `%USERPROFILE%\.aether\aether.exe` |

### Directory Structure

```
~/.aether/
├── config.yaml        # Aether 配置文件
├── environment.yaml   # 环境状态缓存
└── aether[.exe]       # CLI 二进制文件
```

## [0.8.4] - 2026-03-12

### Added
- **Complete CLI Installation Workflow**: Enhanced `aether-doctor` (v1.4.0) with full installation support
  - Automatic installation from Forgejo releases (方案 A)
  - Source build fallback (方案 B)
  - Platform-specific manual installation commands (方案 C)
  - Specify version installation option

- **requirements.yaml**: Complete CLI dependency configuration
  - Release API URLs (latest and versioned)
  - Tag format: `aether-cli/v{VERSION}`
  - Binary naming: `aether-{OS}-{ARCH}[.exe]`
  - Supported platforms matrix (Linux/macOS/Windows, amd64/arm64)

### Changed
- `aether-doctor` skill (v1.3.0 → v1.4.0):
  - Fixed download URLs to use correct Aether releases API
  - Updated binary naming format documentation
  - Added Windows `.exe` suffix handling
  - Enhanced interactive installation with version selection

- Removed invalid `cli` field from `plugin.json` (caused installation error)
- Moved CLI requirements to `requirements.yaml` and skill frontmatters

### Fixed
- **CLI Release Workflow**: Fixed ldflags variable name (`main.version` → `main.Version`)
  - Binary version now correctly embedded at build time
  - Affects `.forgejo/workflows/cli-release.yml`

### Configuration

```yaml
# .claude-plugin/requirements.yaml
cli:
  min_version: "0.7.0"
  recommended_version: "0.7.0"
  release_api: "https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases"
  tag_format: "aether-cli/v{VERSION}"
  binary_format: "aether-{OS}-{ARCH}"
  platforms:
    - { os: linux, arch: amd64, binary: "aether-linux-amd64" }
    - { os: linux, arch: arm64, binary: "aether-linux-arm64" }
    - { os: darwin, arch: amd64, binary: "aether-darwin-amd64" }
    - { os: darwin, arch: arm64, binary: "aether-darwin-arm64" }
    - { os: windows, arch: amd64, binary: "aether-windows-amd64.exe" }
```

### Release Source

| Item | Value |
|------|-------|
| Release API | `https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases` |
| Latest | `.../releases/latest` |
| Versioned | `.../releases/tags/aether-cli/v{VERSION}` |

## [0.8.3] - 2026-03-09

### Added
- **CLI Version Compatibility**: Plugin now defines minimum CLI version requirement
  - `plugin.json` includes `cli.minVersion` and `cli.recommendedVersion` fields
  - `aether-doctor` (v1.3.0) checks CLI version compatibility

### Changed
- `aether-doctor` skill: Enhanced CLI installation support
  - Added version compatibility check (Plugin v0.8.x requires CLI >= 0.7.0)
  - Added automatic installation flow (方案A)
  - Added manual installation commands (方案C)
  - Interactive installation prompts when CLI not found or incompatible

### Configuration
```json
// plugin.json
{
  "cli": {
    "minVersion": "0.7.0",
    "recommendedVersion": "0.7.0",
    "downloadUrl": "https://forgejo.10cg.pub/api/v1/repos/10CG/aether-cli/releases/latest"
  }
}
```

## [0.8.1] - 2026-03-08

### Changed
- **Refactored Skill Architecture**: Clear separation between base layer and composition layer
  - `aether-status` (v1.0.0): Enhanced as **base layer** skill
    - Added `--failed` flag: View failed allocations with details
    - Added `--recent` flag: View recent deployments
    - Added `--logs` flag: View allocation logs
    - Added `--watch` flag: Continuous monitoring mode
  - `aether-deploy-watch` (v1.1.0): Refactored as **composition layer** skill
    - Now calls `aether-status` for status queries
    - Focused on monitoring loop, error pattern matching, and fix suggestions
    - Clear documentation of skill relationships

### Architecture
```
aether-status (base layer)├── provides core status queries
├── --failed, --recent, --logs, --watch
│
aether-deploy-watch (composition layer)
├── calls aether-status for status
├── monitoring loop
├── error diagnosis
└── fix suggestions
```

## [0.8.0] - 2026-03-08

### Added
- **NEW Skill**: `aether-deploy-watch` - Post-deploy verification and diagnostics
  - Automatically check Nomad allocation status after CI/CD deployment
  - Collect failed allocation logs and error messages
  - Pattern matching for common deployment failures (image pull, network, auth, etc.)
  - Provide specific fix suggestions based on error patterns
  - Support `--follow` mode for continuous monitoring
  - Support `--timeout` parameter for custom timeout

### Changed
- `aether-doctor` skill: Added CI/CD configuration check (Step 8)
  - Detect CI platform (Forgejo/GitHub/GitLab)
  - Check workflow files for correct secrets usage
  - Identify hardcoded values vs secrets references
  - Provide fix suggestions for incorrect configurations
- `aether-init` workflow templates: Updated to use correct Forgejo secrets
  - Use `secrets.FORGEJO_TOKEN` instead of `secrets.REGISTRY_TOKEN`
  - Use `secrets.FORGEJO_USER` instead of `secrets.REGISTRY_USERNAME`

### Fixed
- CI shows success but Nomad deployment fails - now caught by `aether-deploy-watch`

## [0.7.2] - 2026-03-08

### Added
- `aether-doctor` skill: CI/CD configuration check (Step 8)
  - Detect CI platform (Forgejo/GitHub/GitLab)
  - Check workflow files for correct secrets usage
  - Identify hardcoded values vs secrets references
  - Provide fix suggestions for incorrect configurations
  - Support `--ci` flag for CI-only check

### Changed
- `aether-init` workflow templates: Updated to use correct Forgejo secrets
  - Use `secrets.FORGEJO_TOKEN` instead of `secrets.REGISTRY_TOKEN`
  - Use `secrets.FORGEJO_USER` instead of `secrets.REGISTRY_USERNAME`
  - Nomad address from `secrets.NOMAD_ADDR` instead of hardcoded
  - Added documentation for Forgejo auto-injected secrets

## [0.7.1] - 2026-03-08

### Changed
- `aether-doctor` skill: Major update v1.1.0
  - **Fixed**: Configuration validation logic - no longer uses leader address for comparison
  - **Added**: Complete cluster topology caching (all servers and clients)
  - **Added**: Project-level environment cache (`./.aether/environment.yaml`)
  - **Improved**: Configuration validation checks if address belongs to server list
  - **Improved**: Caches all server nodes with roles (leader/follower)
  - **Improved**: Caches all client nodes with classes and drivers
  - **Improved**: SSH connection tests for all nodes (servers + clients)

### Fixed
- Configuration conflict between multiple projects using same global cache
- Incorrect validation due to RPC port (4647) vs HTTP port (4646) mismatch

## [0.7.0] - 2026-03-07

### Added
- `aether-doctor` skill: Environment diagnostics tool
  - Check aether CLI installation and version
  - Validate configuration file existence and format
  - Test Nomad/Consul cluster connectivity
  - Check SSH key configuration and permissions
  - Test SSH connection to all cluster nodes
  - Collect cluster overview (node types, counts, IPs)
  - Update configuration cache with environment status
  - Provide repair suggestions for common issues

### Changed
- Enhanced environment state caching in config.yaml
- Skills can now read cached environment status before execution
- Better error messages with diagnostic suggestions

## [0.6.0] - 2026-03-07

### Added
- `aether-volume` skill: Host volume management guide
  - Volume creation, listing, and deletion workflows
  - SSH connection and remote execution guidance
  - Dry-run preview and rollback mechanisms

### Changed
- `aether-init` skill: Added Step 2.3 Registry authentication configuration
- Updated to support aether-cli v0.6.0 volume management features
- Enhanced registry integration with platform-specific credentials

## [0.5.0] - 2026-03-06

### Changed
- Updated to support aether-cli v0.5.0 registry auth detection
- Skills now leverage CLI's intelligent credential mapping
- Forgejo users can use `FORGEJO_TOKEN`/`FORGEJO_USER` directly

## [0.2.0] - 2026-02-19

### Added
- `aether-setup` skill: Configure cluster endpoints (global or project-level)
- Configuration discovery: Read from `~/.aether/config.yaml` or project `.env`
- Auto-discovery: Node classes and drivers discovered from Nomad API

### Changed
- `aether-init`: Two-phase workflow (analyze → generate), dev/prod config separation
- All skills: Removed hardcoded cluster info, now use config discovery
- Templates: Use placeholders (`__DOCKER_NODE_CLASS__`, `__REGISTRY__`, etc.)

## [0.1.0] - 2026-02-19

### Added
- Initial release
- `aether-init` skill: Project scaffolding for Aether deployment
- `aether-dev` skill: Dev environment deploy, test jobs, logs
- `aether-status` skill: Cluster and service status query
- `aether-deploy` skill: Production deployment with approval
- `aether-rollback` skill: Production rollback
- `deploy-doctor` agent: Deployment failure diagnostics
- `node-maintenance` agent: Node maintenance orchestration
