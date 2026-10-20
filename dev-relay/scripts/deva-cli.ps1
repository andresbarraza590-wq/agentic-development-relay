#requires -Version 5.1
<#
.SYNOPSIS
  deva CLI - installs, updates, and inspects the Agentic AI Instruction Framework.
.DESCRIPTION
  Invoked only by deva.bat, and only for the reserved verbs (install, update,
  status, version, help). Passthrough arguments never reach this script; the
  shim sends those straight to install.bat so GNU-style '--' flags survive.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Verb = 'help',
    [string]$Branch,
    [ValidateSet('git', 'share')][string]$Source,
    [Alias('Home')][string]$HomePath,
    [switch]$NoPull
)

$ErrorActionPreference = 'Stop'

# Native commands write progress to stderr; under 'Stop' a redirected stderr line
# becomes a terminating NativeCommandError. Run them under 'Continue' and judge
# success by $LASTEXITCODE instead.
function Invoke-Native([scriptblock]$Block) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Block } finally { $ErrorActionPreference = $prev }
}

# .NET rather than Get-FileHash: the cmdlet's module is not always loadable in a
# restricted or -NoProfile shell, and this must run anywhere the installer does.
function Get-Sha256([string]$Path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

# --- Defaults. Overridable by environment, then by flags. ---
$DefaultHome  = '<FRAMEWORK_HOME>'
$DefaultGit   = '<DEFAULT_GIT_REMOTE_URL>'
$DefaultShare = '<DEFAULT_SHARE_PATH>'
$DefaultBranch = 'develop'

function Write-Section([string]$Text) { Write-Host ""; Write-Host "=== $Text ===" -ForegroundColor Cyan }
function Write-Step([string]$Text)    { Write-Host "  $Text" }
function Write-Ok([string]$Text)      { Write-Host "  $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text)   { Write-Host "  $Text" -ForegroundColor Yellow }
function Fail([string]$Text)          { Write-Host "  $Text" -ForegroundColor Red; exit 1 }

function Get-PersistedOr([string]$Name, [string]$Fallback) {
    $v = [Environment]::GetEnvironmentVariable($Name, 'User')
    if ($v) { return $v }
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v) { return $v }
    return $Fallback
}

# Where was the CLI invoked from? The repo root is deva-cli.ps1's parent's parent
# when running from a checkout (scripts\deva-cli.ps1), else its own directory.
function Get-InvocationRoot {
    $dir = Split-Path -Parent $PSCommandPath
    if ((Split-Path -Leaf $dir) -ieq 'scripts') { return (Split-Path -Parent $dir) }
    return $dir
}

# git checkout -> git; UNC path -> share. Explicit flag and persisted value win.
function Resolve-SourceMode {
    if ($Source) { return $Source }
    $persisted = [Environment]::GetEnvironmentVariable('DEVA_SOURCE', 'User')
    if ($persisted) { return $persisted }
    $root = Get-InvocationRoot
    if (Test-Path (Join-Path $root '.git')) { return 'git' }
    if ($root -like '\\*') { return 'share' }
    return 'git'
}

function Get-Paths {
    $root = if ($HomePath) { $HomePath.TrimEnd('\') } else { (Get-PersistedOr 'DEVA_HOME' $DefaultHome).TrimEnd('\') }
    [pscustomobject]@{
        Home      = $root
        Src       = Join-Path $root 'deva'
        Bin       = Join-Path $root 'bin'
        Installer = Join-Path (Join-Path $root 'deva') 'install.bat'
        GitUrl    = Get-PersistedOr 'DEVA_GIT_URL' $DefaultGit
        Share     = Get-PersistedOr 'DEVA_SHARE'   $DefaultShare
        Branch    = if ($Branch) { $Branch } else { Get-PersistedOr 'DEVA_BRANCH' $DefaultBranch }
    }
}

function Test-Installed($p) {
    if (-not [Environment]::GetEnvironmentVariable('DEVA_HOME', 'User')) { return $false }
    if (-not (Test-Path $p.Src)) { return $false }
    if (-not (Test-Path (Join-Path $p.Bin 'deva.bat'))) { return $false }
    return $true
}

function Get-SrcRevision($p, [string]$Mode) {
    if ($Mode -eq 'git' -and (Test-Path (Join-Path $p.Src '.git'))) {
        $rev = Invoke-Native { & git -C $p.Src rev-parse --short HEAD 2>$null }
        if ($LASTEXITCODE -eq 0 -and $rev) { return "$rev".Trim() }
    }
    $stamp = Join-Path $p.Src '.deva-sync'
    if (Test-Path $stamp) { return (Get-Content $stamp -Raw).Trim() }
    return '(unknown)'
}

function Sync-Source($p, [string]$Mode) {
    if ($Mode -eq 'git') {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) { Fail "git is not on PATH; use -Source share or install git." }

        if (Test-Path (Join-Path $p.Src '.git')) {
            $dirty = Invoke-Native { & git -C $p.Src status --porcelain 2>$null }
            if ($dirty) { Fail "$($p.Src) has local changes. It is a managed copy - resolve or remove it, then retry." }
            Write-Step "fetching $($p.Branch)"
            Invoke-Native { & git -C $p.Src fetch --quiet origin $p.Branch 2>&1 | Out-Null }
            Invoke-Native { & git -C $p.Src checkout --quiet $p.Branch 2>&1 | Out-Null }
            if ($LASTEXITCODE -ne 0) { Fail "cannot check out branch '$($p.Branch)'." }
            Invoke-Native { & git -C $p.Src pull --ff-only --quiet origin $p.Branch 2>&1 | Out-Null }
            if ($LASTEXITCODE -ne 0) { Fail "git pull --ff-only failed for '$($p.Branch)'." }
        } else {
            Write-Step "cloning $($p.GitUrl) ($($p.Branch))"
            Invoke-Native { & git clone --quiet --branch $p.Branch $p.GitUrl $p.Src 2>&1 | Out-Null }
            if ($LASTEXITCODE -ne 0) { Fail "git clone failed." }
        }
    } else {
        if ($Branch) { Fail "-Branch applies to git sources only; share copies carry no branch." }
        if (-not (Test-Path $p.Share)) { Fail "share not reachable: $($p.Share)" }
        Write-Step "mirroring $($p.Share)"
        # /NJH /NJS /NP quiet; robocopy exit codes below 8 mean success.
        Invoke-Native { & robocopy $p.Share $p.Src /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null }
        if ($LASTEXITCODE -ge 8) { Fail "robocopy failed with code $LASTEXITCODE." }
        Set-Content (Join-Path $p.Src '.deva-sync') ((Get-Date).ToString('s')) -Encoding ASCII
    }
    Write-Ok "source synced"
}

# .ps1 first, .bat last, and only when changed - the running .bat must be the
# last thing rewritten, and ideally not rewritten at all.
function Install-Cli($p) {
    # Prefer the synced source; fall back to whatever copy is running. Probe both
    # the repo layout (scripts\deva-cli.ps1) and the installed flat layout.
    $root = Get-InvocationRoot
    $batCandidates = @((Join-Path $p.Src 'deva.bat'), (Join-Path $root 'deva.bat'))
    $ps1Candidates = @((Join-Path $p.Src 'scripts\deva-cli.ps1'),
                       (Join-Path $root 'scripts\deva-cli.ps1'),
                       (Join-Path $root 'deva-cli.ps1'))
    $shimCandidates = @((Join-Path $p.Src 'deva'), (Join-Path $root 'deva'))
    $srcBat  = $batCandidates  | Where-Object { Test-Path $_ } | Select-Object -First 1
    $srcPs1  = $ps1Candidates  | Where-Object { Test-Path $_ } | Select-Object -First 1
    $srcShim = $shimCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $srcBat -or -not $srcPs1) {
        Write-Warn2 "source does not ship the deva CLI; keeping the existing copy"
        return
    }

    New-Item -ItemType Directory -Force -Path $p.Bin | Out-Null
    $changed = 0
    # Order matters: .ps1 and the optional POSIX shim before .bat, so the running
    # .bat is the last file rewritten. The shim is optional - older sources omit it.
    $pairs = @(@{ From = $srcPs1; To = (Join-Path $p.Bin 'deva-cli.ps1') })
    if ($srcShim) { $pairs += @{ From = $srcShim; To = (Join-Path $p.Bin 'deva') } }
    $pairs += @{ From = $srcBat; To = (Join-Path $p.Bin 'deva.bat') }
    foreach ($pair in $pairs) {
        if ((Resolve-Path $pair.From).Path -ieq $pair.To) { continue }
        $needed = $true
        if (Test-Path $pair.To) {
            $needed = ((Get-Sha256 $pair.From) -ne (Get-Sha256 $pair.To))
        }
        if ($needed) { Copy-Item $pair.From $pair.To -Force; $changed++ }
    }
    if ($changed -gt 0) { Write-Ok "CLI refreshed ($changed file(s))" } else { Write-Step "CLI already current" }
}

function Persist-Environment($p, [string]$Mode) {
    $vars = [ordered]@{
        DEVA_HOME      = $p.Home
        DEVA_SRC       = $p.Src
        DEVA_BIN       = $p.Bin
        DEVA_INSTALLER = $p.Installer
        DEVA_SOURCE    = $Mode
        DEVA_GIT_URL   = $p.GitUrl
        DEVA_SHARE     = $p.Share
        DEVA_BRANCH    = $p.Branch
    }
    foreach ($k in $vars.Keys) {
        if ([Environment]::GetEnvironmentVariable($k, 'User') -ne $vars[$k]) {
            [Environment]::SetEnvironmentVariable($k, $vars[$k], 'User')
        }
        Set-Item -Path "Env:$k" -Value $vars[$k]
    }
    Write-Ok "environment persisted (User scope)"

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $p.Bin) {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $p.Bin), 'User')
        Write-Ok "added $($p.Bin) to user PATH"
    } else {
        Write-Step "PATH already contains $($p.Bin)"
    }
}

