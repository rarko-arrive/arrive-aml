#!/usr/bin/env bash
set -euo pipefail

# End-to-end "new team member" test, safe to run on any compute instance.
#
#   bash tests/sandbox-new-user.sh            # runs as Colin Tracy (ctracy)
#   KEEP=1 bash tests/sandbox-new-user.sh     # keep the sandbox for inspection
#
# Everything happens in a throwaway directory: its own HOME, its own fake
# workspace share (cloudfiles/code/Users/ctracy), its own /mnt, and a fake
# GitHub made of local bare repos (git url.insteadOf). The repos under test are
# built from THIS working tree, uncommitted changes included. Your real home,
# share, mirrors and GitHub are never touched (checked at the end).
#
# Covers: get-started.sh on an empty share -> wizard (answered over a real pty)
# -> bootstrap (tools skipped: they are system-wide, not per user) -> identity
# in git -> mirrors + sync hooks -> commit reaches the SOT -> /mnt wipe +
# --restore -> quiet re-run -> a second VM that asks nothing -> --add of a
# personal repo -> no trace of another user in anything generated.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVE="python3 ${REPO_ROOT}/tests/lib/drive_tty.py"

T_USER="ctracy"
T_NAME="Colin Tracy"
T_EMAIL="ctracy@arrivelogistics.com"
T_ORG="rarko-arrive"          # team default org; the fake GitHub serves it
T_INSTANCE="ctracy1"
# Strings that must never appear in what setup generates for someone else
FOREIGN_RE='Rick Arko|rarko@|Users/rarko|/rarko/|rarko[0-9]'

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '\033[0;32m  PASS\033[0m %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf '\033[0;31m  FAIL\033[0m %s\n' "$*"; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
section() { printf '\n\033[1;34m### %s\033[0m\n' "$*"; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/arrive-sandbox.XXXXXX")"
cleanup() {
  if [ "${KEEP:-}" = "1" ] || [ "$FAIL" -gt 0 ]; then
    echo "sandbox kept: $SB"
  else
    rm -rf "$SB"
  fi
}
trap cleanup EXIT

# Fingerprint of the real user's setup, compared at the end
real_fingerprint() {
  {
    cat "${HOME}/.gitconfig" 2>/dev/null || true
    cat "${HOME}/.config/arrive-aml/env" 2>/dev/null || true
    ls -la "${HOME}/.claude/skills" 2>/dev/null || true
  } | sha256sum | cut -d' ' -f1
}
REAL_BEFORE="$(real_fingerprint)"
REAL_HOME="$HOME"

section "Sandbox: $SB"
S_HOME="$SB/home"
USERS="$S_HOME/cloudfiles/code/Users"
FAKE_GH="$SB/github"
mkdir -p "$S_HOME" "$USERS/$T_USER" "$USERS/someone-else/main" "$FAKE_GH/$T_ORG" "$FAKE_GH/someorg" "$SB/bin" "$SB/mnt"
printf 'instance=%s\n' "$T_INSTANCE" > "$S_HOME/cloudfiles/.nbvm"

# --- fake GitHub -------------------------------------------------------------
# arrive-aml = this working tree (tracked + untracked, not ignored) as one commit
snap="$SB/snapshot"
mkdir -p "$snap"
(cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
  [ -e "$f" ] || continue
  mkdir -p "$snap/$(dirname "$f")"; cp -p "$f" "$snap/$f"
done)
git -C "$snap" init -q -b main
git -C "$snap" add -A
git -C "$snap" -c user.name=sandbox -c user.email=sandbox@example.invalid commit -q -m "arrive-aml under test"
git clone -q --bare "$snap" "$FAKE_GH/$T_ORG/arrive-aml.git"

make_repo() {   # make_repo org/name [pyproject]
  local d="$SB/src/$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  echo "# $1" > "$d/README.md"
  if [ "${2:-}" = pyproject ]; then
    printf '[project]\nname = "%s"\nversion = "0.0.0"\nrequires-python = ">=3.10"\ndependencies = []\n\n[tool.uv]\npackage = false\n' "$(basename "$1")" > "$d/pyproject.toml"
  elif [ "${2:-}" = requirements ]; then
    # Airflow/Astro style: pyproject holds only tool config, deps in requirements.txt
    printf '[tool.black]\nline-length = 100\n' > "$d/pyproject.toml"
    printf '# no dependencies\n' > "$d/requirements.txt"
  fi
  mkdir -p "$d/skills/work-in-repo"
  [ "$(basename "$1")" != azureml-skills ] || printf -- '---\nname: work-in-repo\ndescription: sandbox copy\n---\n' > "$d/skills/work-in-repo/SKILL.md"
  git -C "$d" add -A
  git -C "$d" -c user.name=sandbox -c user.email=sandbox@example.invalid commit -q -m init
  git clone -q --bare "$d" "$FAKE_GH/$1.git"
}
make_repo "$T_ORG/azureml-skills"
make_repo "$T_ORG/arrive-ds" pyproject
make_repo "someorg/extra-repo" requirements
make_repo "someorg/another-repo"

# fake gh: logged out until `gh auth login` runs
cat > "$SB/bin/gh" <<GH
#!/usr/bin/env bash
state="$SB/gh-authed"
case "\$1 \${2:-}" in
  "auth status") [ -f "\$state" ] ;;
  "auth login") echo "! First copy your one-time code: FAKE-1234"; echo "✓ Logged in as $T_USER"; touch "\$state" ;;
  "auth setup-git") exit 0 ;;
  "api user") [ -f "\$state" ] || exit 1; case "\$*" in *login*) echo "$T_USER" ;; *) echo "" ;; esac ;;
  "ssh-key list") exit 0 ;;
  "ssh-key add") exit 0 ;;
  *) exit 0 ;;
