#!/usr/bin/env bash
#
# conn-guard-report.sh — 读写入面观测档, 输出命中计数 (Aether #246 TASK-026)
#
# 观测档由 conn-guard-hook.sh 的 observe 面写入 (PostToolUse Write|Edit)。
# 它记录「AI 把硬编码集群 IP 的连接串**写进文件**」的次数 —— 这个面本期只观测
# 不阻断, 其数据正是二期 (写入面拦截) 所缺的依据。
#
# 用途:
#   1. Phase 4 收尾: 把命中的分子分母写进 CHANGELOG (4.3 必含项之一)
#   2. GA 后 30 天: 命中 >= N (owner 定为 3) 即立二期票
#
# 用法: bash scripts/conn-guard-report.sh [sink 路径] [--json]
set -uo pipefail
SINK="${1:-${AETHER_CONN_GUARD_SINK:-$HOME/.aether/conn-guard-observations.jsonl}}"
JSON=0
[ "${2:-}" = "--json" ] && JSON=1
[ "${1:-}" = "--json" ] && { JSON=1; SINK="${AETHER_CONN_GUARD_SINK:-$HOME/.aether/conn-guard-observations.jsonl}"; }

python3 - "$SINK" "$JSON" <<'PYEOF'
import sys, json, os
from collections import Counter
sink, as_json = sys.argv[1], sys.argv[2] == "1"

if not os.path.isfile(sink):
    out = {"sink": sink, "exists": False, "total": 0, "note": "观测档尚未产生 — GA 前或期内零命中"}
    print(json.dumps(out, ensure_ascii=False, indent=2) if as_json else
          f"观测档不存在: {sink}\n命中总数: 0 (GA 前或期内零命中)")
    sys.exit(0)

rows, bad = [], 0
with open(sink, errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            bad += 1

hosts = Counter(r.get("host") for r in rows if r.get("host"))
schemes = Counter(r.get("scheme") for r in rows if r.get("scheme"))
ts = sorted(r.get("ts") for r in rows if r.get("ts"))
out = {
    "sink": sink,
    "exists": True,
    "total": len(rows),
    "malformed_lines": bad,
    "first_seen": ts[0] if ts else None,
    "last_seen": ts[-1] if ts else None,
    "by_host": dict(hosts.most_common()),
    "by_scheme": dict(schemes.most_common()),
}
if as_json:
    print(json.dumps(out, ensure_ascii=False, indent=2))
else:
    print(f"观测档: {sink}")
    print(f"写入面命中总数: {out['total']}" + (f" (另有 {bad} 行无法解析)" if bad else ""))
    if ts:
        print(f"时间范围: {out['first_seen']} → {out['last_seen']}")
    if hosts:
        print("按 host:")
        for h, n in hosts.most_common():
            print(f"  {h}: {n}")
    if schemes:
        print("按 scheme: " + ", ".join(f"{s}={n}" for s, n in schemes.most_common()))
    print()
    print("二期启动判据: GA 后 30 天内命中 >= 3 即立票 (owner 2026-09-05 定)")
PYEOF
