#!/usr/bin/env bash
# Install repo git hooks (copies scripts/git-hooks/* → .git/hooks/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scripts/git-hooks"
DEST="$ROOT/.git/hooks"

if [[ ! -d "$DEST" ]]; then
  echo "install-git-hooks: .git/hooks missing — is this a git repo?" >&2
  exit 1
fi

installed=0
for hook in "$SRC"/*; do
  [[ -f "$hook" ]] || continue
  name="$(basename "$hook")"
  cp "$hook" "$DEST/$name"
  chmod +x "$DEST/$name"
  echo "install-git-hooks: installed $name"
  installed=$((installed + 1))
done

if ((installed == 0)); then
  echo "install-git-hooks: no hooks found in $SRC" >&2
  exit 1
fi

echo "install-git-hooks: done ($installed hook(s))"
