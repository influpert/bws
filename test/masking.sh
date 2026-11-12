#!/usr/bin/env bash
# Offline test: runs bin/load.sh against stubbed curl/unzip/bws and checks
# that every line of every loaded value is registered with ::add-mask::, and
# that no value line reaches the log any other way. Needs bash and jq.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A fake multiline PEM-shaped value, a CRLF value and a single-line value.
# None of these are real keys.
# PEM armor is assembled at runtime so secret scanners don't read it as a key.
armor_begin="-----BEGIN PRIVATE"" KEY-----"
armor_end="-----END PRIVATE"" KEY-----"
pem="${armor_begin}"$'\nFAKEbodyLINEoneAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nFAKEbodyLINEtwoBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n\nFAKEbodyLINEthree==\n'"${armor_end}"
crlf=$'FAKEcrlfLINEone\r\nFAKEcrlfLINEtwo'
single='FAKEsingleLINEvalue'

jq -n --arg pem "$pem" --arg crlf "$crlf" --arg single "$single" \
  '[{key:"MULTI",value:$pem},{key:"CRLF",value:$crlf},{key:"SINGLE",value:$single}]' \
  > "$work/secrets.json"

mkdir -p "$work/stubs"
cat > "$work/stubs/curl" <<'STUB'
#!/usr/bin/env bash
# -o <file>: the release download; anything else: the releases API.
out=""
while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
if [ -n "$out" ]; then : > "$out"; else echo '[{"tag_name":"bws-v2.0.0","prerelease":false}]'; fi
STUB
cat > "$work/stubs/unzip" <<'STUB'
#!/usr/bin/env bash
dest=""
while [ $# -gt 0 ]; do [ "$1" = "-d" ] && dest="$2"; shift; done
mkdir -p "$dest"
printf '#!/usr/bin/env bash\ncat %q\n' "$FAKE_SECRETS_JSON" > "$dest/bws"
STUB
chmod +x "$work/stubs/curl" "$work/stubs/unzip"

: > "$work/env"; : > "$work/path"
FAKE_SECRETS_JSON="$work/secrets.json" \
PATH="$work/stubs:$PATH" \
BWS_ACCESS_TOKEN=fake GH_TOKEN=fake INPUT_PROJECT_ID='' INPUT_NAMES=$'MULTI\nCRLF\nSINGLE' \
GITHUB_ENV="$work/env" GITHUB_PATH="$work/path" ACTION_REF=v2 \
GITHUB_ACTION_PATH="$root" \
  bash "$root/bin/load.sh" > "$work/log" 2>&1 || { cat "$work/log"; exit 1; }

fail=0
masks="$(sed -n 's/^::add-mask:://p' "$work/log")"
others="$(grep -v '^::add-mask::' "$work/log" || true)"
for value in "$pem" "$crlf" "$single"; do
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ [^[:space:]] ]] || continue
    if ! grep -qxF -- "$line" <<< "$masks"; then
      echo "FAIL: a value line was never registered with ::add-mask:: (${#line} chars)"
      fail=1
    fi
    if grep -qF -- "$line" <<< "$others"; then
      echo "FAIL: a value line reached the log outside an ::add-mask:: command (${#line} chars)"
      fail=1
    fi
  done <<< "$value"
done

# The heredoc export must still carry the multiline value intact.
grep -qxF 'FAKEbodyLINEthree==' "$work/env" || { echo "FAIL: MULTI not exported intact"; fail=1; }

[ "$fail" -eq 0 ] && echo "ok: every value line is masked"
exit "$fail"