esac
GH
chmod +x "$SB/bin/gh"

# The sandbox user's environment: a fresh VM with an empty home
s_env() {
  env -i \
    HOME="$S_HOME" USER="$(id -un)" LOGNAME="$(id -un)" TERM=xterm \
    PATH="$SB/bin:${REAL_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    TMPDIR="$SB" \
    MIRROR_BASE="$SB/mnt/mirror" UV_VENV_ROOT="$SB/mnt/uv-venvs" \
    ARRIVE_UV_CACHE_DIR="${ARRIVE_UV_CACHE_DIR:-/mnt/uv-cache}" UV_CACHE_DIR="${ARRIVE_UV_CACHE_DIR:-/mnt/uv-cache}" \
    ARRIVE_GIT_PROTOCOL=https ARRIVE_NO_SELF_UPDATE=1 UV_LINK_MODE=copy \
    GIT_CONFIG_NOSYSTEM=1 \
    "$@"
}
# Route github.com to the fake GitHub for this HOME only
s_env git config --global url."$FAKE_GH/".insteadOf "https://github.com/"
s_env git config --global --add url."$FAKE_GH/".insteadOf "git@github.com:"
SOT="$USERS/$T_USER/main"
M="$SB/mnt/mirror"
LOG="$SB/run.log"

# --- 1. first run: get-started + wizard ---------------------------------------
section "1. New user on an empty share: get-started.sh + wizard"
rc=0
s_env ARRIVE_AML_URL="https://github.com/$T_ORG/arrive-aml.git" \
  $DRIVE --timeout 900 \
    --expect 'Your folder name \[ctracy\]' '' \
    --expect 'Your full name' "$T_NAME" \
    --expect "Your work email \\[$T_EMAIL\\]" '' \
    --expect 'Look right\?' '' \
    -- bash "$REPO_ROOT/scripts/get-started.sh" --skip-tools > "$LOG" 2>&1 || rc=$?
check "get-started + bootstrap finished (rc=$rc; verify may flag system tools)" test "$rc" -ne 124 -a "$rc" -ne 125
check "welcome banner shown on first run" grep -q "Welcome to arrive-aml" "$LOG"
check "folder guessed from instance name ($T_INSTANCE -> $T_USER)" grep -q "Your folder name \[$T_USER\]" "$LOG"
check "email suggested from folder name" grep -q "Your work email \[$T_EMAIL\]" "$LOG"
check "arrive-aml cloned to the new user's share" test -d "$SOT/arrive-aml/.git"
check "nothing written to another user's folder" test -z "$(ls -A "$USERS/someone-else/main")"

# configure-git.sh is part of the (skipped) tools step; run just that piece
s_env bash "$SOT/arrive-aml/scripts/lib/configure-git.sh" >> "$LOG" 2>&1 || true

section "2. Identity"
check "git user.name = $T_NAME" test "$(s_env git config --global user.name)" = "$T_NAME"
check "git user.email = $T_EMAIL" test "$(s_env git config --global user.email)" = "$T_EMAIL"
ENVF="$S_HOME/.config/arrive-aml/env"
check "env file has the name" grep -qx "ARRIVE_USER_NAME=\"$T_NAME\"" "$ENVF"
check "env file has the SOT base" grep -qx "ARRIVE_SOT_BASE=\"$SOT\"" "$ENVF"
check "org not pinned (team default can move)" bash -c "! grep -q '^ARRIVE_GITHUB_ORG=' '$ENVF'"
check "profile saved on the share for other VMs" grep -q "ARRIVE_USER_EMAIL=\"$T_EMAIL\"" "$SOT/.arrive-aml/profile"

