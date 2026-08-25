#!/usr/bin/env bash
# Install the bws CLI and load the requested Bitwarden secrets BY NAME into
# $GITHUB_ENV, masked.
#
# The action's major version tracks the bws CLI major version, derived
# DYNAMICALLY from how the action was referenced (github.action_ref): `@v2`
# installs the latest bws 2.x. There is no file to keep in sync with the tag.
# For a SHA-pinned or branch/local ref (no major in the ref), the action
# recovers a version tag at its own checkout, and failing that installs the
# latest bws release overall.
set -euo pipefail

: "${BWS_ACCESS_TOKEN:?access-token is required}"
: "${INPUT_PROJECT_ID:=}"
: "${INPUT_NAMES:?names is required}"

# Derive the bws major from the action ref (e.g. "v2" -> 2, "v2.1.0" -> 2).
major=""
if [[ "${ACTION_REF:-}" =~ ^v?([0-9]+) ]]; then
  major="${BASH_REMATCH[1]}"
fi
if [ -z "$major" ]; then
  # SHA/branch/local ref: recover a version tag pointing at this checkout.
  tag="$(git -C "$GITHUB_ACTION_PATH" tag --points-at HEAD 2>/dev/null | grep -Em1 '^v?[0-9]+' || true)"
  if [[ "$tag" =~ ^v?([0-9]+) ]]; then
    major="${BASH_REMATCH[1]}"
  fi
fi
[ -n "$major" ] || echo "note: no major in action ref '${ACTION_REF:-}'; installing the latest bws release"

# --- resolve the latest non-prerelease bws-v<major>.* release ---
api="https://api.github.com/repos/bitwarden/sdk-sm/releases?per_page=100"
auth=()
[ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")
ver="$(
  curl -fsSL "${auth[@]}" "$api" \
    | jq -r --arg m "$major" '
        map(select(
          (.prerelease | not) and
          (if $m == "" then (.tag_name | startswith("bws-v"))
           else (.tag_name | startswith("bws-v" + $m + ".")) end)))
        | .[0].tag_name // empty
        | ltrimstr("bws-v")'
)"
if [ -z "$ver" ]; then
  echo "::error::no matching non-prerelease bws release found${major:+ for major ${major}}"
  exit 1
fi

# --- pick the release asset for this runner's OS/arch ---
os="$(uname -s)"
arch="$(uname -m)"
case "${os}-${arch}" in
  Linux-x86_64)        target="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64)       target="aarch64-unknown-linux-gnu" ;;
  Darwin-x86_64)       target="x86_64-apple-darwin" ;;
  Darwin-arm64)        target="aarch64-apple-darwin" ;;
  *) echo "::error::unsupported runner ${os}-${arch} for bws"; exit 1 ;;
esac

tmp="$(mktemp -d)"
url="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${ver}/bws-${target}-${ver}.zip"
echo "Installing bws ${ver} (${target})"
curl -fsSL -o "${tmp}/bws.zip" "$url"
unzip -o -q "${tmp}/bws.zip" -d "${tmp}/bin"
chmod +x "${tmp}/bin/bws"
echo "${tmp}/bin" >> "$GITHUB_PATH"   # on PATH for later steps
export PATH="${tmp}/bin:${PATH}"       # ...and for this step

# --- resolve each requested key by name and export it, masked ---
secrets_json="${tmp}/secrets.json"
list_args=()
[ -n "$INPUT_PROJECT_ID" ] && list_args=("$INPUT_PROJECT_ID")
bws secret list "${list_args[@]}" --output json > "$secrets_json"

while IFS= read -r raw; do
  name="$(printf '%s' "$raw" | tr -d '[:space:]')"
  [ -n "$name" ] || continue

  value="$(jq -r --arg k "$name" '.[] | select(.key == $k) | .value' "$secrets_json")"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "::error::Bitwarden secret '${name}' not found${INPUT_PROJECT_ID:+ in project ${INPUT_PROJECT_ID}}"
    exit 1
  fi

  printf '::add-mask::%s\n' "$value"
  # Heredoc form so multiline secret values survive intact.
  {
    printf '%s<<__BWS_EOF__\n' "$name"
    printf '%s\n' "$value"
    printf '__BWS_EOF__\n'
  } >> "$GITHUB_ENV"
  echo "loaded ${name}"
done <<< "$INPUT_NAMES"
