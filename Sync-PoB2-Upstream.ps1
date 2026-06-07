<#
.SYNOPSIS
    Sync official Path of Building 2 dev into this repo's custom branch.

.DESCRIPTION
    One-command sync for this standalone custom copy:
      1. Ensures the official upstream remote exists.
      2. Fetches upstream/dev.
      3. Creates or fast-forwards local dev from upstream/dev.
      4. Merges dev into local custom.
      5. Pushes local custom to origin/custom.

    Untracked files are allowed. Tracked local edits are blocked so branch switches
    and merges do not overwrite work in progress.

.EXAMPLE
    .\Sync-PoB2-Upstream.ps1

.EXAMPLE
    .\Sync-PoB2-Upstream.ps1 -NoPush
#>
[CmdletBinding()]
param(
    [string]$OriginName = 'origin',
    [string]$OriginBranch = 'custom',
    [string]$UpstreamName = 'upstream',
    [string]$UpstreamBranch = 'dev',
    [string]$UpstreamUrl = 'https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2.git',
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

function Info($Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Ok($Message) { Write-Host "OK  $Message" -ForegroundColor Green }
function Warn($Message) { Write-Host "!!  $Message" -ForegroundColor Yellow }
function Fail($Message) { Write-Host "ERR $Message" -ForegroundColor Red; exit 1 }

try {
    $repoRoot = git rev-parse --show-toplevel
} catch {
    Fail "Run this from inside C:\Dev\repos\PoB2-Custom."
}

Set-Location $repoRoot

$trackedChanges = git status --porcelain --untracked-files=no
if ($trackedChanges) {
    Warn "Tracked local changes are present:"
    $trackedChanges | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Fail "Commit or stash tracked changes first, then run this script again. Untracked files are OK."
}

$remotes = @(git remote)
if ($remotes -notcontains $OriginName) {
    Fail "Remote '$OriginName' was not found. Add your repo remote first."
}

if ($remotes -notcontains $UpstreamName) {
    Info "Adding official upstream remote..."
    git remote add $UpstreamName $UpstreamUrl
    Ok "Added '$UpstreamName' -> $UpstreamUrl."
}

$upstreamActualUrl = git remote get-url $UpstreamName
if ($upstreamActualUrl -ne $UpstreamUrl) {
    Warn "Remote '$UpstreamName' points to: $upstreamActualUrl"
    Warn "Expected official upstream: $UpstreamUrl"
    Fail "Fix the upstream URL or re-run with -UpstreamUrl if this is intentional."
}

Info "Fetching '$UpstreamName' and '$OriginName'..."
git fetch $UpstreamName --prune
git fetch $OriginName --prune

$upstreamRef = "$UpstreamName/$UpstreamBranch"
$originRef = "$OriginName/$OriginBranch"

git rev-parse --verify --quiet $upstreamRef | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "Could not find '$upstreamRef'."
}

$startBranch = git rev-parse --abbrev-ref HEAD

Info "Updating local '$UpstreamBranch' from '$upstreamRef'..."
$localMirrorExists = $true
git rev-parse --verify --quiet "refs/heads/$UpstreamBranch" | Out-Null
if ($LASTEXITCODE -ne 0) {
    $localMirrorExists = $false
}

if ($localMirrorExists) {
    git checkout $UpstreamBranch
    $before = git rev-parse HEAD
    git merge --ff-only $upstreamRef
    if ($LASTEXITCODE -ne 0) {
        git checkout $startBranch | Out-Null
        Fail "Local '$UpstreamBranch' has diverged. Move any work off it, then reset it to '$upstreamRef'."
    }
} else {
    git checkout -B $UpstreamBranch $upstreamRef
    $before = git rev-parse HEAD
}

$after = git rev-parse HEAD
$pulled = git rev-list --count "$before..$after"
Ok "Local '$UpstreamBranch' now matches official '$upstreamRef' ($pulled new commit(s))."

Info "Checking out local '$OriginBranch'..."
$localWorkExists = $true
git rev-parse --verify --quiet "refs/heads/$OriginBranch" | Out-Null
if ($LASTEXITCODE -ne 0) {
    $localWorkExists = $false
}

if ($localWorkExists) {
    git checkout $OriginBranch
} else {
    git rev-parse --verify --quiet $originRef | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "Could not find local '$OriginBranch' or remote '$originRef'."
    }
    git checkout -B $OriginBranch $originRef
}

Info "Merging official '$UpstreamBranch' into local '$OriginBranch'..."
git merge --no-edit $UpstreamBranch
if ($LASTEXITCODE -ne 0) {
    Warn "Merge conflicts need manual resolution."
    Warn "After resolving conflicts, run:"
    Warn "    git add <files>"
    Warn "    git commit"
    Warn "    git push $OriginName ${OriginBranch}:${OriginBranch}"
    Fail "Stopped with merge in progress."
}

Ok "Merged official '$UpstreamBranch' into local '$OriginBranch'."

if ($NoPush) {
    Warn "Skipped push because -NoPush was used."
    Warn "Push later with: git push $OriginName ${OriginBranch}:${OriginBranch}"
} else {
    Info "Pushing local '$OriginBranch' to '$OriginName/$OriginBranch'..."
    git push $OriginName "${OriginBranch}:${OriginBranch}"
    Ok "Pushed '$OriginBranch' to '$OriginName/$OriginBranch'."
}

Write-Host ""
Ok "Sync complete."
