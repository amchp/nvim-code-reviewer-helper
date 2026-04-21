#!/usr/bin/env bash
set -euo pipefail

output=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

cat >/dev/null
sleep 0.3
printf 'slow response\n' >"$output"
