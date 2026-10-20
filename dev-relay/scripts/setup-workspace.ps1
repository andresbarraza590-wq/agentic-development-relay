#==============================================================================
# setup-workspace.ps1 — Workspace directory structure setup
#==============================================================================
# Creates the required directory structure under <WORKSPACE_PROJECTS_ROOT>
# and lists all available workspaces. Also copies framework files to
# each workspace's .github directory.
#
# Usage:
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File setup-workspace.ps1
#   [-BasePath "path/to/projects"] [-RepoRoot "path/to/framework"]
#   [-WorkspaceName "workspace_name" [-RepoName "repo_name"]] [-LocalPath "path/to/local"]
#   [-BackupWorkspace | -PurgeWorkspace | -PurgeAllBackups | -KeepArchitecture] [-SkipClaude]
#==============================================================================

param(
    [string]$BasePath = "<WORKSPACE_PROJECTS_ROOT>",
    [string]$RepoRoot = "",
    [string]$WorkspaceName = "",
    [string]$RepoName = "",
    [string]$LocalPath = "",
    [switch]$BackupWorkspace,
    [switch]$PurgeWorkspace,
    [switch]$PurgeAllBackups,
    [switch]$KeepArchitecture,
    [switch]$SkipClaude
)

$ErrorActionPreference = "Stop"

# -SkipClaude (or AI_SKIP_CLAUDE=1 from install.bat) suppresses the .claude/CLAUDE.md
# dual-platform mirror so only the Copilot (.github) layout is written. --backup,
# --purge, and --purge-all are still honored: Prepare-WorkspaceConfigDirectories runs
# regardless and acts on any existing .claude/CLAUDE.md and their .bak* generations.
if (-not $SkipClaude -and $env:AI_SKIP_CLAUDE -eq '1') { $SkipClaude = $true }

# Function to create directory if it doesn't exist
function Ensure-Directory {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Host "Creating $Path ..."
        try {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
            Write-Host "$Path created successfully."
        } catch {
            throw "Could not create ${Path}: $($_.Exception.Message)"
        }
    }
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

