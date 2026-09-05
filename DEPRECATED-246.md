# 本分支已废弃 — #246 L4 连接串守卫 (2026-09-05)

> **不要把本分支合进 master, 也不要在 hooks.json 里注册这里的 hook。**
> 保留它只为参考骨架, 不为交付。

## 为什么废弃

Phase 4 强制门判 **FAIL**, #246 已降级关票 —— **放弃实时拦截, 保留检出**。

- 结论评论: https://forgejo.10cg.pub/10CG/Aether/issues/246
- 决策记录 (主仓): `.aria/decisions/246-downgrade-to-detection-2026-09-05.md`

两个假设一个被证伪、一个从未成立:

| 假设 | 状态 |
|---|---|
| **有效性** — hook 注入能改变模型交付物 | ❌ post 0/8。13/13 未察觉钉 IP, 多份明确断言「文件没钉 IP」, 而观测 hook 显示 post 6/8 的工具返回里确实出现过该 IP —— **先验压过了证据** |
| **分发** — 守卫能装到出问题的地方 | ❌ 接入率 6/39 = 15.4%, 且 #241 的触发源不在这 6 个里 |

**hook 触发了 ≠ hook 起作用了。** 本分支的 hook 在真实会话里确实触发 (xtrace 实证,
走到 emit_json, 两种返回都发出过), 结果仍全部 fail —— 拦了等于没拦。

## 判据本身是好的, 失效的是投递机制

`aether conn-guard` 与 `internal/lint.ScanConnStrings` **已合入 aether-cli master
并继续使用**, 定位改为**诊断工具**。它首次全面运行就找出 6 处活的硬编码 IP
(见 Aether #367), 其中含一份 Nomad HCL。

## 这里还有什么值得看

如果将来要写别的 hook, 以下骨架经过实测, 可以参考:

- **四面注册** (Bash / Read / Write|Edit / Stop) 与各面的返回契约差异 ——
  PostToolUse 用 `hookSpecificOutput.additionalContext`, Stop 用 `decision:block`,
  **两者不通用** (Phase 0 实测)
- **fail-open**: CLI 输出非合法 JSON 时 `count=-1` 放行, 绝不因守卫自身故障挡住用户
- **防循环**: `stop_hook_active` 第二次调用无条件放行
- **读 `persistedOutputPath` 而非 `stdout`**: `tool_response.stdout` 有 30,000 字节
  硬上限, 直接读它会在大输出上静默漏检

**但也请一并记住这三条的代价** (它们合起来正是 FAIL 的机制): `reason` 写成结论式
(只给 host 不给原文) · 措辞留了逃逸出口 (「还是仅作为示例/反例引用」) · 阻断只有
一次。对一个先验很强的模型, 这三条各给了一条出路。

## 后续票

- Aether #366 — skill 挂载 (aether-conventions case C), 需 AB 门
- Aether #367 — 首扫发现的 6 处活失败面
