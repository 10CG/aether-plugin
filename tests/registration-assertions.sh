#!/usr/bin/env bash
#
# registration-assertions.sh — hooks.json 注册形状的机械断言 (Aether #246 TASK-012)
#
# 存在理由: 本仓踩过一次「注册形状静默架空兄弟断言」——
# 给 PostToolUse 加 hook 时若**新建第二个同名 matcher 条目**,
# `select(.matcher=="Bash") | .hooks[0]` 会返回两行, 用 eval 执行取末条退出码,
# 于是断言实际在测新 hook 且**仍然绿**。
#
# 2026-09-05 实测澄清了该现象的层次: 两个同名 matcher 的 hook **执行层面都会跑**
# (互不吞没, 按声明顺序), 劫持只发生在**断言层面**。故本文件防的是断言空洞,
# 不是功能漏挂。
#
# === 执行时机 (重要) ===
# 主仓 CI 不 checkout submodule (checkout 未开 submodules, 且 submodule 是 SSH URL,
# 强行开启有 runner 凭据风险), 本仓自身无 CI。故本脚本**不在任何 CI 里自动跑**。
# 约定: 改 .claude-plugin/hooks.json 后必跑, 且 Phase 5 发版前必跑。
#
# 用法: bash tests/registration-assertions.sh [hooks.json 路径]
# 退出码: 0 全过 / 1 有失败

set -uo pipefail
HJ="${1:-$(dirname "$0")/../.claude-plugin/hooks.json}"
FAILED=0

chk() {
  if [ "$1" = "0" ]; then printf '  OK   %s\n' "$2"; else printf '  FAIL %s — %s\n' "$2" "${3:-}"; FAILED=1; fi
}

q() { python3 -c "
import json,sys
d=json.load(open('$HJ'))
$1
" 2>/dev/null; }

echo "=== 被测: $HJ ==="

# 1. PostToolUse 下 matcher=='Bash' 的条目**恰好 1 个** (防劫持的根本断言)
n=$(q "print(sum(1 for e in d['hooks'].get('PostToolUse',[]) if e.get('matcher')=='Bash'))")
[ "$n" = "1" ] && chk 0 "PostToolUse 的 Bash matcher 条目恰好 1 个" || chk 1 "PostToolUse 的 Bash matcher 条目恰好 1 个" "实际 ${n:-?} 个 — 多条会让 .hooks[0] 选择器返回多行, 静默架空兄弟断言"

# 2. 该 matcher 的首个 hook 仍是原 hook (锚点未被顶掉)
first=$(q "e=[x for x in d['hooks']['PostToolUse'] if x.get('matcher')=='Bash'][0]; print(e['hooks'][0]['command'].split('/')[-1])")
case "$first" in
  ci-watch-hook.sh*) chk 0 "Bash matcher 的 .hooks[0] 仍是 ci-watch (锚点未被顶掉)" ;;
  *) chk 1 "Bash matcher 的 .hooks[0] 仍是 ci-watch" "实际是 ${first:-?}" ;;
esac

# 3. conn-guard 在 Bash matcher 下恰好注册 1 次
n=$(q "e=[x for x in d['hooks']['PostToolUse'] if x.get('matcher')=='Bash'][0]; print(sum(1 for h in e['hooks'] if 'conn-guard-hook.sh' in h['command']))")
[ "$n" = "1" ] && chk 0 "conn-guard 在 Bash matcher 下恰好 1 次" || chk 1 "conn-guard 在 Bash matcher 下恰好 1 次" "实际 ${n:-?} 次"

# 4. Read 面已注册 (DD-1 承诺主面含 Read; 漏掉则直接 Read 打开 home 目录文件即绕过)
n=$(q "print(sum(1 for e in d['hooks'].get('PostToolUse',[]) if e.get('matcher')=='Read' for h in e['hooks'] if 'conn-guard-hook.sh' in h['command']))")
[ "$n" = "1" ] && chk 0 "Read matcher 下 conn-guard 恰好 1 次" || chk 1 "Read matcher 下 conn-guard 恰好 1 次" "实际 ${n:-?} 次 — DD-1 承诺的主面缺一半"

# 5. Stop 面已注册 (自审档的唯一载体)
n=$(q "print(sum(1 for e in d['hooks'].get('Stop',[]) for h in e['hooks'] if 'conn-guard-hook.sh' in h['command']))")
[ "$n" = "1" ] && chk 0 "Stop 下 conn-guard 恰好 1 次" || chk 1 "Stop 下 conn-guard 恰好 1 次" "实际 ${n:-?} 次"

# 6. 写入面用**单个** matcher (spec 定死, 不拆成 Write / Edit 两条)
n=$(q "print(sum(1 for e in d['hooks'].get('PostToolUse',[]) if e.get('matcher') in ('Write|Edit','Edit|Write')))")
[ "$n" = "1" ] && chk 0 "写入面观测档用单个 matcher" || chk 1 "写入面观测档用单个 matcher" "实际 ${n:-?} 个"

# 7. 三个 manifest 的组件计数一致, 且与实际数量相符
D="$(dirname "$HJ")"
actual_skills=$(ls -d "$D/../skills/"*/ 2>/dev/null | wc -l)
actual_hooks=$(q "print(len({h['command'].split('/')[-1].split()[0] for ev in d['hooks'].values() for e in ev for h in e['hooks']}))")
for f in hooks.json plugin.json marketplace.json; do
  s=$(grep -o '[0-9]*个 Skills' "$D/$f" 2>/dev/null | head -1 | grep -o '[0-9]*')
  h=$(grep -o '[0-9]*个 Hooks' "$D/$f" 2>/dev/null | head -1 | grep -o '[0-9]*')
  if [ "$s" = "$actual_skills" ] && [ "$h" = "$actual_hooks" ]; then
    chk 0 "$f 计数与实际相符 (${s} skills / ${h} hooks)"
  else
    chk 1 "$f 计数与实际相符" "写 ${s:-?} skills/${h:-?} hooks, 实际 ${actual_skills}/${actual_hooks}"
  fi
done

echo
[ "$FAILED" = "0" ] && echo "全部通过" || echo "有断言失败"
exit "$FAILED"
