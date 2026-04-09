# Phantom Alloc 诊断 (超时时执行)

当 Step 3 超时且 `PASSING < DESIRED` 时，执行 phantom alloc 检测：

```bash
# 获取所有 Nomad 报告为 running 的 alloc
RUNNING_ALLOCS=$(curl -sf --max-time 10 \
  "${NOMAD_ADDR}/v1/job/${JOB_NAME}/allocations" | \
  jq -r '.[] | select(.ClientStatus == "running" and .DesiredStatus == "run") | .ID')

PHANTOM_COUNT=0
for alloc_id in $RUNNING_ALLOCS; do
  TASK_STATES=$(curl -sf --max-time 10 \
    "${NOMAD_ADDR}/v1/allocation/${alloc_id}" | \
    jq -r '[.TaskStates // {} | to_entries[] | .value.State] | unique | .[]')
  if echo "$TASK_STATES" | grep -q "dead"; then
    PHANTOM_COUNT=$((PHANTOM_COUNT + 1))
    echo "  ⚠️ Phantom alloc: ${alloc_id:0:8} (Nomad=running, TaskState=dead)"
    echo "    Fix: nomad alloc stop ${alloc_id}"
  fi
done

if [ "$PHANTOM_COUNT" -gt 0 ]; then
  echo ""
  echo "❌ ${PHANTOM_COUNT} phantom allocation(s) detected"
  echo "  Cause: Docker daemon lost container lifecycle event (Issue #12)"
  echo "  Fix: Stop phantom allocs to trigger rescheduling, or drain the affected node"
fi
```

此检测仅在超时路径执行，不影响正常部署的性能。
