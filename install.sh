#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
hooks_dir="${HERMES_HOME:-$HOME/.hermes}/agent-hooks"
destination="$hooks_dir/attention.sh"
mkdir -p -- "$hooks_dir"

if [[ -e $destination || -L $destination ]]; then
  if cmp -s -- "$source_dir/attention.sh" "$destination"; then
    printf 'Hook already installed at %s\n' "$destination"
  else
    printf 'A different hook exists at %s. Review it before replacing it.\n' "$destination" >&2
    exit 1
  fi
else
  install -m 755 -- "$source_dir/attention.sh" "$destination"
  printf 'Installed hook at %s\n' "$destination"
fi
printf 'Register the hook in Hermes as described in README.md.\n'
