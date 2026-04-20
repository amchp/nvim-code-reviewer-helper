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
cat >"$output" <<'EOF'
```json
{
  "mode": "repo",
  "summary": "Start at the docs, then the command entrypoint, then the main orchestration.",
  "items": [
    {
      "path": "README.md",
      "reason": "Explains the plugin surface first.",
      "status": "repo",
      "old_path": null
    },
    {
      "path": "plugin/code_reviewer_helper.lua",
      "reason": "Shows the commands users can run.",
      "status": "repo",
      "old_path": null
    },
    {
      "path": "lua/code_reviewer_helper/init.lua",
      "reason": "Connects the commands to the implementation.",
      "status": "repo",
      "old_path": null
    }
  ]
}
```
# Review Order

Start with the docs, then move into the command registration, then the main orchestration.

1. `README.md` - Explains the plugin surface first.
2. `plugin/code_reviewer_helper.lua` - Shows the commands users can run.
3. `lua/code_reviewer_helper/init.lua` - Connects the commands to the implementation.
EOF
