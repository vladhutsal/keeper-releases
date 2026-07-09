#!/usr/bin/env bash
# Хмарна зграя: чує стуки (issues «knock: …»), верифікує підпис ПУБЛІЧНИМ
# ключем (.github/allowed_signers, namespace keeper-token), реєструє в
# ПЕРСОНИ.md, відкриває живий канал персони (issue «persona: <ім'я>» —
# одна на персону, П4.4), відповідає коментарем і закриває стук. Тіло
# Майстерні може спати — дух чує з хмари GitHub. Тіло, прокинувшись,
# робить своє: локальна зграя журналить persona-alive у сад
# (ідемпотентно: закриті стуки не чіпаються).
set -euo pipefail
REPO="${GITHUB_REPOSITORY:?}"
SIGNERS=".github/allowed_signers"
PRINCIPAL=$(awk '{print $1; exit}' "$SIGNERS")

git config user.name "keeper-flock"
git config user.email "flock@keeper.garden"

# ensure_channel <ім'я> — номер живої issue «persona: <ім'я>»; створює,
# якщо нема (канал = одна відкрита issue, решта спілкування — коментарі).
ensure_channel() {
	local name="$1" ch
	ch=$(gh issue list -R "$REPO" --state open --limit 100 \
		--json number,title \
		| jq -r --arg t "persona: $name" \
			'.[] | select(.title == $t) | .number' | head -1)
	if [ -z "$ch" ]; then
		ch=$(gh issue create -R "$REPO" --title "persona: $name" --body \
"Живий канал персони «$name» — одна issue (П4.4).

Питання персони до Майстерні і письма Майстерні персоні — коментарі
тут. Відкрита = канал живий; закриття = архів (історія лишається)." \
			| sed 's|.*/||')
	fi
	printf '%s' "$ch"
}

heard=0
declare -a NUMS=() ACKS=()
for N in $(gh issue list -R "$REPO" --state open --limit 100 \
	--json number,title \
	-q '.[] | select(.title | startswith("knock: ")) | .number'); do
	TITLE=$(gh issue view "$N" -R "$REPO" --json title -q .title)
	NAME=${TITLE#knock: }
	gh issue view "$N" -R "$REPO" --json body -q .body >/tmp/body.txt

	awk '/^---ПІДПИС/{exit} {print}' /tmp/body.txt >/tmp/manifest.txt
	awk 'f{print} /^---ПІДПИС/{f=1}' /tmp/body.txt >/tmp/sig.txt

	STATUS="первинний контакт (без підпису)"
	if grep -q "BEGIN SSH SIGNATURE" /tmp/sig.txt; then
		# канонічна форма: LF, рівно один хвостовий \n
		printf '%s\n' "$(sed 's/\r$//' /tmp/manifest.txt)" >/tmp/canon.txt
		if ssh-keygen -Y verify -f "$SIGNERS" -I "$PRINCIPAL" -n keeper-token \
			-s /tmp/sig.txt </tmp/canon.txt >/dev/null 2>&1; then
			STATUS="підпис верифіковано ✓ (хмарна зграя)"
		else
			STATUS="⚠ підпис НЕ зійшовся (хмарна зграя)"
		fi
	fi

	{
		[ -f ПЕРСОНИ.md ] || printf '# ПЕРСОНИ — стуки, почуті хмарною зграєю\n'
		printf '\n## %s\n\n- статус: %s\n- стук: issue #%s\n' "$NAME" "$STATUS" "$N"
		sed 's/\r$//' /tmp/manifest.txt | awk 'NF{print "- " $0}'
	} >>ПЕРСОНИ.md

	CH=$(ensure_channel "$NAME" || true)
	ACK="Зграя чує: $STATUS · зареєстровано в ПЕРСОНИ.md"
	[ -n "$CH" ] && ACK="$ACK · живий канал персони — issue #$CH"

	NUMS+=("$N")
	ACKS+=("$ACK")
	heard=$((heard + 1))
done

if [ "$heard" -gt 0 ]; then
	git add ПЕРСОНИ.md
	git commit -m "зграя: почуто стуків — $heard"
	# Майстерня жива: паралельний пуш — звичайна гонка, доганяємо і
	# повторюємо (виміряно стуком #5: пуш відкинуто, реєстр загублено,
	# а коментар збрехав «зареєстровано»). Відповідь і закриття — лише
	# ПІСЛЯ вдалого пушу: не записано = не почуто, стук лишається
	# відкритим, і його підмете наступний прогін.
	pushed=0
	for _ in 1 2 3 4 5; do
		if git push; then
			pushed=1
			break
		fi
		git pull --rebase
	done
	if [ "$pushed" != 1 ]; then
		echo "::error::реєстр не запушився після 5 спроб — стуки лишаються відкритими"
		exit 1
	fi
	for i in "${!NUMS[@]}"; do
		gh issue comment "${NUMS[$i]}" -R "$REPO" --body "${ACKS[$i]}"
		gh issue close "${NUMS[$i]}" -R "$REPO"
	done
fi
echo "почуто: $heard"