# Rotate an existing backup chain so a fresh backup can take the base `.bak`
# name without overwriting older generations: .bak -> .bak.1 -> .bak.2 ...
# After this runs the base `.bak` path is free; the caller moves the current
# config into it, leaving .bak as newest and .bak.<n> as progressively older.
function Move-BackupAside {
    param([string]$BackupPath)

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        return
    }

    # Highest existing numbered generation (.bak.<n>).
    $highest = 0
    while (Test-Path -LiteralPath ("{0}.{1}" -f $BackupPath, ($highest + 1))) {
        $highest++
    }

    # Shift numbered generations down, oldest first, to avoid collisions.
    for ($i = $highest; $i -ge 1; $i--) {
        Move-Item -LiteralPath ("{0}.{1}" -f $BackupPath, $i) `
            -Destination ("{0}.{1}" -f $BackupPath, ($i + 1)) -Force -ErrorAction Stop
    }

    # Base .bak becomes .bak.1.
    Move-Item -LiteralPath $BackupPath -Destination ("{0}.1" -f $BackupPath) -Force -ErrorAction Stop
}

# Remove every backup generation for a config target: the base <name>.bak plus all
# rotated <name>.bak.<n> copies. Used by --purge-all to clear accumulated backups.
function Remove-AllBackups {
    param(
        [string]$WorkspacePath,
        [string]$Name
    )

    Get-ChildItem -LiteralPath $WorkspacePath -Force -Filter ("{0}.bak*" -f $Name) -ErrorAction Stop |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                Write-Host "Removed backup $($_.FullName)"
            } catch {
                throw "Could not remove backup $($_.FullName): $($_.Exception.Message)"
            }
        }
}

# Prepare .github and .claude right before re-creating them.
function Prepare-WorkspaceConfigDirectories {
    param(
        [string]$WorkspacePath,
        [switch]$BackupWorkspace,
        [switch]$PurgeWorkspace,
        [switch]$PurgeAllBackups
    )

    $targetDirs = @(".github", ".claude")

    if ($BackupWorkspace) {
        foreach ($dirName in $targetDirs) {
            $sourcePath = Join-Path -Path $WorkspacePath -ChildPath $dirName
            $backupPath = Join-Path -Path $WorkspacePath -ChildPath ("{0}.bak" -f $dirName)

            if (Test-Path -Path $sourcePath) {
                try {
                    Move-BackupAside -BackupPath $backupPath

                    Move-Item -Path $sourcePath -Destination $backupPath -Force -ErrorAction Stop
                    Write-Host "Backed up $sourcePath to $backupPath"
                } catch {
                    throw "Could not back up $sourcePath to ${backupPath}: $($_.Exception.Message)"
                }
            }
        }

        # Root CLAUDE.md is part of the Claude mirror; back it up too so --backup
        # is respected even when the mirror is skipped (-SkipClaude).
        $claudeMdSource = Join-Path -Path $WorkspacePath -ChildPath "CLAUDE.md"
        $claudeMdBackup = Join-Path -Path $WorkspacePath -ChildPath "CLAUDE.md.bak"
        if (Test-Path -Path $claudeMdSource) {
            try {
                Move-BackupAside -BackupPath $claudeMdBackup
                Move-Item -Path $claudeMdSource -Destination $claudeMdBackup -Force -ErrorAction Stop
                Write-Host "Backed up $claudeMdSource to $claudeMdBackup"
            } catch {
                throw "Could not back up $claudeMdSource to ${claudeMdBackup}: $($_.Exception.Message)"
            }
        }
    }

    if ($PurgeWorkspace) {
        foreach ($dirName in $targetDirs) {
            $targetPath = Join-Path -Path $WorkspacePath -ChildPath $dirName

            if (Test-Path -Path $targetPath) {
                try {
                    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
                    Write-Host "Removed $targetPath"
                } catch {
                    throw "Could not remove ${targetPath}: $($_.Exception.Message)"
                }
            }
        }

        # Root CLAUDE.md is part of the Claude mirror; remove it too so --purge is
        # respected even when the mirror is skipped (-SkipClaude).
        $claudeMdTarget = Join-Path -Path $WorkspacePath -ChildPath "CLAUDE.md"
        if (Test-Path -Path $claudeMdTarget) {
            try {
                Remove-Item -Path $claudeMdTarget -Force -ErrorAction Stop
                Write-Host "Removed $claudeMdTarget"
            } catch {
                throw "Could not remove ${claudeMdTarget}: $($_.Exception.Message)"
            }
        }
    }

    if ($PurgeAllBackups) {
        # Deepest clean: remove the live config (like --purge) and every backup generation.
        foreach ($dirName in $targetDirs) {
            $targetPath = Join-Path -Path $WorkspacePath -ChildPath $dirName
            if (Test-Path -Path $targetPath) {
                try {
                    Remove-Item -Path $targetPath -Recurse -Force -ErrorAction Stop
                    Write-Host "Removed $targetPath"
                } catch {
                    throw "Could not remove ${targetPath}: $($_.Exception.Message)"
                }
            }
            Remove-AllBackups -WorkspacePath $WorkspacePath -Name $dirName
        }

        # Root CLAUDE.md and its backups are removed too, even with -SkipClaude.
        $claudeMdTarget = Join-Path -Path $WorkspacePath -ChildPath "CLAUDE.md"
        if (Test-Path -Path $claudeMdTarget) {
            try {
                Remove-Item -Path $claudeMdTarget -Force -ErrorAction Stop
                Write-Host "Removed $claudeMdTarget"
            } catch {
                throw "Could not remove ${claudeMdTarget}: $($_.Exception.Message)"
            }
        }
        Remove-AllBackups -WorkspacePath $WorkspacePath -Name "CLAUDE.md"
    }
}

# Function to copy framework directories to workspace .github directory
function Copy-FrameworkDirectory {
    param(
        [string]$SourcePath,
        [string]$DestinationRoot
    )

    if (-not (Test-Path -Path $SourcePath)) {
        Write-Host "WARNING: Source directory does not exist: $SourcePath"
        return
    }

    try {
        $sourceDirName = Split-Path -Path $SourcePath -Leaf
        $destinationPath = Join-Path -Path $DestinationRoot -ChildPath $sourceDirName

        if (-not (Test-Path -Path $destinationPath)) {
            New-Item -ItemType Directory -Path $destinationPath -Force -ErrorAction Stop | Out-Null
        }
        Get-ChildItem -Path $SourcePath -Force -ErrorAction Stop | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse -Force -ErrorAction Stop
        }
        Write-Host "Merged $sourceDirName into $destinationPath"
    } catch {
        throw "Could not copy directory to ${DestinationRoot}: $($_.Exception.Message)"
    }
}

# Function to copy all contents of a source directory into a destination directory
function Copy-DirectoryContents {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string[]]$KeepExistingFiles = @()
    )

    if (-not (Test-Path -Path $SourcePath)) {
        Write-Host "WARNING: Source directory does not exist: $SourcePath"
        return
    }

    try {
        Get-ChildItem -Path $SourcePath -Force -ErrorAction Stop | ForEach-Object {
            $destinationItem = Join-Path -Path $DestinationPath -ChildPath $_.Name
            if ($_.Name -in $KeepExistingFiles -and (Test-Path -LiteralPath $destinationItem -PathType Leaf)) {
                Write-Host "Kept existing $destinationItem"
            } else {
                Copy-Item -Path $_.FullName -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
            }
        }
        Write-Host "Copied contents of $(Split-Path -Path $SourcePath -Leaf) to $DestinationPath"
    } catch {
        throw "Could not copy contents from $SourcePath to ${DestinationPath}: $($_.Exception.Message)"
    }
}

#==============================================================================
# Dual-platform mirror: generate the Claude Code (.claude) layout from
# the same .github source assets at install time. Single source of truth —
# do not hand-edit .claude/; edit the base .github assets and re-run install.
# The Copilot -> Claude transform functions are shared with setup-overlay.ps1
# via claude-mirror-lib.ps1 so base and overlay produce identical frontmatter.
#==============================================================================

. (Join-Path -Path $PSScriptRoot -ChildPath "claude-mirror-lib.ps1")

# Orchestrate the full .claude mirror for one workspace/repo root.
function Copy-ClaudeMirror {
    param(
        [string]$BaseDir,
        [string]$ClaudeDir,
        [string]$WorkspaceRoot
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    # 1. Instructions: base/copilot-instructions.md -> <root>/CLAUDE.md
    $instr = Join-Path -Path $BaseDir -ChildPath "copilot-instructions.md"
    if (Test-Path -LiteralPath $instr) {
        $banner = "<!-- Generated from .github/copilot-instructions.md by install.bat (dual-platform mirror). Do not edit directly. -->"
        $content = Get-Content -LiteralPath $instr -Raw -Encoding UTF8
        $content = Convert-ClaudeInstructionLinks -Content $content
        $claudeMd = Join-Path -Path $WorkspaceRoot -ChildPath "CLAUDE.md"
        [System.IO.File]::WriteAllText($claudeMd, ($banner + "`r`n`r`n" + $content), $utf8NoBom)
        Write-Host "Generated CLAUDE.md from copilot-instructions.md"
    }

    # 2. Agents: base/agents/*.agent.md -> .claude/agents/*.md (frontmatter transformed)
    $agentsSrc = Join-Path -Path $BaseDir -ChildPath "agents"
    if (Test-Path -LiteralPath $agentsSrc) {
        $claudeAgents = Join-Path -Path $ClaudeDir -ChildPath "agents"
        Ensure-Directory -Path $claudeAgents
        Get-ChildItem -Path $agentsSrc -Filter "*.agent.md" -ErrorAction SilentlyContinue | ForEach-Object {
            Convert-ToClaudeAgent -SourceFile $_.FullName -DestDir $claudeAgents -Encoder $utf8NoBom
        }
        Write-Host "Mirrored agents to $claudeAgents"
    }

    # 3a. Skills: base/skills/ -> .claude/skills/ (verbatim; SKILL.md is cross-compatible)
    $skillsSrc = Join-Path -Path $BaseDir -ChildPath "skills"
    if (Test-Path -LiteralPath $skillsSrc) {
        Copy-FrameworkDirectory -SourcePath $skillsSrc -DestinationRoot $ClaudeDir
    }

    # 3b. Images: base/images/ -> .claude/images/ (verbatim; PNG assets referenced by docs)
    $imagesSrc = Join-Path -Path $BaseDir -ChildPath "images"
    if (Test-Path -LiteralPath $imagesSrc) {
        Copy-FrameworkDirectory -SourcePath $imagesSrc -DestinationRoot $ClaudeDir
    }

    # 3c. Scripts: base/scripts/ -> .claude/scripts/ (verbatim; includes logs/ tracer and
    #      githooks/ deterministic hooks, which are activated per-repo)
    $scriptsSrc = Join-Path -Path $BaseDir -ChildPath "scripts"
    if (Test-Path -LiteralPath $scriptsSrc) {
        Copy-FrameworkDirectory -SourcePath $scriptsSrc -DestinationRoot $ClaudeDir
    }

    # 4. Prompts: prompts/*.prompt.md -> .claude/commands/*.md (Claude slash commands;
    #      frontmatter transformed). Mirrors shipped base prompts; overlay prompts are
    #      mirrored by the overlay installation path.
    $promptsSrc = Join-Path -Path $BaseDir -ChildPath "prompts"
    if (Test-Path -LiteralPath $promptsSrc) {
        $promptFiles = @(Get-ChildItem -Path $promptsSrc -Filter "*.prompt.md" -ErrorAction SilentlyContinue)
        if ($promptFiles.Count -gt 0) {
            $claudeCommands = Join-Path -Path $ClaudeDir -ChildPath "commands"
            Ensure-Directory -Path $claudeCommands
            $promptFiles | ForEach-Object {
                Convert-ToClaudeCommand -SourceFile $_.FullName -DestDir $claudeCommands -Encoder $utf8NoBom
            }
            Write-Host "Mirrored prompts to $claudeCommands"
        }
    }

    # 5. Governance/config YAML -> .claude/ (self-contained; referenced by CLAUDE.md)
    foreach ($yaml in @("guardrails.yaml", "default-config.yaml", "agent-commands.yaml")) {
        $src = Join-Path -Path $BaseDir -ChildPath ("config/$yaml")
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $ClaudeDir -Force -ErrorAction Stop
        }
    }
    Write-Host "Copied governance YAML to $ClaudeDir"

    # 6. Architecture docs use Claude-native names and rewritten cross-links.
    Copy-ClaudeArchitectureDocuments -SourceRoot $BaseDir -ClaudeDir $ClaudeDir -Encoder $utf8NoBom

    # 7. Framework docs -> .claude/docs/ so links in the mirrored README resolve.
    $docsSrc = Join-Path -Path $BaseDir -ChildPath "docs"
    if (Test-Path -LiteralPath $docsSrc) {
        $claudeDocs = Join-Path -Path $ClaudeDir -ChildPath "docs"
        Ensure-Directory -Path $claudeDocs
        Get-ChildItem -Path $docsSrc -Filter "*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
            $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
            $content = Convert-ClaudeFrameworkDocumentLinks -Content $content -Location docs
            $destination = Join-Path -Path $claudeDocs -ChildPath $_.Name
            [System.IO.File]::WriteAllText($destination, $content, $utf8NoBom)
        }
    }
    $readmeSrc = Join-Path -Path $BaseDir -ChildPath "README.md"
    if (Test-Path -LiteralPath $readmeSrc) {
        $content = Get-Content -LiteralPath $readmeSrc -Raw -Encoding UTF8
        $content = Convert-ClaudeFrameworkDocumentLinks -Content $content -Location root
        [System.IO.File]::WriteAllText((Join-Path -Path $ClaudeDir -ChildPath "README.md"), $content, $utf8NoBom)
    }
    Write-Host "Copied framework docs to $ClaudeDir"
}

# Define paths
$dsRoot = "<WORKSPACE_ROOT>"
$projectsRoot = $BasePath

# Normalize RepoRoot once so path checks do not fail on stray quotes/whitespace
$resolvedRepoRoot = ""
if ($RepoRoot) {
    $sanitizedRepoRoot = $RepoRoot.Trim().Trim('"').Trim("'")

    if ($sanitizedRepoRoot) {
        try {
            $resolvedRepoRoot = (Resolve-Path -LiteralPath $sanitizedRepoRoot -ErrorAction Stop).Path
        } catch {
            Write-Host "ERROR: RepoRoot path is invalid or inaccessible: $RepoRoot"
            exit 1
        }
    }
}

if ($resolvedRepoRoot) {
    $basePayload = Join-Path -Path $resolvedRepoRoot -ChildPath "base"
    $baseReadme = Join-Path -Path $basePayload -ChildPath "README.md"
    $baseInstructions = Join-Path -Path $basePayload -ChildPath "copilot-instructions.md"
    $baseDefaultConfig = Join-Path -Path $basePayload -ChildPath "config/default-config.yaml"
    $baseGuardrails = Join-Path -Path $basePayload -ChildPath "config/guardrails.yaml"
    if (-not (Test-Path -LiteralPath $basePayload -PathType Container) -or
        -not (Test-Path -LiteralPath $baseReadme -PathType Leaf) -or
        -not (Test-Path -LiteralPath $baseInstructions -PathType Leaf) -or
        -not (Test-Path -LiteralPath $baseDefaultConfig -PathType Leaf) -or
        -not (Test-Path -LiteralPath $baseGuardrails -PathType Leaf)) {
        Write-Host "ERROR: Framework base payload is missing or incomplete: $basePayload"
        exit 1
    }
}

# Resolve the optional local overlay tier source. -LocalPath wins; otherwise fall
# back to the AI_LOCAL_TIER environment variable set by install.bat. When set and
# non-empty it is applied LAST for each workspace (after base assets) so local
# files win - the final overwrite step when the overlay step is skipped.
if ([string]::IsNullOrWhiteSpace($LocalPath) -and -not [string]::IsNullOrWhiteSpace($env:AI_LOCAL_TIER)) {
    $LocalPath = $env:AI_LOCAL_TIER
}
$resolvedLocal = Resolve-LocalTierSource -LocalPath $LocalPath
if ($resolvedLocal) {
    if (Test-TierHasContent -Root $resolvedLocal) {
        Write-Host "Local overlay tier source: $resolvedLocal"
    } else {
        Write-Host "Local overlay tier source has no content (skipped): $resolvedLocal"
    }
}

Write-Host ""
Write-Host "Checking workspace directory structure ..."
Write-Host ""

# Create required directories
Ensure-Directory -Path $dsRoot
Ensure-Directory -Path $projectsRoot

Write-Host ""

if ((@($BackupWorkspace, $PurgeWorkspace, $PurgeAllBackups) | Where-Object { $_ }).Count -gt 1) {
    Write-Host "ERROR: -BackupWorkspace, -PurgeWorkspace and -PurgeAllBackups are mutually exclusive (use at most one)"
    exit 1
}

if ($KeepArchitecture -and ($BackupWorkspace -or $PurgeWorkspace -or $PurgeAllBackups)) {
    Write-Host "ERROR: -KeepArchitecture cannot be used with backup or purge operations."
    exit 1
}

if (($BackupWorkspace -or $PurgeWorkspace -or $PurgeAllBackups) -and -not $resolvedRepoRoot) {
    Write-Host "ERROR: -RepoRoot with a complete framework base payload is required for backup or purge operations."
    exit 1
}

# Determine which workspaces to process
if ($WorkspaceName) {
    $WorkspaceName = $WorkspaceName.Trim().Trim('"').Trim("'")
    Assert-SafePathSegment -Value $WorkspaceName -ParameterName "-WorkspaceName"
    Write-Host "Setting up workspace: $WorkspaceName"
    Write-Host "WorkspaceName parameter: '$WorkspaceName'"
    if ($RepoName) {
        $RepoName = $RepoName.Trim().Trim('"').Trim("'")
        Assert-SafePathSegment -Value $RepoName -ParameterName "-RepoName"
        Write-Host "RepoName parameter: '$RepoName'"
    }
    Write-Host ""
} else {
    if ($RepoName) {
        Write-Host "ERROR: -RepoName can only be used with -WorkspaceName"
        exit 1
    }
    Write-Host "Available workspaces under $projectsRoot :"
    Write-Host ""
}

# List all directories under <WORKSPACE_PROJECTS_ROOT> and ensure .claude and .github directories
if (Test-Path -Path $projectsRoot) {
    if ($WorkspaceName) {
        $targetWorkspacePath = Get-ContainedPath -Root $projectsRoot -Child $WorkspaceName -Description "Workspace path"

        $targetPath = $targetWorkspacePath
        if ($RepoName) {
            $targetPath = Get-ContainedPath -Root $targetWorkspacePath -Child $RepoName -Description "Repository path"
        }

        if (-not (Test-Path -Path $targetPath -PathType Container)) {
            Write-Host ""
            if ($RepoName) {
                Write-Host "ERROR: Repository path '$WorkspaceName\$RepoName' not found at $projectsRoot"
            } else {
                Write-Host "ERROR: Workspace '$WorkspaceName' not found at $projectsRoot"
            }
            Write-Host ""
            exit 1
        }

        $workspaces = @(Get-Item -Path $targetPath -ErrorAction SilentlyContinue)
    } else {
        $workspaces = Get-ChildItem -Path $projectsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('.') }
    }

    if ($workspaces.Count -gt 0) {
        $workspaceFound = $false

        foreach ($workspace in $workspaces) {
            $workspaceFound = $true
            Write-Host "  - $($workspace.Name)"

            # Ensure .claude and .github directories exist in each workspace
            $claudeDir = Join-Path -Path $workspace.FullName -ChildPath ".claude"
            $githubDir = Join-Path -Path $workspace.FullName -ChildPath ".github"

            Prepare-WorkspaceConfigDirectories -WorkspacePath $workspace.FullName -BackupWorkspace:$BackupWorkspace -PurgeWorkspace:$PurgeWorkspace -PurgeAllBackups:$PurgeAllBackups

            if (-not $SkipClaude) {
                Ensure-Directory -Path $claudeDir
            }
            Ensure-Directory -Path $githubDir

            # Copy everything under base/ into .github if RepoRoot is valid.
            # Files in base/ flatten to the .github root; sub-directories
            # (agents, cache, docs, images, prompts, scripts, skills) copy as-is.
            if ($resolvedRepoRoot) {
                $baseDir = Join-Path -Path $resolvedRepoRoot -ChildPath "base"
                $keepExistingFiles = @()
                if ($KeepArchitecture) {
                    $keepExistingFiles = @("copilot-instructions.md", "copilot-infra-nutshell.md")
                }
                Copy-DirectoryContents -SourcePath $baseDir -DestinationPath $githubDir -KeepExistingFiles $keepExistingFiles
                Write-ProtectedConfigBaseline -GithubDir $githubDir

                # Dual-platform mirror: generate the Claude Code (.claude) layout
                # from the same base sources just copied into .github above.
                # Skipped with -SkipClaude (Copilot-only install); any existing
                # .claude/CLAUDE.md was already handled by Prepare above per --backup/--purge.
                if (-not $SkipClaude) {
                    Copy-ClaudeMirror -BaseDir $baseDir -ClaudeDir $claudeDir -WorkspaceRoot $workspace.FullName
                }
            }

            # Local overlay tier: final overwrite so local files win over base.
            if (Test-TierHasContent -Root $resolvedLocal) {
                $localCopied = Apply-LocalOverlayTier -SourceRoot $resolvedLocal -GithubDir $githubDir -WorkspaceRoot $workspace.FullName -SkipClaude:$SkipClaude
                Write-Host "Applied local overlay tier ($localCopied files) from $resolvedLocal to $githubDir"
            }

            if (-not $SkipClaude) {
                Rebuild-ClaudeEffectiveMirror -GithubDir $githubDir -WorkspaceRoot $workspace.FullName
            }

            # Strip Git placeholder files from the rendered targets so tooling
            # (e.g. Deva session resume) is not confused by shipped .gitignore/.gitkeep.
            $placeholderRoots = @($githubDir)
            if (-not $SkipClaude) { $placeholderRoots += $claudeDir }
            Remove-VcsPlaceholderFiles -Roots $placeholderRoots
        }

        # If WorkspaceName was specified but not found, report error
        if ($WorkspaceName -and -not $workspaceFound) {
            Write-Host ""
            Write-Host "ERROR: Workspace '$WorkspaceName' not found at $projectsRoot"
            Write-Host ""
            exit 1
        }
    } else {
        Write-Host "  (No workspaces found)"
        if ($WorkspaceName) {
            Write-Host ""
            Write-Host "ERROR: No workspaces found at $projectsRoot"
            Write-Host ""
            exit 1
        }
    }
} else {
    Write-Host "$projectsRoot does not exist and could not be created."
    if ($WorkspaceName) {
        exit 1
    }
}

Write-Host ""
