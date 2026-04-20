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
printf 'forced failure\n' >&2
printf '' >"$output"
exit 7
