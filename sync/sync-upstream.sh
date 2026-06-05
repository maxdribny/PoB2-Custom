#!/usr/bin/env bash
#
# Sync this personal copy of Path of Building (PoE2) with the official upstream repo.
#
# Fetches the official 'upstream' remote, fast-forwards the local mirror branch
# (default 'dev') to match upstream, pushes it to 'origin', then merges those changes
# into the working branch (default 'custom'). Stops cleanly on merge conflicts.
#
# Expected remote layout:
#     origin   -> your copy     (e.g. github.com/maxdribny/PoB2-Custom)
#     upstream -> official repo (PathOfBuildingCommunity/PathOfBuilding-PoE2)
#
# Usage:
#     bash sync/sync-upstream.sh [-m MIRROR_BRANCH] [-w WORK_BRANCH] [--no-push]
#
set -euo pipefail

MIRROR_BRANCH="dev"
WORK_BRANCH="custom"
PUSH=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--mirror) MIRROR_BRANCH="$2"; shift 2 ;;
        -w|--work)   WORK_BRANCH="$2";   shift 2 ;;
        --no-push)   PUSH=0;             shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

info() { printf '\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32mOK  %s\033[0m\n' "$1"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$1"; }
fail() { printf '\033[31mERR %s\033[0m\n' "$1" >&2; exit 1; }

# Must be inside the git repo.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "Not inside a git repository."
cd "$REPO_ROOT"

# Verify required remotes.
git remote | grep -qx upstream || fail "Remote 'upstream' not found. Add it: git remote add upstream https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2.git"
git remote | grep -qx origin   || fail "Remote 'origin' not found."

# Refuse to run with a dirty working tree.
[[ -z "$(git status --porcelain)" ]] || fail "Working tree has uncommitted changes. Commit or stash them first (git stash), then re-run."

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

info "Fetching upstream..."
git fetch upstream --prune

info "Updating mirror branch '$MIRROR_BRANCH' from upstream/$MIRROR_BRANCH (fast-forward only)..."
git checkout "$MIRROR_BRANCH"
BEFORE="$(git rev-parse HEAD)"
if ! git merge --ff-only "upstream/$MIRROR_BRANCH"; then
    warn "Could not fast-forward '$MIRROR_BRANCH'. It has diverged from upstream (you likely committed to it directly)."
    warn "Recover by moving those commits to '$WORK_BRANCH', then: git checkout $MIRROR_BRANCH && git reset --hard upstream/$MIRROR_BRANCH"
    git checkout "$START_BRANCH" >/dev/null 2>&1 || true
    fail "Aborted: '$MIRROR_BRANCH' must stay a clean mirror of upstream."
fi
AFTER="$(git rev-parse HEAD)"
PULLED="$(git rev-list --count "$BEFORE..$AFTER")"
ok "Mirror '$MIRROR_BRANCH' updated ($PULLED new commit(s) from upstream)."

if [[ "$PUSH" -eq 1 ]]; then
    info "Pushing '$MIRROR_BRANCH' to origin..."
    git push origin "$MIRROR_BRANCH"
fi

info "Merging '$MIRROR_BRANCH' into work branch '$WORK_BRANCH'..."
git checkout "$WORK_BRANCH"
if ! git merge --no-edit "$MIRROR_BRANCH"; then
    warn "Merge produced conflicts. The merge is left in progress."
    warn "Resolve them, then run:"
    warn "    git add <files> && git commit && git push origin $WORK_BRANCH"
    warn "Or abort entirely with: git merge --abort"
    fail "Stopped for manual conflict resolution."
fi
ok "Merged upstream changes into '$WORK_BRANCH'."

if [[ "$PUSH" -eq 1 ]]; then
    info "Pushing '$WORK_BRANCH' to origin..."
    git push origin "$WORK_BRANCH"
    ok "Pushed '$WORK_BRANCH' to origin."
else
    warn "Skipped push (--no-push). Review, then: git push origin $MIRROR_BRANCH && git push origin $WORK_BRANCH"
fi

echo ""
ok "Sync complete. $PULLED upstream commit(s) integrated into '$WORK_BRANCH'."
