#!/usr/bin/env bash
# Доставка писем зграї (див. workflows/letters.yml).
# Формат письма: перший рядок `issue: N`, далі порожній рядок, далі тіло.
set -euo pipefail

dir="письма"
[ -d "$dir" ] || exit 0

delivered=0
for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  issue=$(head -1 "$f" | sed -n 's/^issue:[[:space:]]*\([0-9]\+\).*/\1/p')
  if [ -z "$issue" ]; then
    echo "::warning file=$f::письмо без 'issue: N' у першому рядку — пропускаю"
    continue
  fi
  tail -n +2 "$f" | sed '/./,$!d' | gh issue comment "$issue" \
    -R "$GITHUB_REPOSITORY" --body-file -
  git rm -q "$f"
  delivered=$((delivered + 1))
  echo "✓ $f → #$issue"
done

if [ "$delivered" -gt 0 ]; then
  git config user.name "keeper-flock"
  git config user.email "actions@github.com"
  git commit -m "зграя: письма доставлено ($delivered) — знято з поверхні, текст у історії та в issue"
  git push
fi
