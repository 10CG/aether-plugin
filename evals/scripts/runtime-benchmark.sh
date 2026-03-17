#!/bin/bash
# Runtime Benchmark - 限速运行时触发测试
# 用法: ./runtime-benchmark.sh [--skill <name>] [--delay <seconds>] [--workers <n>]
#
# 使用 skill-creator 的 run_eval.py 逐个测试 Skill 触发准确率
# 默认: 串行执行 (1 worker)，每个查询间隔 3 秒，避免 529 限流

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="$PLUGIN_DIR/skills"
EVALS_DIR="$PLUGIN_DIR/evals"
RUNTIME_DIR="$EVALS_DIR/runtime"
RESULTS_DIR="$RUNTIME_DIR/results"
SKILL_CREATOR_DIR="/home/dev/.claude/plugins/cache/claude-plugins-official/skill-creator/78497c524da3/skills/skill-creator"

# 默认参数: 保守限速
WORKERS=1
TIMEOUT=60
DELAY=3
RUNS_PER_QUERY=1
TARGET_SKILL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skill) TARGET_SKILL="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --workers) WORKERS="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --runs) RUNS_PER_QUERY="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--skill <name>] [--delay <sec>] [--workers <n>]"
            echo ""
            echo "Options:"
            echo "  --skill <name>   Test only this skill (default: all)"
            echo "  --delay <sec>    Delay between skills (default: 3)"
            echo "  --workers <n>    Parallel workers per skill (default: 1)"
            echo "  --timeout <sec>  Timeout per query (default: 60)"
            echo "  --runs <n>       Runs per query (default: 1)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$RESULTS_DIR"

# 检查依赖
if ! command -v claude &>/dev/null; then
    echo "Error: claude CLI not found in PATH" >&2
    exit 1
fi

if [ ! -f "$SKILL_CREATOR_DIR/scripts/run_eval.py" ]; then
    echo "Error: skill-creator run_eval.py not found" >&2
    exit 1
fi

export PYTHONPATH="$SKILL_CREATOR_DIR:${PYTHONPATH:-}"

DATE=$(date +%Y-%m-%d)
REPORT_FILE="$RESULTS_DIR/${DATE}-runtime.yaml"

echo "# Runtime Benchmark Report"
echo "# Generated: $DATE"
echo "# Workers: $WORKERS | Delay: ${DELAY}s | Timeout: ${TIMEOUT}s | Runs/query: $RUNS_PER_QUERY"
echo ""
echo "date: \"$DATE\""
echo "type: runtime-trigger"
echo "config:"
echo "  workers: $WORKERS"
echo "  timeout: $TIMEOUT"
echo "  delay: $DELAY"
echo "  runs_per_query: $RUNS_PER_QUERY"
echo ""
echo "results:"

run_skill_eval() {
    local skill_name="$1"
    local eval_file="$RUNTIME_DIR/${skill_name}.json"
    local skill_path="$SKILLS_DIR/$skill_name"
    local output_file="$RESULTS_DIR/${DATE}-${skill_name}.json"

    if [ ! -f "$eval_file" ]; then
        echo "  $skill_name:" >&2
        echo "    status: skipped" >&2
        echo "    reason: no eval file at $eval_file" >&2
        return
    fi

    if [ ! -f "$skill_path/SKILL.md" ]; then
        echo "  $skill_name:" >&2
        echo "    status: skipped" >&2
        echo "    reason: no SKILL.md" >&2
        return
    fi

    local query_count=$(python3 -c "import json; print(len(json.load(open('$eval_file'))))")

    echo "  [$skill_name] Running $query_count queries (workers=$WORKERS, timeout=${TIMEOUT}s)..." >&2

    # 运行 run_eval.py
    local result
    result=$(python3 -m scripts.run_eval \
        --eval-set "$eval_file" \
        --skill-path "$skill_path" \
        --num-workers "$WORKERS" \
        --timeout "$TIMEOUT" \
        --runs-per-query "$RUNS_PER_QUERY" \
        --verbose 2>&1)

    # 提取 JSON 输出 (run_eval.py 的 JSON 输出在 stdout)
    local json_output
    json_output=$(echo "$result" | grep -v '^\[' | grep -v '^Evaluating:' | grep -v '^Results:' | grep -v '^ ')

    # 保存原始 JSON
    echo "$json_output" > "$output_file" 2>/dev/null

    # 解析并输出 YAML
    python3 -c "
import json, sys
try:
    data = json.loads('''$json_output''')
except:
    # 如果内联解析失败，从文件读取
    try:
        with open('$output_file') as f:
            data = json.load(f)
    except:
        print('  $skill_name:')
        print('    status: error')
        print('    reason: failed to parse results')
        sys.exit(0)

s = data['summary']
print(f'  $skill_name:')
print(f'    passed: {s[\"passed\"]}')
print(f'    total: {s[\"total\"]}')
print(f'    rate: {s[\"passed\"]*100//s[\"total\"] if s[\"total\"] > 0 else 0}%')
print(f'    details:')
for r in data['results']:
    status = 'PASS' if r['pass'] else 'FAIL'
    triggered = r['trigger_rate'] > 0
    expect = 'trigger' if r['should_trigger'] else 'skip'
    print(f'      - [{status}] expect={expect} triggered={triggered} query=\"{r[\"query\"][:50]}\"')
" 2>/dev/null || {
        echo "  $skill_name:"
        echo "    status: parse_error"
    }

    # 打印 verbose 信息到 stderr
    echo "$result" | grep -E '^\[|^  \[' >&2 || true
}

# 执行
if [ -n "$TARGET_SKILL" ]; then
    run_skill_eval "$TARGET_SKILL"
else
    SKILLS=(
        aether-status
        aether-deploy
        aether-deploy-watch
        aether-dev
        aether-doctor
        aether-init
        aether-rollback
        aether-setup
        aether-volume
        aether-cli-guard
    )

    for i in "${!SKILLS[@]}"; do
        skill="${SKILLS[$i]}"
        run_skill_eval "$skill"

        # 限速: 每个 skill 之间等待
        if [ "$i" -lt $((${#SKILLS[@]} - 1)) ]; then
            echo "  [delay] Waiting ${DELAY}s before next skill..." >&2
            sleep "$DELAY"
        fi
    done
fi

echo ""
echo "# Raw results saved to: $RESULTS_DIR/"
