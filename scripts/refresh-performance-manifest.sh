#!/usr/bin/env bash
# Regenerate docs/performance-file-manifest-index.tsv paths after folder reorg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/performance-file-manifest-index.tsv"
OLD="$OUT"
MAP="$ROOT/docs/reorg-move-map.csv"

path_map() {
  local p="$1"
  if [[ ! -f "$MAP" ]]; then
    echo "$p"
    return
  fi
  local mapped
  mapped="$(python3 - "$p" "$MAP" <<'PY'
import csv, sys
old, map_path = sys.argv[1], sys.argv[2]
best = old
with open(map_path, newline="") as f:
    for row in csv.DictReader(f):
        o, n = row["old_path"], row["new_path"]
        if o == old or old.startswith(o.rstrip("/") + "/"):
            best = n + old[len(o.rstrip("/")):]
            break
print(best)
PY
)"
  echo "$mapped"
}

{
  echo -e "path\tlines\tmodule\tcoverage\trisk_hint"
  while IFS= read -r line; do
    [[ "$line" == path* ]] && continue
    path="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    [[ -z "$path" ]] && continue
    new_path="$(path_map "$path")"
    if [[ -f "$ROOT/$new_path" ]]; then
      lines="$(wc -l < "$ROOT/$new_path" | tr -d ' ')"
      mod="$(echo "$new_path" | cut -d/ -f2)"
      [[ "$new_path" == College/Features/* ]] && mod="$(echo "$new_path" | cut -d/ -f3)"
      echo -e "${new_path}\t${lines}\t${mod}\t${rest#*	}"
    fi
  done < "$OLD"
  # Append any new Swift under College/ not in old manifest
  while IFS= read -r f; do
    rel="${f#"$ROOT/"}"
    grep -qF "$rel" "$OUT" 2>/dev/null && continue
    lines="$(wc -l < "$f" | tr -d ' ')"
    mod="$(echo "$rel" | cut -d/ -f2)"
    [[ "$rel" == College/Features/* ]] && mod="$(echo "$rel" | cut -d/ -f3)"
    echo -e "${rel}\t${lines}\t${mod}\t5c\tY"
  done < <(find "$ROOT/College" -name '*.swift' -type f | sort)
} > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "wrote $OUT ($(wc -l < "$OUT") lines)"
