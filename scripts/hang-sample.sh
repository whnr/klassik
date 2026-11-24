#!/usr/bin/env bash
# Samples the app while the UI log stands still, to show what its threads wait for.
# Arguments: the log file, the output directory.
log=$1 out=$2
last=$(stat -f %m "$log" 2>/dev/null || echo 0)
still=0 taken=0
while sleep 10; do
  now=$(stat -f %m "$log" 2>/dev/null || echo 0)
  if [ "$now" = "$last" ]; then still=$((still + 10)); else still=0; last=$now; fi
  [ "$still" -ge 40 ] && [ "$taken" -lt 8 ] || continue
  pid=$(pgrep -f "Klassik.app/Klassik" | head -1)
  [ -n "$pid" ] || continue
  taken=$((taken + 1))
  { date; ps -o pid,stat,%cpu,etime,command -p "$pid"; } > "$out/sample-$taken.txt" 2>&1
  sample "$pid" 3 -file "$out/sample-$taken-threads.txt" > /dev/null 2>&1 || true
  still=0
done
