# Upstream sync

This is a **standalone copy** of [PathOfBuilding-PoE2](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2)
(not a GitHub fork). Your custom work lives on the **`custom`** branch; **`dev`** is kept as a
clean mirror of the official `dev` and should never be committed to directly.

## Remotes

| Remote     | Points to                                                      |
|------------|----------------------------------------------------------------|
| `origin`   | your copy — `github.com/maxdribny/PoB2-Custom`                 |
| `upstream` | official — `PathOfBuildingCommunity/PathOfBuilding-PoE2`        |

## Pulling in the latest official changes

**Windows (PowerShell):**

```powershell
./sync/Sync-Upstream.ps1
```

**Git Bash / WSL / Linux / macOS:**

```bash
bash sync/sync-upstream.sh
```

What it does:

1. Fetches `upstream`.
2. Fast-forwards your local `dev` to match `upstream/dev` and pushes it to `origin`.
3. Merges `dev` into `custom` and pushes `custom` to `origin`.

### Options

- Preview without pushing: `-NoPush` (PowerShell) or `--no-push` (bash).
- Different branch names: `-MirrorBranch` / `-WorkBranch` (PowerShell) or `-m` / `-w` (bash).

### If there are merge conflicts

The script stops and leaves the merge in progress. Resolve the conflicted files, then:

```bash
git add <files>
git commit
git push origin custom
```

Or abandon the merge with `git merge --abort`.

## Golden rule

Never commit on `dev`. If you accidentally do, the fast-forward step will refuse to run; the
script prints how to recover (move the commits to `custom`, then
`git reset --hard upstream/dev`).
