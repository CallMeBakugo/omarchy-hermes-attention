#!/usr/bin/env bash
set -euo pipefail

commit="${1:-}"
replace="${2:-}"
if [[ ! $commit =~ ^[0-9a-f]{40}$ || ( -n $replace && $replace != --replace ) || $# -gt 2 ]]; then
  printf 'Usage: bash install.sh <reviewed-commit-sha> [--replace]\n' >&2
  exit 2
fi

source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
if [[ $(git -C "$source_dir" rev-parse --verify HEAD) != "$commit" ]] ||
  ! git -C "$source_dir" diff --quiet "$commit" -- install.sh attention.sh; then
  printf 'Use the clean plugin checkout at the reviewed commit %s.\n' "$commit" >&2
  exit 1
fi

hooks_dir="${HERMES_HOME:-$HOME/.hermes}/agent-hooks"
destination="$hooks_dir/attention.sh"
mkdir -p -- "$hooks_dir"
temporary=$(mktemp -- "$hooks_dir/.attention.XXXXXXXX")
trap 'rm -f -- "$temporary"' EXIT
git -C "$source_dir" show "$commit:attention.sh" > "$temporary"
chmod 700 -- "$temporary"

if [[ -L $destination || ( -e $destination && ! -f $destination ) ]]; then
  printf 'Refusing to replace a non-regular hook at %s.\n' "$destination" >&2
  exit 1
fi

if cmp -s -- "$temporary" "$destination"; then
  printf 'Hook already installed at %s\n' "$destination"
elif [[ $replace == --replace && -f $destination ]]; then
  mv -fT -- "$temporary" "$destination"
  printf 'Updated hook at %s\n' "$destination"
elif ln -T -- "$temporary" "$destination" 2>/dev/null; then
  printf 'Installed hook at %s\n' "$destination"
else
  printf 'Review the existing hook at %s before rerunning with --replace.\n' "$destination" >&2
  exit 1
fi
printf 'Register the hook in Hermes as described in README.md.\n'
