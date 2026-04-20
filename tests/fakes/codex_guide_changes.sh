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
  "mode": "changes",
  "summary": "Review the tracked edit first, then the new file, then the deleted file, then the rename.",
  "items": [
    {
      "path": "modified.lua",
      "reason": "This is the core tracked edit.",
      "status": "modified",
      "old_path": null
    },
    {
      "path": "added.lua",
      "reason": "This is a new file with no base revision.",
      "status": "untracked",
      "old_path": null
    },
    {
      "path": "deleted.lua",
      "reason": "This file was removed and still matters for context.",
      "status": "deleted",
      "old_path": null
    },
    {
      "path": "renamed_new.lua",
      "reason": "This rename should be reviewed last.",
      "status": "renamed",
      "old_path": "renamed_old.lua"
    }
  ]
}
```
# Review Order

Review the tracked edit first, then the added file, then the deleted file, then the rename.
EOF