function Show-Help {
@"
deva - Agentic AI Instruction Framework

USAGE
  deva install [-Branch <b>] [-Source git|share] [-Home <path>] [-NoPull]
                     Provision and sync. Safe to re-run.
  deva update  [-Branch <b>]
                     Sync only. Requires an existing install.
  deva status        Show resolved environment and current revision.
  deva version       Show framework version and revision.
  deva help          This message.

  deva <any other args>    Passed straight through to install.bat, e.g.
                     deva --workspace ai --skip-overlay --skip-claude
                     deva overlay add ai --url <ssh-url>
                     deva --help              (install.bat's own help)

ENVIRONMENT
  DEVA_HOME      install root (default $DefaultHome)
  DEVA_SRC       synced copy of the framework repository
  DEVA_BIN       CLI location, added to PATH
  DEVA_INSTALLER install.bat used for passthrough
  DEVA_SOURCE    git | share
  DEVA_GIT_URL   git source
  DEVA_SHARE     shared-directory source
  DEVA_BRANCH    base branch (git only)
"@ | Write-Host
}

# ---------------- verbs ----------------

switch ($Verb.ToLowerInvariant()) {

    'install' {
        $p = Get-Paths
        $mode = Resolve-SourceMode
        Write-Section "deva install"
        Write-Step "DEVA_HOME   = $($p.Home)"
        Write-Step "source      = $mode"
        if ($mode -eq 'git') { Write-Step "branch      = $($p.Branch)" }

        New-Item -ItemType Directory -Force -Path $p.Home | Out-Null
        New-Item -ItemType Directory -Force -Path $p.Bin  | Out-Null

        if ($NoPull) {
            Write-Warn2 "-NoPull: skipping source sync"
            if (-not (Test-Path $p.Installer)) { Fail "no source at $($p.Src); run without -NoPull first." }
        } else {
            Sync-Source $p $mode
        }

        Install-Cli $p
        Persist-Environment $p $mode

        Write-Section "Install complete"
        Write-Step "revision : $(Get-SrcRevision $p $mode)"
        Write-Step "installer: $($p.Installer)"
        Write-Host ""
        Write-Warn2 "Open a NEW terminal for 'deva' to be on PATH."
        Write-Step "Then run:  deva --workspace <name> --backup --skip-overlay"
    }

    'update' {
        $p = Get-Paths
        $mode = Resolve-SourceMode
        if ($NoPull) { Fail "-NoPull is not valid for 'update'; syncing is its purpose." }
        if (-not (Test-Installed $p)) {
            Write-Section "deva update"
            Fail "not installed (need DEVA_HOME, $($p.Src), and $($p.Bin)\deva.bat). Run: deva install"
        }
        Write-Section "deva update"
        $before = Get-SrcRevision $p $mode
        Sync-Source $p $mode
        Install-Cli $p
        $after = Get-SrcRevision $p $mode
        if ($before -eq $after) { Write-Ok "already up to date ($after)" }
        else { Write-Ok "updated $before -> $after" }
    }

    'status' {
        $p = Get-Paths
        $mode = Resolve-SourceMode
        Write-Section "deva status"
        Write-Step "DEVA_HOME     : $($p.Home)"
        Write-Step "DEVA_SRC      : $($p.Src)"
        Write-Step "DEVA_BIN      : $($p.Bin)"
        Write-Step "DEVA_INSTALLER : $($p.Installer)"
        Write-Step "source        : $mode"
        if ($mode -eq 'git') { Write-Step "branch        : $($p.Branch)" }
        Write-Step "revision      : $(Get-SrcRevision $p $mode)"
        if (Test-Installed $p) { Write-Ok "installed" } else { Write-Warn2 "not installed - run 'deva install'" }
        if (Test-Path $p.Installer) { Write-Ok "installer found" } else { Write-Warn2 "installer missing" }
        $onPath = ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') -contains $p.Bin
        if ($onPath) { Write-Ok "on user PATH" } else { Write-Warn2 "not on user PATH" }
        $ovl = Join-Path $p.Home 'overlays'
        if (Test-Path $ovl) {
            $names = @(Get-ChildItem $ovl -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
            if ($names.Count -gt 0) { Write-Step "overlays      : $($names -join ', ')" }
            else { Write-Step "overlays      : (none)" }
        }
    }

    'version' {
        $p = Get-Paths
        $mode = Resolve-SourceMode
        $readme = Join-Path $p.Src 'README.md'
        $ver = '(unknown)'
        if (Test-Path $readme) {
            $line = Select-String -Path $readme -Pattern '^Version:\s*(.+)$' | Select-Object -First 1
            if ($line) { $ver = $line.Matches[0].Groups[1].Value.Trim() }
        }
        Write-Section "deva version"
        Write-Step "framework : $ver"
        Write-Step "revision  : $(Get-SrcRevision $p $mode)"
        Write-Step "source    : $mode"
    }

    default { Show-Help }
}

exit 0
