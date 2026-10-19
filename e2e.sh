#!/usr/bin/env bash
# Builds pattern.mqc and checks what only the compiled command can: argument parsing, the
# --allow-read/--allow-write flags, stdin, and documents too large for mq-test.
# What `run` prints for a given document and arguments is tested in pattern_tests.mq.
set -euo pipefail
cd "$(dirname "$0")"

mq compile -L . -f cli.mq -o pattern.mqc
P="mq pattern.mqc"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check() {
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1"
    echo "--- expected"; echo "$2"
    echo "--- actual"; echo "$3"
    exit 1
  fi
  echo "ok: $1"
}

check "count" "testdata/sample.md: 5" \
  "$($P --arg pattern '[$t]($u)' --arg output count testdata/sample.md)"

check "json argument" "5:50  [mirror](http://m.org)" \
  "$($P --arg pattern '[$t]($u)' --arg inside '## Install' --argjson constraints '{"u":"^http:"}' testdata/sample.md | sed -n 2p)"

check "preview" "$(printf 'testdata/sample.md\n5:50  - [mirror](http://m.org)\n      + [mirror](https://m.org)\n\n24:8  - [deep](http://deep.example)\n      + [deep](https://deep.example)')" \
  "$($P --arg pattern '[$t](http://$r)' --arg rewrite '[$t](https://$r)' testdata/sample.md)"

cp testdata/ja.md "$tmp/ja.md"
$P -R -W --arg pattern ' - [ ] $i' --arg rewrite ' - [x] $i' --arg write true "$tmp/ja.md" > /dev/null
check "write" "$(printf '日本語 [リンク](http://u) 終わり\n\n  - [x] 項目\n- [x] done')" "$(cat "$tmp/ja.md")"

# mq stops at a fixed depth of nested calls and limits regex matches, so a recursion over
# the nodes, lines or matches of a large document fails. These documents have more of each.
awk 'BEGIN { for (i = 1; i <= 6000; i++) printf "[a%d](http://x.example/%d)\n\n", i, i }' > "$tmp/big.md"
check "large document: many nodes" "$tmp/big.md: 6000" \
  "$($P --arg pattern '[$t](http://$r)' --arg output count "$tmp/big.md")"

$P -R --arg pattern '[$t](http://$r)' --arg rewrite '[$t](https://$r)' --arg output doc "$tmp/big.md" > "$tmp/big.out.md"
check "large document: many lines and edits" "6000 0" \
  "$(grep -c 'https://' "$tmp/big.out.md") $(grep -c 'http://' "$tmp/big.out.md" || true)"

awk 'BEGIN { for (i = 1; i <= 1500; i++) printf "日本語 [リンク%d](http://u/%d) 終わり\n\n", i, i }' > "$tmp/big_ja.md"
$P -R --arg pattern '[$t](http://$r)' --arg rewrite '[$t](https://$r)' --arg output doc "$tmp/big_ja.md" > "$tmp/big_ja.out.md"
check "large multibyte document keeps its text" "1500 1500" \
  "$(grep -c '^日本語 \[リンク[0-9]*\](https://u/[0-9]*) 終わり$' "$tmp/big_ja.out.md") $(grep -c '日本語' "$tmp/big_ja.out.md")"

check "stdin" "<stdin>" \
  "$(cat testdata/sample.md | $P --arg pattern '[$t](http://$r)' | head -1)"

echo "all passed"
