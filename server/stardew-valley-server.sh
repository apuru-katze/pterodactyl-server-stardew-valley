#!/bin/bash
export DISPLAY=:10.0
export XAUTHORITY=~/.Xauthority
export TERM=xterm

# Cleanup function
cleanup() {
    echo "Shutting down server..."
    killall -9 cpulimit StardewModdingAPI Xvfb x11vnc i3 2>/dev/null
    rm -f /tmp/.X10-lock
}
trap cleanup EXIT INT TERM

# Start virtual display
if [ -f /tmp/.X10-lock ]; then rm /tmp/.X10-lock; fi
Xvfb :10 -screen 0 1280x720x24 -ac &

# Wait for X display
while ! xdpyinfo -display :10 >/dev/null 2>&1; do
    echo "Waiting for X display..."
    sleep 2
done

# Start VNC if enabled
if [ "${USE_VNC}" = "1" ]; then

    echo "Starting x11vnc on port ${VNC_PORT}"

    # Start VNC server
    x11vnc -display :10 -rfbport "${VNC_PORT:-5900}" -ncache 10 -forever -shared -passwd "${VNC_PASS:-myvncpassword}" &
else
    echo "VNC mode disabled"
fi

# Render/CPU throttling: RENDER_FPS < 30 = limit CPU % to reduce load (1 = minimal, 30 = no limit)
# Uses cpulimit for real CPU cap; falls back to timerslack_ns if cpulimit not available

FPS="${RENDER_FPS:-30}"

# Validate integer
case "$FPS" in
  ''|*[!0-9]*)
    echo "Invalid RENDER_FPS='$FPS'; skipping throttle, using full speed"
    FPS=30
    ;;
esac

# CPU % when throttling: 1 -> 5%, 5 -> 10%, 10 -> 18%, 20 -> 33%, 29 -> 50% (capped)
# Formula: 5 + (FPS * 45 / 29), min 5 max 50
calc_cpu_percent() {
  local f=$1
  if [ "$f" -le 0 ]; then echo 5; return; fi
  local p=$(( 5 + (f * 45 / 29) ))
  if [ "$p" -lt 5 ]; then p=5; fi
  if [ "$p" -gt 50 ]; then p=50; fi
  echo "$p"
}

APPLY_CPU_THROTTLE=0
CPU_PERCENT=50

if [ "$FPS" -lt 30 ]; then
  CPU_PERCENT=$(calc_cpu_percent "$FPS")

  if command -v cpulimit >/dev/null 2>&1; then
    APPLY_CPU_THROTTLE=1
    echo "Render/CPU throttle: RENDER_FPS=$FPS -> CPU limit ${CPU_PERCENT}% (cpulimit)"
  elif [ -w /proc/self/timerslack_ns ]; then
    # Fallback: timerslack (weaker, only hints kernel)
    SLACK_NS=$(( 1000000000 / FPS ))
    echo "$SLACK_NS" > /proc/self/timerslack_ns
    echo "Render throttle (fallback): ~${FPS}Hz timerslack_ns=$SLACK_NS (install cpulimit for real CPU limit)"
  else
    echo "Cannot throttle: install cpulimit or use kernel with timerslack_ns"
  fi
else
  echo "RENDER_FPS=$FPS (>=30): no throttle (full speed)"
fi

# Start Stardew server
cd /home/container

if [ "$APPLY_CPU_THROTTLE" = "1" ]; then
  # Run game in background so we can attach cpulimit to its PID, then wait for it
  ./StardewModdingAPI &
  GAME_PID=$!
  sleep 1
  if kill -0 "$GAME_PID" 2>/dev/null; then
    cpulimit -p "$GAME_PID" -l "$CPU_PERCENT" -b
  fi
  wait "$GAME_PID"
  exit $?
else
  exec ./StardewModdingAPI
fi
