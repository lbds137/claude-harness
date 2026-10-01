#!/bin/bash
# Skill-name lint: a SKILL.md whose frontmatter name: differs from its
# containing directory silently fails to load. Every skill must live in a
# directory matching its name. Usage: tests/skill-name-lint.probe.sh   (from anywhere)

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="$REPO/plugins/seyag/skills"
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# Print the frontmatter name value of $1 on stdout; exit 1 if the frontmatter
# is missing, malformed (no opening/closing ---), or has no non-empty name:.
# The name is captured but only returned once the closing --- is seen: a
# frontmatter that never closes is malformed no matter what it contains.
extract_name() {
  local file=$1 line in_fm=0 name=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in_fm" -eq 0 ]; then
      [ "$line" = "---" ] || return 1
      in_fm=1
      continue
    fi
    if [ "$line" = "---" ]; then
      [ -n "$name" ] || return 1
      printf '%s' "$name"
      return 0
    fi
    case "$line" in
      name:*)
        name="${line#name:}"
        name="${name#"${name%%[![:space:]]*}"}"    # ltrim
        name="${name%"${name##*[![:space:]]}"}"    # rtrim
        name="${name%\"}"; name="${name#\"}"       # strip quotes
        name="${name%\'}"; name="${name#\'}"
        name="${name%"${name##*[![:space:]]}"}"    # rtrim again
        ;;
    esac
  done < "$file"
  return 1   # EOF without a closing ---
}

[ -d "$SKILLS" ] || { bad "skills dir missing: $SKILLS"; exit 1; }

n=0
shopt -s nullglob
for d in "$SKILLS"/*/; do
  d="${d%/}"
  [ -L "$d" ] && continue            # symlinks are ignored
  f="$d/SKILL.md"
  [ -f "$f" ] || continue            # only skills/*/SKILL.md is scanned
  n=$((n + 1))
  rel="${f#"$REPO"/}"
  name="$(extract_name "$f")" || { bad "$rel: missing or malformed frontmatter"; continue; }
  dir="$(basename "$d")"
  [ "$name" = "$dir" ] || bad "$rel: name '$name' != directory '$dir'"
done

for f in "$SKILLS"/*.md; do
  [ -e "$f" ] || continue
  [ -L "$f" ] && continue            # symlinks are ignored
  bad "flat skill file: ${f#"$REPO"/} (skills must live in a named directory)"
done

if [ "$fail" -ne 0 ]; then exit 1; fi
ok "skill lint: $n skills checked, names match, 0 flat files"
