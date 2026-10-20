#==============================================================================
# setup-overlay.ps1 — Copy overlay files to workspace .github
#==============================================================================
# From any overlay source directory, this script copies various files from the
# overlay to all workspace .github directories. The source may, but need not,
# belong to a Git repository:
#
# 1. When non-empty, every file and sub-directory from overlays/workspace is
#    copied recursively into .github/ (root files flatten to .github/; agents/,
#    prompts/, skills/, docs/, ... copy as-is). A targeted non-empty repo tier
#    may be applied when this workspace tier is absent or empty.
# 2. When a specific repository is targeted (-RepoName), the same copy is
#    repeated for overlays/repo/<RepoName>, layered on top of overlays/workspace
#    when that tier is present or directly on the existing base when it is not.
#    The repo tier reads ONLY that per-repo subdirectory (no fallback to a flat
#    overlays/repo). It is skipped silently when the subdirectory is missing or
#    has no content beyond .gitkeep.
# 3. When -LocalPath (or the AI_LOCAL_TIER environment variable) is supplied, the
#    local overlay tier at that path (absolute or relative to the current
#    directory) is copied LAST, overwriting the overlay assets so personal/local
#    files win. Skipped when the source is missing/empty.
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup-overlay.ps1 `
#     -OverlayPath "<FRAMEWORK_HOME>\overlays" -BasePath "<WORKSPACE_PROJECTS_ROOT>" [-WorkspaceName "workspace_name"] [-RepoName "repo_name"] [-LocalPath "C:\my\local"]
#==============================================================================

param(
    [string]$OverlayPath = "",
    [string]$BasePath = "<WORKSPACE_PROJECTS_ROOT>",
    [string]$WorkspaceName = "",
    [string]$RepoName = "",
    [string]$LocalPath = "",
    [switch]$Verbose,
    [switch]$SkipClaude
)

# -SkipClaude (or AI_SKIP_CLAUDE=1 from install.bat) suppresses the .claude/CLAUDE.md
# dual-platform mirror so overlay assets only update the Copilot (.github) layout.
if (-not $SkipClaude -and $env:AI_SKIP_CLAUDE -eq '1') { $SkipClaude = $true }

$ErrorActionPreference = "Stop"

# Validation
if ([string]::IsNullOrWhiteSpace($OverlayPath)) {
    Write-Host "ERROR: -OverlayPath parameter is required" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $OverlayPath)) {
    Write-Host "ERROR: Overlay path does not exist: $OverlayPath" -ForegroundColor Red
    exit 1
}

$overlayRootPath = Join-Path -Path $OverlayPath -ChildPath "overlays"
if (-not (Test-Path -LiteralPath $overlayRootPath -PathType Container)) {
    Write-Host "ERROR: Overlay source path must contain an overlays/ directory: $OverlayPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $BasePath)) {
    Write-Host "ERROR: Base path does not exist: $BasePath" -ForegroundColor Red
    exit 1
}

# Shared Copilot -> Claude Code transform functions (dual-platform mirror),
# identical to the ones used by setup-workspace.ps1 for base assets.
. (Join-Path -Path $PSScriptRoot -ChildPath "claude-mirror-lib.ps1")

function Log-Message {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = "White"
    if ($Level -eq "WARN") { $color = "Yellow" }
    if ($Level -eq "ERROR") { $color = "Red" }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Assert-SafePathSegment {
    param(
        [string]$Value,
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -in @('.', '..') -or
        [System.IO.Path]::IsPathRooted($Value) -or $Value.IndexOfAny(@([char]'\', [char]'/')) -ge 0 -or
        $Value.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "$ParameterName must be one non-empty directory name without path separators or traversal segments."
    }
}

function Get-ContainedPath {
    param(
        [string]$Root,
        [string]$Child,
        [string]$Description
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $childFull = [System.IO.Path]::GetFullPath((Join-Path -Path $rootFull -ChildPath $Child))
    $requiredPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes its allowed root '$rootFull'."
    }
    return $childFull
}

function Get-OverlayIdentityHash {
    param(
        [string]$OverlayPath,
        [string]$OverlaySubtree
    )

    $sourceIdentity = ([System.IO.Path]::GetFullPath($OverlayPath).TrimEnd('\', '/') + '|' + $OverlaySubtree.Replace('\', '/')).ToLowerInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $identityBytes = [System.Text.Encoding]::UTF8.GetBytes($sourceIdentity)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($identityBytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-FileSha256 {
    param([string]$LiteralPath)

    $stream = [System.IO.File]::OpenRead($LiteralPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Read-ValidatedOverlayManifest {
    param(
        [string]$ManifestPath,
        [string]$ExpectedSourceId,
        [string]$GithubDir
    )

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schema -ne 2) {
        throw "Overlay ownership manifest '$ManifestPath' has an unsupported schema."
    }
    if ([string]$manifest.source_id -cne $ExpectedSourceId) {
        throw "Overlay ownership manifest '$ManifestPath' does not belong to the expected source."
    }

    $seenPaths = @{}
    foreach ($entry in @($manifest.files)) {
        $relativePath = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [System.IO.Path]::IsPathRooted($relativePath) -or
            (Test-ReservedOverlayPath -RelativePath $relativePath) -or
            (Test-ProtectedOverlayConfigPath -RelativePath $relativePath)) {
            throw "Overlay ownership manifest '$ManifestPath' contains an invalid owned path."
        }
        [void](Get-ContainedPath -Root $GithubDir -Child $relativePath -Description 'Overlay ownership manifest path')
        $pathKey = $relativePath.Replace('\', '/').ToLowerInvariant()
        if ($seenPaths.ContainsKey($pathKey)) {
            throw "Overlay ownership manifest '$ManifestPath' contains a duplicate owned path."
        }
        $seenPaths[$pathKey] = $true
        if ([string]$entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw "Overlay ownership manifest '$ManifestPath' contains an invalid file hash."
        }
        if ($entry.prior_present -isnot [bool]) {
            throw "Overlay ownership manifest '$ManifestPath' contains an invalid prior_present value."
        }
        $priorContent = [string]$entry.prior_content_base64
        if ([bool]$entry.prior_present -and [string]::IsNullOrEmpty($priorContent)) {
            throw "Overlay ownership manifest '$ManifestPath' omits required prior content."
        }
        if (-not [string]::IsNullOrEmpty($priorContent)) {
            try { [void][Convert]::FromBase64String($priorContent) }
            catch { throw "Overlay ownership manifest '$ManifestPath' contains invalid prior content." }
        }
    }
    return $manifest
}

function Test-OverlayManifestExists {
    param(
        [string]$OverlayPath,
        [string]$OverlaySubtree,
        [string]$GithubDir
    )

    $identityHash = Get-OverlayIdentityHash -OverlayPath $OverlayPath -OverlaySubtree $OverlaySubtree
    $manifestPath = Join-Path -Path $GithubDir -ChildPath ".overlay-manifests/$identityHash.json"
    return Test-Path -LiteralPath $manifestPath -PathType Leaf
}

function Test-HigherTierOwnsTarget {
    param(
        [string]$ManifestDir,
        [string[]]$HigherOwnerIds,
        [string]$RelativePath,
        [string]$TargetHash
    )

    foreach ($ownerId in @($HigherOwnerIds)) {
        if ([string]::IsNullOrWhiteSpace($ownerId)) { continue }
        $ownerManifestPath = Join-Path -Path $ManifestDir -ChildPath ($ownerId + '.json')
        if (-not (Test-Path -LiteralPath $ownerManifestPath -PathType Leaf)) { continue }
        $githubRoot = Split-Path -Path $ManifestDir -Parent
        $ownerManifest = Read-ValidatedOverlayManifest -ManifestPath $ownerManifestPath -ExpectedSourceId $ownerId -GithubDir $githubRoot
        foreach ($ownerEntry in @($ownerManifest.files)) {
            if ([string]$ownerEntry.path -ieq $RelativePath -and
                [string]$ownerEntry.sha256 -eq $TargetHash) {
                return $true
            }
        }
    }
    return $false
}

# Copy one overlay subtree (e.g. "overlays/workspace" or "overlays/repo/<RepoName>")
# into a workspace/repo .github directory: every file and sub-directory is copied
# recursively, exactly like the base tier. Files at the subtree root flatten to
# .github/; sub-directories (agents, prompts, skills, docs, ...) copy as-is.
# Returns the number of files copied. A missing/empty subtree is a no-op.
function Copy-OverlayGithubTree {
    param(
        [string]$OverlayPath,
        [string]$OverlaySubtree,
        [string]$GithubDir,
        [string[]]$HigherOwnerIds = @(),
        [switch]$CleanupOnly
    )

    if (-not (Test-Path -Path $GithubDir)) {
        New-Item -ItemType Directory -Path $GithubDir -Force | Out-Null
    }

    try {
        $srcRoot = Join-Path -Path $OverlayPath -ChildPath $OverlaySubtree
        $identityHash = Get-OverlayIdentityHash -OverlayPath $OverlayPath -OverlaySubtree $OverlaySubtree

        $manifestDir = Join-Path -Path $GithubDir -ChildPath '.overlay-manifests'
        $manifestPath = Join-Path -Path $manifestDir -ChildPath ($identityHash + '.json')
        $sourceExists = Test-Path -LiteralPath $srcRoot -PathType Container
        if (-not $sourceExists -and -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Log-Message "Skipping $OverlaySubtree - source path and ownership manifest not found: $srcRoot" "WARN"
            return 0
        }
        $sourceFiles = if ($sourceExists) {
            @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction Stop |
                Where-Object { $_.Name -ne '.gitkeep' })
        } else { @() }
        # Company-wide protected config is base-authoritative: never track an
        # overlay tier's copy of default-config.yaml or guardrails.yaml in the
        # manifest. The base copy is restored after the physical copy below.
        $sourceFiles = @($sourceFiles | Where-Object {
            $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\', '/').Replace('\', '/')
            -not (Test-ProtectedOverlayConfigPath -RelativePath $rel) -and
            -not (Test-ReservedOverlayPath -RelativePath $rel)
        })
        $priorEntries = @{}
        $priorManifest = $null
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $priorManifest = Read-ValidatedOverlayManifest -ManifestPath $manifestPath -ExpectedSourceId $identityHash -GithubDir $GithubDir
            foreach ($entry in @($priorManifest.files)) {
                $priorEntries[([string]$entry.path).ToLowerInvariant()] = $entry
            }
        }

        $currentEntries = @($sourceFiles | ForEach-Object {
            $relativePath = $_.FullName.Substring($srcRoot.Length).TrimStart('\', '/').Replace('\', '/')
            $targetPath = Get-ContainedPath -Root $GithubDir -Child $relativePath -Description 'Overlay target file'
            $priorEntry = $priorEntries[$relativePath.ToLowerInvariant()]
            $retainPrior = $false
            if ($null -ne $priorEntry -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                $targetHash = Get-FileSha256 -LiteralPath $targetPath
                $retainPrior = $targetHash -eq [string]$priorEntry.sha256 -or
                    (Test-HigherTierOwnsTarget -ManifestDir $manifestDir -HigherOwnerIds $HigherOwnerIds -RelativePath $relativePath -TargetHash $targetHash)
            }

            if ($retainPrior) {
                $priorPresent = [bool]$priorEntry.prior_present
                $priorContent = [string]$priorEntry.prior_content_base64
            } else {
                $priorPresent = Test-Path -LiteralPath $targetPath -PathType Leaf
                $priorContent = if ($priorPresent) {
                    [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($targetPath))
                } else { '' }
            }

            [pscustomobject]@{
                path = $relativePath
                sha256 = Get-FileSha256 -LiteralPath $_.FullName
                prior_present = $priorPresent
                prior_content_base64 = $priorContent
            }
        })
        $currentPaths = @{}
        foreach ($entry in $currentEntries) { $currentPaths[$entry.path.ToLowerInvariant()] = $true }

        if ($null -ne $priorManifest) {
            foreach ($entry in @($priorManifest.files)) {
                $relativePath = [string]$entry.path
                if ([string]::IsNullOrWhiteSpace($relativePath) -or $currentPaths.ContainsKey($relativePath.ToLowerInvariant())) { continue }
                $targetPath = Get-ContainedPath -Root $GithubDir -Child $relativePath -Description 'Stale overlay file'
                if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and
                    (Get-FileSha256 -LiteralPath $targetPath) -eq [string]$entry.sha256) {
                    if ([bool]$entry.prior_present -and -not [string]::IsNullOrEmpty([string]$entry.prior_content_base64)) {
                        [System.IO.File]::WriteAllBytes(
                            $targetPath,
                            [Convert]::FromBase64String([string]$entry.prior_content_base64)
                        )
                        Log-Message "Restored lower-tier file after overlay removal: $targetPath"
                    } else {
                        Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                        Log-Message "Removed stale overlay-owned file: $targetPath"
                    }
                } elseif (Test-Path -LiteralPath $targetPath -PathType Leaf) {
                    $targetHash = Get-FileSha256 -LiteralPath $targetPath
                    if (Test-HigherTierOwnsTarget -ManifestDir $manifestDir -HigherOwnerIds $HigherOwnerIds -RelativePath $relativePath -TargetHash $targetHash) {
                        $currentEntries += $entry
                        Log-Message "Deferred lower-tier cleanup while a higher overlay owns: $targetPath"
                    } else {
                        Log-Message "Preserved changed stale overlay path: $targetPath" "WARN"
                    }
                } else {
                    Log-Message "Preserved changed stale overlay path: $targetPath" "WARN"
                }
            }
        }

        if ($sourceExists -and -not $CleanupOnly) {
            [void](Copy-OverlayTierToGithub -SourceRoot $srcRoot -GithubDir $GithubDir -TierLabel $OverlaySubtree)
        }
        $copied = if ($CleanupOnly) { 0 } else { $sourceFiles.Count }

        if (-not (Test-Path -LiteralPath $manifestDir -PathType Container)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }
        $manifest = [ordered]@{
            schema = 2
            source_id = $identityHash
            files = $currentEntries
        } | ConvertTo-Json -Depth 5
        $manifestTemp = $manifestPath + '.tmp'
        [System.IO.File]::WriteAllText($manifestTemp, $manifest, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force
        Log-Message "Copied $copied files from $OverlaySubtree to $GithubDir"
        return $copied
    } catch {
        Log-Message "Error copying $OverlaySubtree from $srcRoot to $GithubDir : $_" "ERROR"
        throw
    }
}

#==============================================================================
# Main execution
#==============================================================================

Log-Message "=== Overlay Setup ==="
Log-Message "Overlay path: $OverlayPath"
Log-Message "Workspace base: $BasePath"
if ($WorkspaceName) {
    $WorkspaceName = $WorkspaceName.Trim().Trim('"').Trim("'")
    Assert-SafePathSegment -Value $WorkspaceName -ParameterName "-WorkspaceName"
    Log-Message "Workspace filter: $WorkspaceName"
    if ($RepoName) {
        $RepoName = $RepoName.Trim().Trim('"').Trim("'")
        Assert-SafePathSegment -Value $RepoName -ParameterName "-RepoName"
        Log-Message "Repo filter: $RepoName"
    }
} elseif ($RepoName) {
    Log-Message "-RepoName can only be used with -WorkspaceName" "ERROR"
    exit 1
}

$workspaceOverlay = Join-Path -Path $OverlayPath -ChildPath "overlays/workspace"
$workspaceOverlayHasContent = Test-TierHasContent -Root $workspaceOverlay
$repoOverlayHasContent = $false
if ($RepoName) {
    $repoOverlayBase = Get-ContainedPath -Root $OverlayPath -Child "overlays/repo" -Description "Repository overlay root"
    $repoOverlayRoot = Get-ContainedPath -Root $repoOverlayBase -Child $RepoName -Description "Repository overlay path"
    $repoOverlayHasContent = Test-TierHasContent -Root $repoOverlayRoot
}

# Discover all workspaces (exclude dot-directories like .backup/.claude/.idea)
$workspaces = @()
if (Test-Path -Path $BasePath) {
    if ($WorkspaceName) {
        $targetWorkspacePath = Get-ContainedPath -Root $BasePath -Child $WorkspaceName -Description "Workspace path"

        $targetPath = $targetWorkspacePath
        if ($RepoName) {
            $targetPath = Get-ContainedPath -Root $targetWorkspacePath -Child $RepoName -Description "Repository path"
        }

        if (-not (Test-Path -Path $targetPath -PathType Container)) {
            if ($RepoName) {
                Log-Message "Repository path '$WorkspaceName/$RepoName' not found at $BasePath" "ERROR"
            } else {
                Log-Message "Workspace '$WorkspaceName' not found at $BasePath" "ERROR"
            }
            exit 1
        }
        $workspaces = @(Get-Item -Path $targetPath)
    } else {
        $workspaces = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^\.' }
    }
}

if ($workspaces.Count -eq 0) {
    Log-Message "No workspaces found at $BasePath" "WARN"
    exit 0
}

$hasCleanupManifest = $false
if (-not $workspaceOverlayHasContent -and -not $repoOverlayHasContent) {
    foreach ($workspace in $workspaces) {
        $githubDir = Join-Path -Path $workspace.FullName -ChildPath '.github'
        if (Test-OverlayManifestExists -OverlayPath $OverlayPath -OverlaySubtree 'overlays/workspace' -GithubDir $githubDir) {
            $hasCleanupManifest = $true
            break
        }
        if ($RepoName -and (Test-OverlayManifestExists -OverlayPath $OverlayPath -OverlaySubtree "overlays/repo/$RepoName" -GithubDir $githubDir)) {
            $hasCleanupManifest = $true
            break
        }
    }
    if (-not $hasCleanupManifest) {
        if ($RepoName) {
            Log-Message "No applicable overlay payload found. Expected content in overlays/workspace or overlays/repo/$RepoName for the targeted repository." "ERROR"
        } else {
            Log-Message "No applicable overlay payload found. Expected content in overlays/workspace." "ERROR"
        }
        exit 1
    }
    Log-Message 'Overlay payload is empty; reconciling previously installed overlay-owned files.'
}

Log-Message "Found $($workspaces.Count) workspace(s)"

# Local overlay tier: resolve the source once. -LocalPath wins; otherwise fall
# back to the AI_LOCAL_TIER environment variable set by install.bat. When set and
# non-empty it is applied LAST for each workspace (after the overlay tiers) so
# local files win over the overlay.
if ([string]::IsNullOrWhiteSpace($LocalPath) -and -not [string]::IsNullOrWhiteSpace($env:AI_LOCAL_TIER)) {
    $LocalPath = $env:AI_LOCAL_TIER
}
$resolvedLocal = Resolve-LocalTierSource -LocalPath $LocalPath
if ($resolvedLocal) {
    if (Test-TierHasContent -Root $resolvedLocal) {
        Log-Message "Local overlay tier source: $resolvedLocal"
    } else {
        Log-Message "Local overlay tier source has no content (skipped): $resolvedLocal" "WARN"
    }
}

$totalCopied = 0

foreach ($workspace in $workspaces) {
    $githubDir = Join-Path -Path $workspace.FullName -ChildPath ".github"
    $repoSubtree = if ($RepoName) { "overlays/repo/$RepoName" } else { '' }
    $workspaceHigherOwnerIds = if ($RepoName) {
        @(Get-OverlayIdentityHash -OverlayPath $OverlayPath -OverlaySubtree $repoSubtree)
    } else { @() }

    # Ensure .github exists
    if (-not (Test-Path -Path $githubDir)) {
        New-Item -ItemType Directory -Path $githubDir -Force | Out-Null
    }

    Log-Message "Processing workspace: $($workspace.Name)"

    # Workspace overlay is optional for a repository target with a non-empty repo tier.
    if ($workspaceOverlayHasContent -or (Test-OverlayManifestExists -OverlayPath $OverlayPath -OverlaySubtree 'overlays/workspace' -GithubDir $githubDir)) {
        $copiedCount = Copy-OverlayGithubTree -OverlayPath $OverlayPath -OverlaySubtree "overlays/workspace" -GithubDir $githubDir -HigherOwnerIds $workspaceHigherOwnerIds
        $totalCopied += $copiedCount
    } elseif ($Verbose) {
        Log-Message "No content in overlays/workspace - skipping workspace-level overlay"
    }

    # Repo overlay: when a specific repository is targeted (--repo), layer
    # overlays/repo/<RepoName> on top of the workspace overlay. Reads ONLY the
    # per-repo subdirectory (no flat overlays/repo fallback); silently skips when
    # that subdirectory is missing or has no content beyond .gitkeep.
    if ($RepoName) {
        if ($repoOverlayHasContent -or (Test-OverlayManifestExists -OverlayPath $OverlayPath -OverlaySubtree $repoSubtree -GithubDir $githubDir)) {
            Log-Message "Applying repo overlay ($repoSubtree) for $($workspace.Name)"
            $copiedCount = Copy-OverlayGithubTree -OverlayPath $OverlayPath -OverlaySubtree $repoSubtree -GithubDir $githubDir
            $totalCopied += $copiedCount
        } elseif ($Verbose) {
            Log-Message "No content in $repoSubtree - skipping repo-level overlay"
        }

        # A stale workspace-owned path may have been hidden by the repo tier on
        # the first pass. Reconcile workspace cleanup again after the higher
        # tier has restored or relinquished that path, without recopying active
        # workspace files over the repo tier.
        if (Test-OverlayManifestExists -OverlayPath $OverlayPath -OverlaySubtree 'overlays/workspace' -GithubDir $githubDir) {
            [void](Copy-OverlayGithubTree -OverlayPath $OverlayPath -OverlaySubtree "overlays/workspace" -GithubDir $githubDir -HigherOwnerIds $workspaceHigherOwnerIds -CleanupOnly)
        }
    }

    # Local overlay tier: final overwrite so local files win over the overlay.
    if (Test-TierHasContent -Root $resolvedLocal) {
        $localCopied = Apply-LocalOverlayTier -SourceRoot $resolvedLocal -GithubDir $githubDir -WorkspaceRoot $workspace.FullName -SkipClaude:$SkipClaude
        $totalCopied += $localCopied
        Log-Message "Applied local overlay tier ($localCopied files) from $resolvedLocal for $($workspace.Name)"
    }

    if (-not $SkipClaude) {
        Rebuild-ClaudeEffectiveMirror -GithubDir $githubDir -WorkspaceRoot $workspace.FullName
    }

    # Strip Git placeholder files from the rendered targets so tooling
    # (e.g. Deva session resume) is not confused by shipped .gitignore/.gitkeep.
    $placeholderRoots = @($githubDir)
    if (-not $SkipClaude) { $placeholderRoots += (Join-Path -Path $workspace.FullName -ChildPath ".claude") }
    Remove-VcsPlaceholderFiles -Roots $placeholderRoots
}

Log-Message "=== Overlay Setup Complete ==="
Log-Message "Total files copied: $totalCopied"
exit 0
