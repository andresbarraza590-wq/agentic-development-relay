#==============================================================================
# clone-bitbucket-repo.ps1 - Clone a Git repository
#==============================================================================
# Clones a Git repository to a specified location, similar to the <BASE_ENGINEERING_ECOSYSTEM>
# bootstrap pattern.
#
# This script:
# - Takes repo URL, branch, and destination as parameters
# - Validates git connectivity (user-provided protocol first, then the alternate as fallback)
# - Clones the repo
# - Sets up environment variables if needed
#
# Usage:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File clone-bitbucket-repo.ps1 `
#     -RepoUrl "ssh://git@..." -Branch "develop" -DestinationPath "<WORKSPACE_PROJECTS_ROOT>\path\to\repo"
#==============================================================================
param(
    [string]$RepoUrl = "",
    [string]$Branch = "develop",
    [string]$DestinationPath = "",
    [switch]$UpdateOnly,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Validate required parameters
if (-not $UpdateOnly -and [string]::IsNullOrWhiteSpace($RepoUrl)) {
    Write-Host "ERROR: -RepoUrl parameter is required" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
    Write-Host "ERROR: -DestinationPath parameter is required" -ForegroundColor Red
    exit 1
}

function Log-Message {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Protect-RepositoryUrlToken {
    param([string]$Token)

    if ([string]::IsNullOrEmpty($Token)) { return $Token }
    $protected = $Token
    $schemeMatch = [regex]::Match(
        $protected,
        '^(?<scheme>[A-Za-z][A-Za-z0-9+.-]*://)(?<authority>[^/?#]*)(?<rest>.*)$'
    )
    if ($schemeMatch.Success) {
        $authority = $schemeMatch.Groups['authority'].Value
        $atIndex = $authority.LastIndexOf('@')
        if ($atIndex -ge 0) {
            $authority = '<redacted>@' + $authority.Substring($atIndex + 1)
        }
        $protected = $schemeMatch.Groups['scheme'].Value + $authority + $schemeMatch.Groups['rest'].Value
    } elseif ($protected -match '^(?<user>[^@\s]+)@(?<host>[^:\s]+):(?<path>.+)$') {
        $protected = '<redacted>@' + $Matches['host'] + ':' + $Matches['path']
    }
    return ($protected -replace '(?:[?#]).*$', '<redacted>')
}

function Protect-RepositoryUrl {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $protected = [regex]::Replace(
        $Value,
        '(?i)[A-Za-z][A-Za-z0-9+.-]*://[^\s"''<>]+',
        { param($match) Protect-RepositoryUrlToken $match.Value }
    )
    return [regex]::Replace(
        $protected,
        '(?i)(?<![/A-Za-z0-9._-])[^@\s"''<>]+@[^:\s"''<>]+:[^\s"''<>]+',
        { param($match) Protect-RepositoryUrlToken $match.Value }
    )
}

function Test-GitConnectivity {
    param(
        [string]$RepoUrl,
        [switch]$RetryWithOutput
    )

    if ($Verbose) {
        Log-Message "Testing git connectivity to $(Protect-RepositoryUrl $RepoUrl)"
    }

    # Match <BASE_ENGINEERING_ECOSYSTEM> bootstrap semantics: trust git exit code, not stderr content.
    # Some environments print non-fatal warnings on stderr during successful SSH handshakes.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git ls-remote $RepoUrl HEAD *> $null
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($rc -eq 0) {
        return $true
    }

    if ($RetryWithOutput) {
        Log-Message "Connectivity check failed for $(Protect-RepositoryUrl $RepoUrl) (exit code $rc). Retrying with sanitized output..." "WARN"
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $gitOutput = @(& git ls-remote $RepoUrl HEAD 2>&1)
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        $gitOutput | ForEach-Object { Write-Host (Protect-RepositoryUrl ([string]$_)) }
        if ($rc -eq 0) {
            return $true
        }
    }

    if ($Verbose) {
        Log-Message "Git connectivity test failed for $(Protect-RepositoryUrl $RepoUrl) (exit code $rc)" "WARN"
    }

    return $false
}

function Convert-SshToHttps {
    param(
        [string]$SshUrl
    )

    $sshMatch = [regex]::Match($SshUrl, '^ssh://git@(?<host>[^:/]+):\d+/(?<path>.+)$')
    if (-not $sshMatch.Success) {
        return $null
    }

    $sshHost = $sshMatch.Groups['host'].Value
    $repoPath = $sshMatch.Groups['path'].Value
    $httpsHost = $sshHost -replace '-ssh(?=\.)', ''
    return "https://$httpsHost/scm/$repoPath"
}

function Convert-HttpsToSsh {
    param(
        [string]$HttpsUrl
    )

    $httpsMatch = [regex]::Match($HttpsUrl, '^https://(?<host>[^/]+)/scm/(?<path>.+)$')
    if (-not $httpsMatch.Success) {
        return $null
    }

    $httpsHost = $httpsMatch.Groups['host'].Value
    $repoPath = $httpsMatch.Groups['path'].Value

    if ($httpsHost -notmatch '-ssh\.') {
        $sshHost = $httpsHost -replace '^([^.]+)\.', '$1-ssh.'
    } else {
        $sshHost = $httpsHost
    }

    return "ssh://git@$sshHost`:7999/$repoPath"
}

function Ensure-GitInstalled {
    $gitPath = where.exe git.exe 2>$null
    if (-not $gitPath) {
        Log-Message "ERROR: git.exe not found on PATH" "ERROR"
        exit 1
    }

    if ($Verbose) {
        Log-Message "Git found at: $gitPath"
    }
}

function Get-RepositoryIdentity {
    param([string]$Url)

    $value = $Url.Trim().TrimEnd('/') -replace '\.git$', ''
    $ssh = [regex]::Match($value, '^ssh://git@(?<host>[^:/]+):\d+/(?<path>.+)$')
    if ($ssh.Success) {
        $hostName = $ssh.Groups['host'].Value -replace '-ssh(?=\.)', ''
        return ($hostName + '/' + $ssh.Groups['path'].Value).ToLowerInvariant()
    }
    $https = [regex]::Match($value, '^https://(?<host>[^/]+)/scm/(?<path>.+)$')
    if ($https.Success) {
        $hostName = $https.Groups['host'].Value -replace '-ssh(?=\.)', ''
        return ($hostName + '/' + $https.Groups['path'].Value).ToLowerInvariant()
    }
    return $value.ToLowerInvariant()
}

function Clone-Repository {
    param(
        [string]$Url,
        [string]$Branch,
        [string]$Destination
    )

    try {
        Log-Message "Cloning repo from $(Protect-RepositoryUrl $Url) (branch: $Branch) to $Destination"

        # Create parent directory if it doesn't exist
        $parentDir = Split-Path -Path $Destination -Parent
        if (-not (Test-Path -Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            Log-Message "Created parent directory: $parentDir"
        }

        # If destination exists, treat it as an update target.
        if (Test-Path -Path $Destination) {
            if (-not (Test-Path -Path (Join-Path $Destination '.git'))) {
                Log-Message "Destination exists but is not a git repository: $Destination" "ERROR"
                return $false
            }
            Log-Message "Destination already exists. Verifying branch '$Branch' before update: $Destination"
            Push-Location $Destination
            try {
                $originUrl = (git remote get-url origin).Trim()
                if ($LASTEXITCODE -ne 0 -or
                    (Get-RepositoryIdentity -Url $originUrl) -ne (Get-RepositoryIdentity -Url $Url)) {
                    Log-Message "Existing destination origin '$(Protect-RepositoryUrl $originUrl)' does not match requested repository '$(Protect-RepositoryUrl $Url)'" "ERROR"
                    return $false
                }

                $currentBranch = (git branch --show-current).Trim()
                if ($LASTEXITCODE -ne 0 -or $currentBranch -ne $Branch) {
                    Log-Message "Existing destination is on branch '$currentBranch', not requested branch '$Branch'. Switch branches explicitly or choose a matching destination." "ERROR"
                    return $false
                }

                $updateUrl = $originUrl
                $replaceOriginAfterPull = $false
                if (-not (Test-GitConnectivity -RepoUrl $originUrl)) {
                    $updateUrl = $Url
                    $replaceOriginAfterPull = $originUrl -ne $Url
                    Log-Message "Existing origin is unreachable. Updating through the verified protocol fallback: $(Protect-RepositoryUrl $updateUrl)" "WARN"
                }

                $gitOutput = @(& git pull --rebase $updateUrl $Branch 2>&1)
                $gitRc = $LASTEXITCODE
                $gitOutput | ForEach-Object { Write-Host (Protect-RepositoryUrl ([string]$_)) }
                if ($gitRc -eq 0) {
                    if ($replaceOriginAfterPull) {
                        & git remote set-url origin $updateUrl
                        if ($LASTEXITCODE -ne 0) {
                            Log-Message "Repository updated, but the working fallback could not be persisted as origin." "ERROR"
                            return $false
                        }
                        Log-Message "Updated origin to the verified working protocol: $(Protect-RepositoryUrl $updateUrl)"
                    }
                    Log-Message "Repository branch '$Branch' updated successfully via git pull --rebase"
                    return $true
                }

                Log-Message "Failed to update repository (exit code: $gitRc)" "ERROR"
                return $false
            }
            finally {
                Pop-Location
            }
        }

        # Clone the repo when destination does not exist.
        $gitOutput = @(& git clone --quiet --branch $Branch $Url $Destination 2>&1)
        $gitRc = $LASTEXITCODE
        $gitOutput | ForEach-Object { Write-Host (Protect-RepositoryUrl ([string]$_)) }

        if ($gitRc -eq 0) {
            Log-Message "Repository cloned successfully to: $Destination"
            return $true
        } else {
            Log-Message "Failed to clone repository (exit code: $gitRc)" "ERROR"
            return $false
        }
    } catch {
        Log-Message "Clone operation failed: $(Protect-RepositoryUrl ([string]$_))" "ERROR"
        return $false
    }
}

function Update-Repository {
    param([string]$Destination)

    if (-not (Test-Path -LiteralPath (Join-Path $Destination '.git'))) {
        Log-Message "Destination is not a Git repository: $Destination" "ERROR"
        return $false
    }

    Push-Location $Destination
    try {
        $gitOutput = @(& git pull --rebase 2>&1)
        $gitRc = $LASTEXITCODE
        $gitOutput | ForEach-Object { Write-Host (Protect-RepositoryUrl ([string]$_)) }
        if ($gitRc -eq 0) {
            Log-Message "Overlay repository updated successfully via git pull --rebase"
            return $true
        }
        Log-Message "Failed to update overlay repository (exit code: $gitRc)" "ERROR"
        return $false
    } catch {
        Log-Message "Overlay update failed: $(Protect-RepositoryUrl ([string]$_))" "ERROR"
        return $false
    } finally {
        Pop-Location
    }
}

#==============================================================================
# Main execution
#==============================================================================

if ($UpdateOnly) {
    Ensure-GitInstalled
    if (Update-Repository -Destination $DestinationPath) { exit 0 }
    exit 1
}

Log-Message "=== Repository Clone Script ==="
Log-Message "Destination: $DestinationPath"
Log-Message "Repository URL: $(Protect-RepositoryUrl $RepoUrl)"
Log-Message "Branch: $Branch"

# Validate git is installed
Ensure-GitInstalled

# Test connectivity
Log-Message "Testing connectivity to repository..."
$connectivity = $false

# Match <BASE_ENGINEERING_ECOSYSTEM>-like flow: try user-provided protocol first, then fallback.
if ($RepoUrl -match '^ssh://') {
    if (Test-GitConnectivity -RepoUrl $RepoUrl -RetryWithOutput) {
        $connectivity = $true
        Log-Message "SSH connectivity OK - using SSH"
    } else {
        $httpsUrl = Convert-SshToHttps -SshUrl $RepoUrl
        if ($httpsUrl) {
            Log-Message "SSH connectivity failed. Trying HTTPS fallback: $(Protect-RepositoryUrl $httpsUrl)" "WARN"
            if (Test-GitConnectivity -RepoUrl $httpsUrl -RetryWithOutput) {
                $RepoUrl = $httpsUrl
                $connectivity = $true
                Log-Message "HTTPS connectivity OK - using HTTPS"
            }
        }
    }
} elseif ($RepoUrl -match '^https://') {
    if (Test-GitConnectivity -RepoUrl $RepoUrl -RetryWithOutput) {
        $connectivity = $true
        Log-Message "HTTPS connectivity OK - using HTTPS"
    } else {
        $sshUrl = Convert-HttpsToSsh -HttpsUrl $RepoUrl
        if ($sshUrl) {
            Log-Message "HTTPS connectivity failed. Trying SSH fallback: $(Protect-RepositoryUrl $sshUrl)" "WARN"
            if (Test-GitConnectivity -RepoUrl $sshUrl -RetryWithOutput) {
                $RepoUrl = $sshUrl
                $connectivity = $true
                Log-Message "SSH connectivity OK - using SSH"
            }
        }
    }
} else {
    if (Test-GitConnectivity -RepoUrl $RepoUrl -RetryWithOutput) {
        $connectivity = $true
        Log-Message "Repository connectivity OK"
    }
}

if (-not $connectivity) {
    Log-Message "Could not reach repository at $(Protect-RepositoryUrl $RepoUrl)" "ERROR"
    exit 2
}

# Clone the repository
$cloneResult = Clone-Repository -Url $RepoUrl -Branch $Branch -Destination $DestinationPath

if ($cloneResult) {
    Log-Message "=== Clone completed successfully ==="
    exit 0
} else {
    Log-Message "=== Clone failed ===" "ERROR"
    exit 1
}
