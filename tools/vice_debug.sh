#!/bin/bash
# Start a fresh x64sc with the binary monitor, run tools/vice_debug.py with the
# given arguments, then close VICE. Run from the workspace root in Git Bash.
# x64sc must be on the PATH, or set X64SC to its full path. The logger's
# console output goes to tmp/vrun_last.txt, and its last line is printed here.
# Retries up to three times, because back-to-back VICE starts sometimes miss
# the snapshot load. VICE_ARGS adds options for x64sc, such as an event
# history to play back in capture mode (see tools/vice_debug.py).
X64SC="${X64SC:-x64sc}"
mkdir -p tmp
for attempt in 1 2 3; do
  "$X64SC" +sound -warp -silent -binarymonitor -binarymonitoraddress ip4://127.0.0.1:6510 $VICE_ARGS > /dev/null 2>&1 &
  for i in $(seq 1 40); do sleep 0.5; netstat -an | grep -q "127.0.0.1:6510.*LISTEN" && break; done; sleep 3
  timeout 21600 python tools/vice_debug.py "$@" < /dev/null > tmp/vrun_last.txt 2>&1
  rc=$?
  taskkill //F //IM x64sc.exe > /dev/null 2>&1
  tail -1 tmp/vrun_last.txt
  [ $rc -eq 0 ] && exit 0
  sleep 8
done
exit 1
