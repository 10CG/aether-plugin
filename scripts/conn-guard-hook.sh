#!/usr/bin/env bash
#
# conn-guard-hook.sh — L4 连接串守卫 (Aether #246)
#
# 拦截「内网连接串硬编码集群 IP」被 AI 读出去或写下去的路径。
# 判据全部在 CLI 侧 (aether conn-guard), 本脚本**只做管道** —— 零判据逻辑。
#
# 用法: conn-guard-hook.sh <face>
#   posttooluse  PostToolUse(Bash|Read)  命中则注入事实通报
#   stop         Stop                    命中则阻断一次要求自审
#   observe      PostToolUse(Write|Edit) 只记录到 sink, 不阻断不注入
#
# === fail-open (刻意) ===
# CLI 缺失 / 非零退出 / 超时 / 输出非合法 JSON —— 任一发生即放行 (exit 0)。
# 本 hook 挂在**每一次** Bash/Read/Write/Edit 上, fail-closed 会让 CLI 一崩就
# 瘫痪整个会话。守卫不可用不等于会话不可用。
#
# 注意这与 cli-guard-hook.sh 相反 —— 那个是 fail-closed(exit 1 + 装机引导),
# 因为它只在用户**主动敲 aether 命令**时触发, 阻断代价是一条命令。
#
# === 两个事件的返回契约不同 (2026-09-05 实测, 不是文档转述) ===
#   PostToolUse 注入: {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}
#                     (纯 stdout 无效; decision:block 在此面会被模型识别为
#                      「工具输出通道来的指令」而拒绝执行)
#   Stop 阻断:        {"decision":"block","reason":"…"}
#                     (hookSpecificOutput.ok:false 形式无效)
#
# === 措辞纪律 ===
# 注入文本一律写成**事实通报**而非指令。实测模型对 hook 注入内容有警惕性:
# 命令式措辞会被它当作「工具输出通道的注入」披露甚至拒绝执行。陈述事实让它
# 自己判断, 才是 DD-2「一次自审」的本意。

set -uo pipefail

FACE="${1:-posttooluse}"
OBS_SINK="${AETHER_CONN_GUARD_SINK:-$HOME/.aether/conn-guard-observations.jsonl}"

payload="$(cat)"
[ -n "$payload" ] || exit 0

# 允许显式关闭 (发版为 PARTIAL 时按 EXPERIMENTAL 默认关闭的开关)
[ "${AETHER_CONN_GUARD_DISABLED:-}" = "1" ] && exit 0

# --- 定位 CLI (fail-open 第一道) ---------------------------------------
CLI=""
if command -v aether >/dev/null 2>&1; then
  CLI="$(command -v aether)"
elif [ -x "$HOME/.aether/aether" ]; then
  CLI="$HOME/.aether/aether"
fi
[ -n "$CLI" ] || exit 0

# --- 从 payload 抽取待扫文本 -------------------------------------------
# 用 python3 而非 bash 字符串处理: JSON 解析必须可靠, 且要读
# persistedOutputPath 指向的文件 (tool_response.stdout 有 30,000 字节硬上限,
# 只读 stdout = 对所有 >30KB 输出静默漏检, Phase 0 0.2 实测)。
# 注意: 必须用 python3 -c 传代码 —— 若用 heredoc, heredoc 会占用 python 的 stdin,
# 脚本读到的是自己的源码而不是 payload (本 bug 由冒烟测试抓到, 不是推理出来的)。
_CG_EXTRACT_PY='
import sys, json, os
face = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)

def tool_text(d):
    parts = []
    tr = d.get("tool_response")
    if isinstance(tr, dict):
        parts.append(str(tr.get("stdout") or ""))
        parts.append(str(tr.get("stderr") or ""))
        # 超限输出的完整来源 —— 不读它就等于放过所有大输出 (Phase 0 0.2)
        p = tr.get("persistedOutputPath")
        if p and os.path.isfile(p):
            try:
                with open(p, "r", errors="replace") as f:
                    parts.append(f.read())
            except OSError:
                pass
        if not any(parts):
            parts.append(json.dumps(tr, ensure_ascii=False))
    elif tr is not None:
        parts.append(str(tr))
    return "\n".join(parts)

if face == "stop":
    sys.stdout.write(d.get("last_assistant_message") or "")
elif face == "observe":
    sys.stdout.write(json.dumps(d.get("tool_input") or {}, ensure_ascii=False))
else:
    sys.stdout.write(tool_text(d))
'

text="$(printf '%s' "$payload" | python3 -c "$_CG_EXTRACT_PY" "$FACE" 2>/dev/null)" || exit 0
[ -n "$text" ] || exit 0

# --- 调 CLI 取判定 (fail-open 第二道: 非零退出 / 非法 JSON 都放行) -----
result="$(printf '%s' "$text" | timeout 10 "$CLI" conn-guard --source "$FACE" 2>/dev/null)" || exit 0
count="$(printf '%s' "$result" | python3 -c 'import sys,json
try:
    print(int(json.load(sys.stdin).get("count", 0)))
except Exception:
    print(-1)' 2>/dev/null)" || exit 0
# -1 = 输出非合法 JSON → fail-open
[ "$count" -gt 0 ] 2>/dev/null || exit 0

hosts="$(printf '%s' "$result" | python3 -c 'import sys,json
d=json.load(sys.stdin)
seen=[]
for f in d.get("findings",[]):
    h=f.get("host") or ""
    if h and h not in seen: seen.append(h)
print(", ".join(seen[:5]))' 2>/dev/null)"

emit_json() { python3 -c 'import sys,json; sys.stdout.write(json.dumps(json.loads(sys.argv[1]),ensure_ascii=False))' "$1"; echo; }

case "$FACE" in
  stop)
    # 防循环: 第二次调用时 stop_hook_active 为 true, 无条件放行 (Phase 0 0.1 验证)
    active="$(printf '%s' "$payload" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("stop_hook_active"))
except Exception: print("True")' 2>/dev/null)"
    [ "$active" = "True" ] || [ "$active" = "true" ] && exit 0
    msg="本次回复里出现了硬编码集群 IP 的内网连接串 (host: ${hosts})。集群规范要求内网连接串用 <service>.service.consul —— 钉死的 IP 在服务 reschedule 后会失效。请复核这些值是交付给操作员使用, 还是仅作为示例/反例引用; 若是前者, 改用 consul 名后再结束。"
    emit_json "$(python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]},ensure_ascii=False))' "$msg")"
    ;;
  observe)
    # 只记录, 不阻断不注入。sink 落在 repo 外, 避免脱敏 host 被误提交。
    mkdir -p "$(dirname "$OBS_SINK")" 2>/dev/null
    printf '%s' "$result" | python3 -c '
import sys, json, datetime
sink = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
with open(sink, "a") as f:
    for x in d.get("findings", []):
        # 只写脱敏字段 —— CLI 侧结构上已不含 userinfo, 这里再明示一次意图
        f.write(json.dumps({
            "ts": ts,
            "scheme": x.get("scheme"),
            "host": x.get("host"),
            "port": x.get("port"),
            "face": "write",
        }, ensure_ascii=False) + "\n")
' "$OBS_SINK" 2>/dev/null
    exit 0
    ;;
  *)
    ctx="检测到工具输出中含硬编码集群 IP 的内网连接串 (host: ${hosts})。集群规范是内网连接串用 <service>.service.consul, 钉死的 IP 在服务 reschedule 后会失效。"
    emit_json "$(python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}},ensure_ascii=False))' "$ctx")"
    ;;
esac
exit 0
