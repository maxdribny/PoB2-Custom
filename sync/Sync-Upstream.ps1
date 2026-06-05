<#
.SYNOPSIS
    Sync this personal copy of Path of Building (PoE2) with the official upstream repo.

.DESCRIPTION
    Fetches the official 'upstream' repo, fast-forwards the local mirror branch (default
    'dev') to match upstream, pushes it to your 'origin', then merges those changes into
    your working branch (default 'custom'). Stops cleanly on merge conflicts with
    instructions for resolving them.

    Expected remote layout:
        origin   -> your copy        (e.g. github.com/maxdribny/PoB2-Custom)
        upstream -> official repo     (PathOfBuildingCommunity/PathOfBuilding-PoE2)

.PARAMETER MirrorBranch
    Branch kept as a pristine mirror of upstream. Default: 'dev'. Never commit to it.

.PARAMETER WorkBranch
    Your working branch that receives upstream updates. Default: 'custom'.

.PARAMETER NoPush
    Do everything locally but do not push to origin (preview mode).

.EXAMPLE
    ./sync/Sync-Upstream.ps1
.EXAMPLE
    ./sync/Sync-Upstream.ps1 -NoPush
#>
[CmdletBinding()]
param(
    [string]$MirrorBranch = 'dev',
    [string]$WorkBranch   = 'custom',
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

function Info($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "OK  $msg"  -ForegroundColor Green }
function Warn($msg)  { Write-Host "!!  $msg"  -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "ERR $msg"  -ForegroundColor Red; exit 1 }

# Must be run from inside the git repo.
try { $repoRoot = (git rev-parse --show-toplevel) } catch { Fail "Not inside a git repository." }
Set-Location $repoRoot

# Verify required remotes exist.
$remotes = git remote
if ($remotes -notcontains 'upstream') { Fail "Remote 'upstream' not found. Add it: git remote add upstream https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2.git" }
if ($remotes -notcontains 'origin')   { Fail "Remote 'origin' not found." }

# Refuse to run with a dirty working tree.
if (git status --porcelain) {
    Fail "Working tree has uncommitted changes. Commit or stash them first (git stash), then re-run."
}

$startBranch = git rev-parse --abbrev-ref HEAD

Info "Fetching upstream..."
git fetch upstream --prune

Info "Updating mirror branch '$MirrorBranch' from upstream/$MirrorBranch (fast-forward only)..."
git checkout $MirrorBranch
# Capture before/after to report how many commits arrived.
$before = git rev-parse HEAD
git merge --ff-only "upstream/$MirrorBranch"
if ($LASTEXITCODE -ne 0) {
    Warn "Could not fast-forward '$MirrorBranch'. It has diverged from upstream (you likely committed to it directly)."
    Warn "Recover by moving those commits to '$WorkBranch', then reset: git checkout $MirrorBranch; git reset --hard upstream/$MirrorBranch"
    git checkout $startBranch | Out-Null
    Fail "Aborted: '$MirrorBranch' must stay a clean mirror of upstream."
}
$after = git rev-parse HEAD
$pulled = (git rev-list --count "$before..$after")
Ok "Mirror '$MirrorBranch' updated ($pulled new commit(s) from upstream)."

if (-not $NoPush) {
    Info "Pushing '$MirrorBranch' to origin..."
    git push origin $MirrorBranch
}

Info "Merging '$MirrorBranch' into work branch '$WorkBranch'..."
git checkout $WorkBranch
git merge --no-edit $MirrorBranch
if ($LASTEXITCODE -ne 0) {
    Warn "Merge produced conflicts. The merge is left in progress."
    Warn "Resolve them, then run:"
    Warn "    git add <files> ; git commit ; git push origin $WorkBranch"
    Warn "Or abort entirely with: git merge --abort"
    Fail "Stopped for manual conflict resolution."
}
Ok "Merged upstream changes into '$WorkBranch'."

if (-not $NoPush) {
    Info "Pushing '$WorkBranch' to origin..."
    git push origin $WorkBranch
    Ok "Pushed '$WorkBranch' to origin."
} else {
    Warn "Skipped push (-NoPush). Review, then: git push origin $MirrorBranch ; git push origin $WorkBranch"
}

Write-Host ""
Ok "Sync complete. $pulled upstream commit(s) integrated into '$WorkBranch'."
