# 轮询模式与容错

- 每次 `curl` 使用 `--max-time 10 --connect-timeout 3`。
- 维护 `api_fail_count` 计数器，成功调用重置为 0，连续 3 次失败 → 终止。

```bash
MAX_ITER=18; INTERVAL=10; api_fail_count=0
for i in $(seq 1 $MAX_ITER); do
  # ... 执行 Deployment/Allocation 检查 ...
  if [ $? -ne 0 ]; then
    api_fail_count=$((api_fail_count + 1))
    [ $api_fail_count -ge 3 ] && echo "❌ Nomad API 连续不可达，运行 /aether:doctor" && exit 1
  else
    api_fail_count=0
  fi
  # 终端状态 (successful/failed/all-running) 判定后 break
  echo "[Step 2] Deployment converging... (attempt ${i}/${MAX_ITER})"
  sleep $INTERVAL
done
```