section "3. Repos, mirrors, venvs, skills"
for r in arrive-aml azureml-skills arrive-ds; do
  check "$r: SOT clone" test -d "$SOT/$r/.git"
  check "$r: mirror clone" test -d "$M/$r/.git"
  check "$r: sot remote -> share" test "$(git -C "$M/$r" remote get-url sot 2>/dev/null)" = "$SOT/$r"
  check "$r: sync hooks" test -x "$M/$r/.git/hooks/arrive-aml-sync-sot"
done
check "arrive-ds: venv on local disk" test -x "$M/arrive-ds/.venv/bin/python"
check "skill linked into ~/.claude/skills" test -f "$S_HOME/.claude/skills/work-in-repo/SKILL.md"
check "aml-bootstrap shim installed" test -x "$S_HOME/.local/bin/aml-bootstrap"
check "bashrc managed block" grep -q ">>> arrive-aml" "$S_HOME/.bashrc"

section "4. Daily loop: commit in the mirror reaches the SOT"
s_env bash -c "cd '$M/arrive-ds' && git checkout -q -b feature/sandbox-test && echo hi > sandbox.txt && git add sandbox.txt && git commit -q -m 'test: sandbox commit'" >> "$LOG" 2>&1 || true
author="$(git -C "$M/arrive-ds" log -1 --format='%an <%ae>' 2>/dev/null || true)"
check "commit authored as $T_NAME <$T_EMAIL>" test "$author" = "$T_NAME <$T_EMAIL>"
synced=false
for _ in $(seq 1 30); do
  if git -C "$SOT/arrive-ds" show-ref -q --verify refs/heads/feature/sandbox-test; then synced=true; break; fi
  sleep 1
done
check "hook pushed the branch to the SOT" test "$synced" = true

section "5. VM restart: /mnt wiped, --restore brings it back"
rm -rf "$SB/mnt/mirror" "$SB/mnt/uv-venvs"
rc=0
s_env bash "$SOT/arrive-aml/scripts/bootstrap.sh" --restore --no-verify < /dev/null >> "$LOG" 2>&1 || rc=$?
check "restore exited 0 (rc=$rc)" test "$rc" -eq 0
for r in arrive-aml azureml-skills arrive-ds; do
  check "$r: mirror back" test -d "$M/$r/.git"
done
check "SOT-only branch fetched back into the mirror" git -C "$M/arrive-ds" show-ref -q --verify refs/remotes/sot/feature/sandbox-test
check "venv rebuilt" test -x "$M/arrive-ds/.venv/bin/python"

section "6. Re-runs never nag"
out="$(s_env $DRIVE --timeout 60 -- bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" 2>&1)" || true
check "second run on a terminal asks nothing" bash -c "! grep -q 'Your full name' <<<\"\$1\"" _ "$out"
check "second run greets the saved user" grep -q "Setting up for $T_NAME" <<<"$out"
out="$(s_env bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" --yes < /dev/null 2>&1)" || true
check "--yes without a terminal does not block" grep -q "Setting up for $T_NAME" <<<"$out"

section "7. A second VM on the same share asks nothing"
S2="$SB/home2"
mkdir -p "$S2"
ln -s "$S_HOME/cloudfiles" "$S2/cloudfiles"
out="$(env -i HOME="$S2" TERM=xterm PATH="$SB/bin:/usr/bin:/bin" ARRIVE_SOT_BASE="$SOT" GIT_CONFIG_NOSYSTEM=1 \
  $DRIVE --timeout 60 -- bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" 2>&1)" || true
check "identity read from the share profile" grep -q "Setting up for $T_NAME <$T_EMAIL>" <<<"$out"
check "no questions on the second VM" bash -c "! grep -q 'Your full name' <<<\"\$1\"" _ "$out"
check "second VM git identity set" test "$(HOME="$S2" GIT_CONFIG_NOSYSTEM=1 git config --global user.email)" = "$T_EMAIL"

section "8. GitHub login step (gh stubbed)"
out="$(s_env $DRIVE --timeout 60 -- bash -c "source '$SOT/arrive-aml/scripts/lib/configure-github-ssh.sh'; ensure_gh_login" 2>&1)" || true
check "explains the device-code login" grep -q "github.com/login/device" <<<"$out"
check "runs gh auth login and reports the user" grep -q "logged in as @$T_USER" <<<"$out"
check "GitHub user saved" grep -qx "ARRIVE_GITHUB_USER=\"$T_USER\"" "$ENVF"

