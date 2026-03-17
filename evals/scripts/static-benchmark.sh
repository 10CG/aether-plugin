#!/bin/bash
# Static Benchmark - 成本守卫 + 风险检查提示
# 用法: ./static-benchmark.sh [--skill <name>]
#
# 只做两件事:
#   1. 自动化: 计算 SKILL.md 行数/词数 (成本守卫)
#   2. 提示: 输出风险检查清单 (人工确认)
#
# 不做评分。评分 ≠ 质量。唯一的质量验证是 AB 测试。

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="$PLUGIN_DIR/skills"
TARGET_SKILL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skill) TARGET_SKILL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--skill <name>]"
            echo "Cost guard + risk checklist for Skill changes"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ============================================================
# 成本守卫: 行数/词数
# ============================================================
check_cost() {
    local skill_name="$1"
    local skill_dir="$SKILLS_DIR/$skill_name"
    local skill_md="$skill_dir/SKILL.md"

    if [ ! -f "$skill_md" ]; then
        echo "  SKIP: $skill_md not found"
        return
    fi

    local lines=$(wc -l < "$skill_md")
    local words=$(wc -w < "$skill_md")
    local ref_words=0
    if [ -d "$skill_dir/references" ]; then
        ref_words=$(cat "$skill_dir/references"/*.md 2>/dev/null | wc -w || echo 0)
    fi

    # 阈值判定
    local status="OK"
    if [ "$lines" -gt 500 ]; then
        status="BLOCKED (>500 lines)"
    elif [ "$lines" -gt 400 ]; then
        status="WARNING (>400 lines)"
    fi

    if [ "$ref_words" -gt 5000 ]; then
        status="BLOCKED (refs >5000 words)"
    elif [ "$ref_words" -gt 3000 ]; then
        status="${status}, WARNING (refs >3000 words)"
    fi

    printf "  %-22s %4d lines  %5d words  refs: %5d words  [%s]\n" \
        "$skill_name" "$lines" "$words" "$ref_words" "$status"
}

echo "=== COST GUARD ==="
echo ""

if [ -n "$TARGET_SKILL" ]; then
    check_cost "$TARGET_SKILL"
else
    for skill_dir in "$SKILLS_DIR"/aether-*/; do
        check_cost "$(basename "$skill_dir")"
    done
fi

echo ""
echo "=== RISK CHECKLIST (人工确认) ==="
echo ""

if [ -n "$TARGET_SKILL" ]; then
    # 检测 skill 类型
    skill_md="$SKILLS_DIR/$TARGET_SKILL/SKILL.md"
    if grep -qi "deploy\|rollback\|init\|setup" <<< "$TARGET_SKILL"; then
        echo "  流程型 Skill: $TARGET_SKILL"
        echo "  [ ] 危险操作前有用户确认步骤?"
        echo "  [ ] 有配置对比/diff 步骤?"
        echo "  [ ] 有回滚方案或失败恢复指引?"
        echo "  [ ] 有前置检查 (CLI/集群/配置)?"
        echo "  [ ] 步骤有明确顺序编号?"
    elif grep -qi "status\|doctor\|watch" <<< "$TARGET_SKILL"; then
        echo "  诊断型 Skill: $TARGET_SKILL"
        echo "  [ ] 覆盖用户问题的所有维度?"
        echo "  [ ] 指令是否过度约束? (探索型任务需留空间)"
        echo "  [ ] 有降级策略? (部分 API 不可达时)"
        echo "  [ ] 输出格式引导结构化呈现?"
    elif grep -qi "guard\|hook" <<< "$TARGET_SKILL"; then
        echo "  Hook 型 Skill: $TARGET_SKILL"
        echo "  [ ] 拦截条件精确? (不误拦不漏拦)"
        echo "  [ ] 拦截信息可操作? (告诉用户怎么修)"
    else
        echo "  通用检查: $TARGET_SKILL"
        echo "  [ ] 关键步骤是否完整?"
        echo "  [ ] 有无过度约束?"
    fi
else
    echo "  指定 --skill <name> 查看对应类型的风险检查清单"
fi

echo ""
echo "提示: 风险检查清单需人工确认。质量验证请运行 AB 测试。"
