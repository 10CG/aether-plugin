#!/usr/bin/env python3
"""Generate AB test subagent prompts from ab-suite eval cases.

Reads all eval JSON files from ab-suite/ and generates prompt pairs
(with_skill + without_skill) that can be fed to Claude Code Agent tool.

Usage:
    python3 generate-ab-prompts.py                    # All skills
    python3 generate-ab-prompts.py --skill aether-deploy  # Single skill
    python3 generate-ab-prompts.py --wave 1           # Only wave N
"""

import json
import sys
from pathlib import Path

PLUGIN_DIR = Path(__file__).parent.parent.parent
SUITE_DIR = PLUGIN_DIR / "evals" / "ab-suite"
SKILLS_DIR = PLUGIN_DIR / "skills"
RESULTS_DIR = PLUGIN_DIR / "evals" / "ab-results" / "2026-03-17"

# Wave assignment (2 skills per wave to avoid 529)
WAVES = {
    1: ["aether-deploy", "aether-rollback"],
    2: ["aether-status", "aether-doctor"],
    3: ["aether-init", "aether-deploy-watch"],
    4: ["aether-setup", "aether-dev"],
    5: ["aether-volume"],
}

def load_eval_suite(skill_name: str) -> dict:
    path = SUITE_DIR / f"{skill_name}.json"
    with open(path) as f:
        return json.load(f)

def generate_prompts(skill_name: str) -> list[dict]:
    suite = load_eval_suite(skill_name)
    skill_path = SKILLS_DIR / skill_name / "SKILL.md"
    prompts = []

    for eval_case in suite["evals"]:
        eval_dir = f"eval-{eval_case['id']}-{eval_case['name']}"
        result_base = RESULTS_DIR / skill_name / eval_dir

        # With skill prompt
        with_prompt = f"""Execute this task WITH the skill loaded:
- Skill: Read {skill_path} first, then follow its instructions.
- Task: "{eval_case['prompt']}"
- Save output to: {result_base}/with_skill/outputs/report.md

Read the SKILL.md first and follow its instructions/format.
If API calls fail (cluster not reachable), document what you WOULD do
and produce a realistic output following the skill's format."""

        # Without skill prompt
        without_prompt = f"""Execute this task WITHOUT any skill guidance:
- Task: "{eval_case['prompt']}"
- Save output to: {result_base}/without_skill/outputs/report.md

Do NOT read any skill files. Use your own knowledge to complete the task.
If API calls fail, produce the best output you can."""

        # Grader prompt
        expectations_text = "\n".join(
            f"  {i+1}. [{e['priority'].upper()}] {e['text']}"
            for i, e in enumerate(eval_case["expectations"])
        )

        grader_prompt = f"""You are Grader and Blind Comparator for an AB test.

## Context
Eval prompt: "{eval_case['prompt']}"
Output A: {result_base}/with_skill/outputs/report.md
Output B: {result_base}/without_skill/outputs/report.md

## Part 1: Grade BOTH outputs against expectations
{expectations_text}

For each: PASS/FAIL with evidence. If any CRITICAL fails → verdict = FAIL.

## Part 2: Blind Comparison
Content rubric (correctness, completeness, accuracy) 1-5
Structure rubric (organization, formatting, usability) 1-5
Winner: A, B, or TIE + reasoning

## Output
Save JSON to: {result_base}/grading_and_comparison.json

Format:
{{
  "grading": {{
    "A": {{"expectations": [{{"text":"...","priority":"critical","passed":true,"evidence":"..."}}], "summary": {{"passed":N,"total":N,"critical_passed":N,"critical_total":N}}}},
    "B": {{...}}
  }},
  "comparison": {{
    "winner": "A/B/TIE",
    "reasoning": "...",
    "rubric": {{
      "A": {{"content_score":X.X,"structure_score":X.X,"overall_score":X.X}},
      "B": {{...}}
    }}
  }}
}}"""

        prompts.append({
            "skill": skill_name,
            "eval_id": eval_case["id"],
            "eval_name": eval_case["name"],
            "with_skill": with_prompt,
            "without_skill": without_prompt,
            "grader": grader_prompt,
        })

    return prompts


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill", help="Single skill to generate")
    parser.add_argument("--wave", type=int, help="Only wave N")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args()

    if args.skill:
        skills = [args.skill]
    elif args.wave:
        skills = WAVES.get(args.wave, [])
    else:
        skills = [s for wave in WAVES.values() for s in wave]

    all_prompts = []
    for skill in skills:
        all_prompts.extend(generate_prompts(skill))

    if args.format == "json":
        print(json.dumps(all_prompts, indent=2, ensure_ascii=False))
    else:
        for p in all_prompts:
            print(f"=== {p['skill']} / eval-{p['eval_id']}-{p['eval_name']} ===")
            print(f"\n--- WITH SKILL ---\n{p['with_skill'][:200]}...")
            print(f"\n--- WITHOUT SKILL ---\n{p['without_skill'][:200]}...")
            print(f"\n--- GRADER ---\n{p['grader'][:200]}...")
            print()


if __name__ == "__main__":
    main()