section "9. Personal repo via --add"
rc=0
s_env bash "$SOT/arrive-aml/scripts/setup-repos.sh" --add someorg/extra-repo < /dev/null >> "$LOG" 2>&1 || rc=$?
check "--add exited 0 (rc=$rc)" test "$rc" -eq 0
check "extra repo mirrored" test -d "$M/extra-repo/.git"
check "requirements.txt-only repo gets a venv" test -x "$M/extra-repo/.venv/bin/python"
check "recorded in personal repos.conf" grep -q "^someorg/extra-repo|extra-repo|yes" "$S_HOME/.config/arrive-aml/repos.conf"
check "team repos.conf unchanged" bash -c "! grep -q extra-repo '$SOT/arrive-aml/repos.conf'"
out="$(s_env bash -c ". '$ENVF'; ARRIVE_LOGIN_RESTORE_LIBRARY=1 . '$SOT/arrive-aml/scripts/lib/login-restore.sh'; rm -rf '$M/extra-repo'; arrive_mirrors_ready && echo READY || echo MISSING")"
check "login auto-restore notices a missing personal mirror" test "$out" = MISSING

section "10. Changing your mind: --configure"
out="$(s_env $DRIVE --timeout 60 \
    --expect 'Your full name' '' \
    --expect 'Your work email' '' \
    --expect 'Team GitHub org' 'Arrive-Logistics' \
    --expect 'Extra repos' 'someorg/another-repo' \
    --expect 'Look right\?' 'n' \
    --expect 'Your full name' '' \
    --expect 'Your work email' '' \
    --expect 'Team GitHub org' "$T_ORG" \
    --expect 'Extra repos' '' \
    --expect 'Look right\?' '' \
    -- bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" --reconfigure 2>&1)" || true
check "--configure shows the current values as defaults" grep -q "Your full name (for git commits) \[$T_NAME\]" <<<"$out"
check "answering n asks again" test "$(grep -c 'Look right' <<<"$out")" -eq 2
check "back on the team default org: not pinned" bash -c "! grep -q '^ARRIVE_GITHUB_ORG=' '$ENVF'"
check "extra repo from the wizard recorded" grep -q "^someorg/another-repo|another-repo|yes" "$S_HOME/.config/arrive-aml/repos.conf"
out="$(s_env bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" --yes --github-org Arrive-Logistics < /dev/null 2>&1)" || true
check "--github-org pins a non-default org" grep -qx 'ARRIVE_GITHUB_ORG="Arrive-Logistics"' "$ENVF"
check "{org} now resolves to it" test "$(s_env bash -c "source '$SOT/arrive-aml/scripts/lib/common.sh'; repo_url '{org}/arrive-ds'")" = "https://github.com/Arrive-Logistics/arrive-ds.git"
s_env bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" --yes --github-org "$T_ORG" < /dev/null > /dev/null 2>&1 || true
out="$(s_env bash "$SOT/arrive-aml/scripts/lib/configure-user.sh" --yes --email not-an-email < /dev/null 2>&1)" && rc=0 || rc=$?
check "a bad --email is rejected" test "$rc" -ne 0

section "11. No trace of another user"
leaks="$(grep -rIlE "$FOREIGN_RE" "$S_HOME/.config" "$S_HOME/.bashrc" "$S_HOME/.local/bin" "$S_HOME/.gitconfig" \
  "$SOT/.arrive-aml" "$S_HOME/.ssh" 2>/dev/null || true)"
check "generated files mention nobody else${leaks:+ (found in: $leaks)}" test -z "$leaks"
check "your real setup is untouched" test "$(real_fingerprint)" = "$REAL_BEFORE"

section "12. verify-setup.sh as the new user"
s_env bash "$SOT/arrive-aml/scripts/bootstrap.sh" --restore --no-verify < /dev/null >> "$LOG" 2>&1 || true
check "restore also brings back personal repos" test -d "$M/extra-repo/.git" -a -d "$M/another-repo/.git"
out="$(s_env bash "$SOT/arrive-aml/scripts/verify-setup.sh" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" || true
failed="$(sed -n '/required check(s) failed/,$p' <<<"$out" | grep '^  - ' | sed 's/^  - //' || true)"
check "identity check passes" grep -q "user: $T_NAME <$T_EMAIL>" <<<"$out"
check "all mirrors verified" test "$(grep -c ': mirror ' <<<"$out")" -ge 3
check "only failure left needs a real GitHub account (SSH key)${failed:+: $(tr '\n' ';' <<<"$failed")}" \
  test "$(grep -v 'GitHub SSH' <<<"$failed" | grep -c . || true)" -eq 0

echo
printf '\033[1m%d passed, %d failed\033[0m   (full log: %s)\n' "$PASS" "$FAIL" "$LOG"
[ "$FAIL" -eq 0 ]
