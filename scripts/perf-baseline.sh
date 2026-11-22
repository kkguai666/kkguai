#!/usr/bin/env bash
# 采集 PstscAgent 的性能统计：以 PSTSC_STATS=1 直接执行 app 内的二进制，
# 避免 open 启动时拿不到 stderr。只做本地采样，不构建、不联网。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="PstscAgent"
APP_BIN="$ROOT/build/kkguai.app/Contents/MacOS/$APP_NAME"
LOG="$ROOT/build/perf-baseline.log"
DURATION="${1:-90}"

usage() {
  cat <<'EOF'
用法: ./scripts/perf-baseline.sh [秒数]

  秒数        采样时长，默认 90 秒

脚本会以 PSTSC_STATS=1 直接启动 build/kkguai.app/Contents/MacOS/PstscAgent，
stdout/stderr 写入 build/perf-baseline.log（旧日志备份为 perf-baseline.log.bak）。
结束时先 TERM（2 秒后 KILL）停止进程，打印 [stats] 行并汇总最后 10 行的平均值。
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -eq 0 ]; then
  echo "错误: 秒数必须是正整数，收到: $DURATION" >&2
  usage >&2
  exit 2
fi

if [ ! -f "$APP_BIN" ]; then
  echo "错误: 未找到 $APP_BIN" >&2
  echo "请先运行: ./scripts/build-app.sh --no-install" >&2
  exit 1
fi

if [ ! -x "$APP_BIN" ]; then
  echo "错误: $APP_BIN 不可执行，请重新构建。" >&2
  exit 1
fi

# 单实例冲突：已有 PstscAgent 在跑时直接退出，不然采样会拿到假数据。
RUNNING_PIDS="$(pgrep -x "$APP_NAME" || true)"
if [ -n "$RUNNING_PIDS" ]; then
  echo "错误: 已有 $APP_NAME 进程在运行（PID: $(printf '%s\n' "$RUNNING_PIDS" | tr '\n' ' ')）" >&2
  echo "请先退出正在运行的 $APP_NAME（单实例冲突），再重新运行本脚本。" >&2
  exit 1
fi

# 旧日志备份后清空。
mkdir -p "$(dirname "$LOG")"
if [ -e "$LOG" ]; then
  mv -f "$LOG" "$LOG.bak"
  echo "旧日志已备份到 $LOG.bak"
fi
: > "$LOG"

is_running() {
  local pid="$1" state
  state="$(ps -p "$pid" -o stat= 2>/dev/null | tr -d '[:space:]')"
  [ -n "$state" ] || return 1
  case "$state" in
    Z*) return 1 ;; # 僵尸进程视为已退出
    *) return 0 ;;
  esac
}

stop_app() {
  local pid="$1" i
  # 先发 TERM，最多等 2 秒；仍存活则 KILL，最后回收子进程。
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  kill -TERM "$pid" 2>/dev/null || true
  for i in $(seq 1 20); do
    is_running "$pid" || break
    sleep 0.1
  done
  if is_running "$pid"; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

PSTSC_STATS=1 "$APP_BIN" >"$LOG" 2>&1 &
APP_PID=$!
echo "已启动 $APP_NAME（PID $APP_PID，PSTSC_STATS=1）"
echo "日志: $LOG"

INTERRUPTED=0
trap 'stop_app "$APP_PID"' EXIT
trap 'INTERRUPTED=1' INT TERM

sleep 1
if ! is_running "$APP_PID"; then
  echo "错误: $APP_NAME 启动后立即退出，请查看日志: $LOG" >&2
  exit 1
fi

echo "前台采样 ${DURATION}s，按 Ctrl-C 可提前结束..."
elapsed=0
while [ "$elapsed" -lt "$DURATION" ]; do
  sleep 1 || true
  if [ "$INTERRUPTED" -ne 0 ]; then
    break
  fi
  elapsed=$((elapsed + 1))
done
if [ "$INTERRUPTED" -ne 0 ]; then
  echo "已中断，提前结束采样。"
fi

if is_running "$APP_PID"; then
  echo "正在停止 $APP_NAME（PID $APP_PID）..."
else
  echo "$APP_NAME 已在采样期间退出。"
fi
stop_app "$APP_PID"
trap - EXIT INT TERM

echo
echo "===== [stats] 行（来自 $LOG） ====="
if grep -q '^\[stats\]' "$LOG" 2>/dev/null; then
  grep '^\[stats\]' "$LOG"
else
  echo "（日志里没有 [stats] 行；可能采样时间太短，或 app 没有进入渲染状态）"
fi

# 汇总最后 10 行可解析的 [stats] 数据行；解析失败就跳过，不影响退出码。
STATS_TAIL="$(grep '^\[stats\] upd=' "$LOG" 2>/dev/null | tail -n 10 || true)"
if [ -z "$STATS_TAIL" ]; then
  echo
  echo "（没有可解析的 [stats] 数据行，跳过汇总）"
  exit 0
fi

SUMMARY="$(
  printf '%s\n' "$STATS_TAIL" | awk '
    {
      n++
      for (i = 1; i <= NF; i++) {
        t = $i
        eq = index(t, "=")
        if (eq == 0) continue
        name = substr(t, 1, eq - 1)
        val = substr(t, eq + 1)
        sub(/ms$/, "", val); sub(/%$/, "", val); sub(/MB\/s$/, "", val)
        if (val !~ /^[0-9]+(\.[0-9]+)?$/) continue
        if (name == "avg") {
          avg[key] += val
          if (key == "lat" && val + 0 > 0) { latN++; latSum += val }
        } else if (name == "max") {
          if (val + 0 > maxv[key] + 0) maxv[key] = val
        } else {
          key = name
          if (name == "upd") upd += val
          else if (name == "cpu") cpu += val
        }
      }
    }
    END {
      if (n == 0) exit 1
      printf "样本: %d 行 [stats]\n", n
      printf "upd:           平均 %.1f 次/5s（约 %.1f 次/s）\n", upd / n, upd / n / 5
      printf "images avg:    平均 %.2f ms\n", avg["images"] / n
      printf "refreshes avg: 平均 %.2f ms\n", avg["refreshes"] / n
      printf "show avg:      平均 %.2f ms（提交图层）\n", avg["show"] / n
      printf "input→frame:   平均 %.0f ms / 最大 %.0f ms（仅有输入的区间）\n", latN ? latSum / latN : 0, maxv["lat"]
      printf "cpu:           平均 %.0f %%\n", cpu / n
    }
  ' 2>/dev/null
)" || SUMMARY=""

if [ -n "$SUMMARY" ]; then
  echo
  echo "===== 汇总（最后 10 行） ====="
  printf '%s\n' "$SUMMARY"
else
  echo
  echo "（汇总解析失败，已跳过）"
fi
