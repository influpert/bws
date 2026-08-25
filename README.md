# bws — load Bitwarden secrets by name (GitHub Action)

A composite GitHub Action that installs the [Bitwarden Secrets Manager CLI
(`bws`)](https://bitwarden.com/help/secrets-manager-cli/) and loads named
secrets from a project into `$GITHUB_ENV` (masked) for the rest of the job.

Unlike the official [`bitwarden/sm-action`](https://github.com/bitwarden/sm-action),
which addresses secrets by **UUID**, this action resolves them **by name (key)**
within a project — so your workflow references readable names, not opaque ids.

## Versioning contract

**The action's major version tracks the `bws` CLI major version, and there is
no version input.** The major is derived **dynamically** from how you reference
the action (`github.action_ref`) — there is no file to keep in sync with the tag.

```
uses: influpert/bws@v1   # installs the latest bws 1.x
uses: influpert/bws@v2   # installs the latest bws 2.x
```

Both lines are published and kept current automatically (see below). `@v2`
always installs the newest non-prerelease `bws-v2.x` release, `@v1` the newest
`bws-v1.x`, and `@v3` will install the latest `bws` 3.x once that exists. If you
pin by commit SHA (no major in the ref), the action recovers a version tag
pointing at that commit; if it can't, it installs the latest `bws` release
overall. See [Tag automation](#tag-automation).

## Usage

```yaml
- name: Load secrets from Bitwarden Secrets Manager
  uses: influpert/bws@v2
  with:
    access-token: ${{ secrets.BWS_ACCESS_TOKEN }}   # the only real secret
    project-id:   ${{ vars.BWS_PROJECT_ID }}         # a variable, not a secret
    names: |
      CLOUDFLARE_API_TOKEN
      TF_VAR_auth_token
      NPM_TOKEN

- name: Use them
  run: terraform apply -auto-approve   # TF_VAR_* etc. are now in the env
```

Each name in `names` must match a secret **key** in the Bitwarden project; the
action exports an environment variable of the same name (masked). A missing key
fails the step.

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `access-token` | yes | Bitwarden Secrets Manager access token. Keep it as the sole GitHub Actions secret. |
| `project-id` | no | Bitwarden project id to resolve names within (not sensitive — use a repo/org **variable**). If omitted, names are resolved across all projects the access token can see. |
| `names` | yes | Newline-separated secret keys to load. |
| `github-token` | no | Token for the release-lookup API call (defaults to `${{ github.token }}`). |

## Runner support

Linux and macOS, x86_64 and arm64 (the action detects OS/arch and downloads the
matching `bws` release). Windows runners are not supported.

## Security notes

- The only GitHub Actions **secret** you configure is `access-token`
  (`BWS_ACCESS_TOKEN`); everything else is pulled from Bitwarden at run time.
- Every loaded value is registered with `::add-mask::` before it reaches the
  log or `$GITHUB_ENV`.
- Pin this action by the `v2` tag (which the maintainer moves) or by commit SHA;
  it becomes part of your deploy supply chain.

## Tag automation

Tags are **fully automated** by [`.github/workflows/maintain-tags.yml`](.github/workflows/maintain-tags.yml)
(on push to `main`, weekly, or manual dispatch) — you never tag by hand. It
maintains the **current and previous** `bws` major: the latest upstream major and
the one before it (floored at `v1`). For each, it ensures the `vN` tag exists and
points at `main`. So:

- With `bws` at 2.x, both `v1` and `v2` are published and kept current.
- When `bws` ships a new major, its `vN` tag is created automatically and the
  window rolls forward (e.g. `bws` 3.x → maintains `v2` and `v3`).
- Tags for majors older than the window are left frozen where they last pointed.

## License

This Action installs and drives the Bitwarden Secrets Manager CLI, which is
proprietary. To avoid granting anything more permissive than Bitwarden does,
this repository is **not** offered under a permissive open-source license: it is
provided subject to the [Bitwarden Software Development Kit License Agreement](https://github.com/bitwarden/sdk-sm/blob/main/LICENSE),
and confers no rights broader than that Agreement grants. See [LICENSE](LICENSE).
