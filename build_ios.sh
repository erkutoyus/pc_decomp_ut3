#!/bin/bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
for python_command in python3.14 python3.13 python3.12 python3; do
  if command -v "$python_command" >/dev/null 2>&1 && "$python_command" -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null; then
    exec "$python_command" "$script_dir/tools/build_apple.py" ios "$@"
  fi
done
printf '%s\n' 'Python 3.12 or newer is required. Install prerequisites with: brew install python@3.13 cmake ninja wimlib' >&2
exit 1
