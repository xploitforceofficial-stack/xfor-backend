#!/usr/bin/env bash
# Probe candidate values for the PolSec key-gate response field `c`.
cd "$(dirname "$0")" || exit 1
FILE="C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
for v in "ok" "success" "valid" "whitelisted" "authorized" "true" "1" "200" "NIL" "TABLE" "LONG"; do
  out=$(POLFILE="$FILE" POLKEY="trial" POLC="$v" timeout 60 lune run _pol_trap 2>&1)
  verdict=$(echo "$out" | grep -c "WARN")
  cap=$(echo "$out" | grep -c "LOADSTRING")
  extra=$(echo "$out" | grep -c "TRAP json\.")
  echo "c=$v  warn=$verdict loadstring=$cap jsonreads=$extra  | $(echo "$out" | grep -m1 'native ok')"
done
