# Changelog

All notable changes to aether-plugin will be documented in this file.

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
