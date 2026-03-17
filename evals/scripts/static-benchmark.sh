#!/bin/bash
# Static Benchmark - 自动化 Skill 静态分析评分
# 用法: ./static-benchmark.sh [--skill <name>] [--compare baseline.yaml]
#
# 自动评估维度:
#   1. Token 效率 (完全自动化)
#   2. 结构检查 (半自动化 - 检查关键 section 是否存在)
#
# 输出: YAML 格式评分报告

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="$PLUGIN_DIR/skills"
EVALS_DIR="$PLUGIN_DIR/evals"
BASELINE="$EVALS_DIR/baseline.yaml"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 参数解析
TARGET_SKILL=""
COMPARE_FILE=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skill) TARGET_SKILL="$2"; shift 2 ;;
        --compare) COMPARE_FILE="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================
# Token 效率评分
# ============================================================
score_token_efficiency() {
    local skill_dir="$1"
    local skill_md="$skill_dir/SKILL.md"
    local ref_dir="$skill_dir/references"

    local lines=$(wc -l < "$skill_md")
    local words=$(wc -w < "$skill_md")
    local ref_words=0

    if [ -d "$ref_dir" ]; then
        ref_words=$(cat "$ref_dir"/*.md 2>/dev/null | wc -w || echo 0)
    fi

    # 评分基于行数 (scoring-rubric.md)
    local score
    if [ "$lines" -lt 200 ]; then
        score=100
    elif [ "$lines" -lt 300 ]; then
        score=90
    elif [ "$lines" -lt 400 ]; then
        score=80
    elif [ "$lines" -lt 500 ]; then
        score=70
    else
        score=60
    fi

    echo "      score: $score"
    echo "      lines: $lines"
    echo "      words: $words"
    echo "      ref_words: $ref_words"
}

# ============================================================
# 结构检查评分
# ============================================================
check_section_exists() {
    local file="$1"
    local pattern="$2"
    grep -qi "$pattern" "$file" 2>/dev/null && echo 1 || echo 0
}

score_output_quality() {
    local skill_md="$1"
    local ref_dir="$2"
    local total=0
    local checks=0

    # 检查输出格式定义
    local has_format=$(check_section_exists "$skill_md" "输出\|output\|格式\|format")
    total=$((total + has_format * 20))
    checks=$((checks + 1))

    # 检查示例
    local has_example=0
    if grep -q '```' "$skill_md" 2>/dev/null; then
        has_example=1
    fi
    # 也检查 references
    if [ -d "$ref_dir" ] && grep -rq '```' "$ref_dir" 2>/dev/null; then
        has_example=1
    fi
    total=$((total + has_example * 20))
    checks=$((checks + 1))

    # 检查错误/异常流程
    local has_error=0
    if grep -qi "错误\|故障\|error\|fail\|异常" "$skill_md" 2>/dev/null; then
        has_error=1
    fi
    if [ -d "$ref_dir" ] && grep -rqi "错误\|故障\|error\|fail" "$ref_dir" 2>/dev/null; then
        has_error=1
    fi
    total=$((total + has_error * 20))
    checks=$((checks + 1))

    # 检查祈使句 (检查 "使用", "执行", "运行", "检查" 等动词)
    local imperative_count=$(grep -cEi "^[^#]*使用|^[^#]*执行|^[^#]*运行|^[^#]*检查|^[^#]*获取" "$skill_md" 2>/dev/null || echo 0)
    if [ "$imperative_count" -ge 3 ]; then
        total=$((total + 20))
    elif [ "$imperative_count" -ge 1 ]; then
        total=$((total + 14))
    fi
    checks=$((checks + 1))

    # 检查 "why" 解释 (不使用场景, 原因, 因为)
    local has_why=$(check_section_exists "$skill_md" "不使用\|原因\|因为\|why\|场景")
    total=$((total + has_why * 20))
    checks=$((checks + 1))

    echo "$total"
}

score_error_handling() {
    local skill_md="$1"
    local ref_dir="$2"
    local total=0
    local max=5

    # CLI 缺失处理
    if grep -qi "require_aether_cli\|CLI.*安装\|CLI.*missing\|未安装" "$skill_md" 2>/dev/null; then
        total=$((total + 1))
    elif [ -d "$ref_dir" ] && grep -rqi "require_aether_cli\|CLI.*安装" "$ref_dir" 2>/dev/null; then
        total=$((total + 1))
    fi

    # 连接失败处理
    if grep -qi "连接失败\|不可达\|unreachable\|connection.*fail\|timeout\|超时" "$skill_md" 2>/dev/null; then
        total=$((total + 1))
    elif [ -d "$ref_dir" ] && grep -rqi "连接失败\|不可达\|unreachable\|timeout" "$ref_dir" 2>/dev/null; then
        total=$((total + 1))
    fi

    # 配置缺失处理
    if grep -qi "配置.*缺失\|config.*missing\|setup\|前置条件\|NOMAD_ADDR" "$skill_md" 2>/dev/null; then
        total=$((total + 1))
    fi

    # 可操作的错误信息
    if grep -qi "请先运行\|请检查\|建议\|fix\|修复\|解决" "$skill_md" 2>/dev/null; then
        total=$((total + 1))
    fi

    # 降级策略
    if grep -qi "降级\|fallback\|degraded\|部分可用\|graceful" "$skill_md" 2>/dev/null; then
        total=$((total + 1))
    elif [ -d "$ref_dir" ] && grep -rqi "降级\|fallback\|degraded" "$ref_dir" 2>/dev/null; then
        total=$((total + 1))
    fi

    # 计算百分比
    echo $((total * 100 / max))
}

score_tool_usage() {
    local skill_md="$1"
    local total=0

    # 检查 allowed-tools 存在
    if grep -q "allowed-tools:" "$skill_md" 2>/dev/null; then
        total=$((total + 40))

        # 检查工具数量 (越少越好)
        local tool_count=$(grep "allowed-tools:" "$skill_md" | tr ',' '\n' | wc -l)
        if [ "$tool_count" -le 2 ]; then
            total=$((total + 30))
        elif [ "$tool_count" -le 4 ]; then
            total=$((total + 20))
        else
            total=$((total + 10))
        fi
    fi

    # 检查工具使用引导
    if grep -qi "使用.*Bash\|使用.*Read\|使用.*Write\|AskUserQuestion" "$skill_md" 2>/dev/null; then
        total=$((total + 30))
    else
        total=$((total + 15))
    fi

    echo "$total"
}

# ============================================================
# 评估单个 Skill
# ============================================================
evaluate_skill() {
    local skill_name="$1"
    local skill_dir="$SKILLS_DIR/$skill_name"
    local skill_md="$skill_dir/SKILL.md"
    local ref_dir="$skill_dir/references"

    if [ ! -f "$skill_md" ]; then
        echo "  $skill_name: SKIP (no SKILL.md)" >&2
        return
    fi

    local output_quality=$(score_output_quality "$skill_md" "$ref_dir")
    local tool_usage=$(score_tool_usage "$skill_md")
    local error_handling=$(score_error_handling "$skill_md" "$ref_dir")

    echo "  $skill_name:"
    echo "    output_quality:"
    echo "      score: $output_quality"
    echo "    tool_usage:"
    echo "      score: $tool_usage"
    echo "    error_handling:"
    echo "      score: $error_handling"
    echo "    token_efficiency:"
    score_token_efficiency "$skill_dir"

    # 计算综合分 (trigger_accuracy 需要运行时测试，这里用 N/A)
    # overall = output*0.25 + tool*0.20 + error*0.15 + token*0.15 + trigger*0.25
    # 无 trigger 数据时，用其他 4 维按比例计算
    local token_score
    token_score=$(score_token_efficiency "$skill_dir" | grep "score:" | awk '{print $2}')

    local weighted=$(awk "BEGIN {printf \"%.1f\", $output_quality * 0.333 + $tool_usage * 0.267 + $error_handling * 0.200 + $token_score * 0.200}")
    echo "    static_score: $weighted"
}

# ============================================================
# 主流程
# ============================================================

echo "# Static Benchmark Report"
echo "# Generated: $(date +%Y-%m-%d)"
echo "# Scope: ${TARGET_SKILL:-all}"
echo ""
echo "date: \"$(date +%Y-%m-%d)\""
echo "type: static-analysis"
echo ""
echo "results:"

if [ -n "$TARGET_SKILL" ]; then
    evaluate_skill "$TARGET_SKILL"
else
    # 排除 skill-benchmark 自身
    for skill_dir in "$SKILLS_DIR"/aether-*/; do
        skill_name=$(basename "$skill_dir")
        evaluate_skill "$skill_name"
    done
fi

# ============================================================
# 基准线对比
# ============================================================
if [ -n "$COMPARE_FILE" ] && [ -f "$COMPARE_FILE" ]; then
    echo ""
    echo "comparison:"
    echo "  baseline: $COMPARE_FILE"
    echo "  note: \"Use diff tool for detailed comparison\""
fi

echo ""
echo "# Run with: ./static-benchmark.sh [--skill <name>] [--compare baseline.yaml]"
