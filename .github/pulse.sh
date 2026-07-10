#!/usr/bin/env bash
# Пульс каналу: створює тестовий стук «knock: пульс», чекає відповіді
# зграї (закриття issue), міряє секунди. Зріз останнього виміру —
# ПУЛЬС.md; історія вимірів — журнал цього репо. Зграя не відповіла за
# 40 хв — канал глухий: прогін червоний, стук закривається чесно.
set -euo pipefail
REPO="${GITHUB_REPOSITORY:?}"
START=$(date -u +%s)
N=$(gh issue create -R "$REPO" --title "knock: пульс" \
	--body "пульс каналу (E5): тестовий стук, непідписаний — міряє час відповіді зграї" \
	| sed 's|.*/||')

ANSWERED=0
for _ in $(seq 1 80); do
	sleep 30
	STATE=$(gh issue view "$N" -R "$REPO" --json state -q .state)
	if [ "$STATE" = "CLOSED" ]; then
		ANSWERED=1
		break
	fi
done
ELAPSED=$(( $(date -u +%s) - START ))

git config user.name "keeper-pulse"
git config user.email "pulse@keeper.garden"
git pull --rebase >/dev/null 2>&1 || true

if [ "$ANSWERED" = 1 ]; then
	printf '# ПУЛЬС каналу персон\n\nОстанній тестовий стук: канал живий — зграя відповіла за %s с.\nМіряється щодня (workflow pulse); історія вимірів — журнал цього репо.\n' \
		"$ELAPSED" >ПУЛЬС.md
	MSG="пульс: канал живий, відповідь за ${ELAPSED} с"
else
	gh issue comment "$N" -R "$REPO" --body "пульс: зграя НЕ відповіла за 40 хв — канал глухий"
	gh issue close "$N" -R "$REPO"
	printf '# ПУЛЬС каналу персон\n\nОстанній тестовий стук: КАНАЛ ГЛУХИЙ — зграя не відповіла за 40 хв.\nМіряється щодня (workflow pulse); історія вимірів — журнал цього репо.\n' \
		>ПУЛЬС.md
	MSG="пульс: канал глухий (40 хв без відповіді)"
fi

git add ПУЛЬС.md
if ! git diff --cached --quiet; then
	git commit -m "$MSG"
	for _ in 1 2 3 4 5; do
		git push && break
		git pull --rebase
	done
fi

[ "$ANSWERED" = 1 ] || { echo "::error::канал персон глухий — зграя мовчить"; exit 1; }
echo "канал живий: ${ELAPSED} с"
