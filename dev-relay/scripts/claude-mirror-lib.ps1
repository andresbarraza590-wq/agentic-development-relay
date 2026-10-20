#==============================================================================
# claude-mirror-lib.ps1 - Shared Copilot -> Claude Code transform functions
#==============================================================================
# Dot-sourced by BOTH setup-workspace.ps1 (base install) and
# setup-overlay.ps1 (overlay install) so the .github -> .claude transform is
# identical for base and overlay assets. Single source of truth for the
# dual-platform mirror (transform-at-install).
#
# This file defines PURE functions only (no top-level side effects) so it is
# safe to dot-source. Orchestration (which files, which destinations) stays in
# each caller.
#==============================================================================

# Map a Copilot agent model string (e.g. "Claude Opus 4.8 (copilot)") to a
# Claude Code model alias. Returns $null when there is nothing to map (inherit).
function Get-ClaudeModelAlias {
    param([string]$ModelLine)

    if ([string]::IsNullOrWhiteSpace($ModelLine)) { return $null }
    if ($ModelLine -match '(?i)opus')   { return 'opus' }
    if ($ModelLine -match '(?i)sonnet') { return 'sonnet' }
    if ($ModelLine -match '(?i)haiku')  { return 'haiku' }
    return 'inherit'
}

# Map supported Copilot tool tokens to Claude Code tool names. Unsupported MCP
# globs and unknown tokens are omitted without discarding mapped restrictions.
# When a declared list contains only unsupported tokens, emit an explicit empty
# list so the generated artifact does not inherit all tools.
function Convert-ToolsToClaude {
    param(
        [string]$ToolsInner,
        [switch]$Declared
    )

    $map = @{
        'read'    = @('Read')
        'search'  = @('Grep', 'Glob')
        'edit'    = @('Edit', 'Write')
        'write'   = @('Write')
        'execute' = @('Bash')
        'agent'   = @('Task')
        'web'     = @('WebFetch', 'WebSearch')
        'todo'    = @('TodoWrite')
    }

    $result = New-Object System.Collections.Generic.List[string]
    $hasDeclaredToken = $false
    foreach ($token in ($ToolsInner -split ',')) {
        $tok = $token.Trim().Trim("'").Trim('"')
        if ($tok -eq '') { continue }
        $hasDeclaredToken = $true
        if ($tok -like '*/*' -or $tok -like 'mcp*') { continue }
        if (-not $map.ContainsKey($tok)) { continue }
        foreach ($m in $map[$tok]) {
            if (-not $result.Contains($m)) { $result.Add($m) }
        }
    }

    if ($result.Count -eq 0) {
        if ($Declared -or $hasDeclaredToken) { return '[]' }
        return $null
    }
    return ($result -join ', ')
}

# Extract a declared tools list from frontmatter. Supports both the inline YAML
# sequence used by base assets and an indented block sequence used by overlays.
function Get-CopilotToolsDeclaration {
    param(
        [string[]]$Lines,
        [int]$Start,
        [int]$End
    )

    for ($i = $Start; $i -lt $End; $i++) {
        if ($Lines[$i] -match '^\s*tools:\s*\[(.*)\]\s*$') {
            return [pscustomobject]@{ Declared = $true; Inner = $Matches[1] }
        }
        if ($Lines[$i] -notmatch '^\s*tools:\s*$') { continue }

        $tokens = New-Object System.Collections.Generic.List[string]
        for ($j = $i + 1; $j -lt $End; $j++) {
            if ($Lines[$j] -match '^\s+-\s*(.+?)\s*$') {
                $tokens.Add($Matches[1])
                continue
            }
            if ([string]::IsNullOrWhiteSpace($Lines[$j])) { continue }
            break
        }
        return [pscustomobject]@{ Declared = $true; Inner = ($tokens -join ',') }
    }
    return [pscustomobject]@{ Declared = $false; Inner = $null }
}

# The mirror intentionally supports the frontmatter shapes it emits. Fail
# visibly when a translated scalar uses YAML block syntax rather than silently
# treating the marker as the field value.
function Assert-NoClaudeFrontmatterBlockScalars {
    param(
        [string[]]$Lines,
        [int]$Start,
        [int]$End,
        [string]$SourceFile
    )

    for ($i = $Start; $i -lt $End; $i++) {
        if ($Lines[$i] -match '^\s*(description|model|argument-hint|tools):\s*[>|](?:[+-][1-9]?|[1-9][+-]?)?\s*(?:#.*)?$') {
            throw "Unsupported YAML block scalar for '$($Matches[1])' in '$SourceFile'. Use a single-line value or an inline/list tools declaration."
        }
    }
}

function Assert-ClaudeFrontmatterScalarShape {
    param(
        [string[]]$Lines,
        [int]$Start,
        [int]$End,
        [string]$SourceFile
    )

    $seen = @{}
    for ($i = $Start; $i -lt $End; $i++) {
        if ($Lines[$i] -notmatch '^\s*(description|model|argument-hint):\s*(.*?)\s*$') { continue }

        $key = $Matches[1]
        $value = $Matches[2]
        if ($seen.ContainsKey($key)) {
            throw "Duplicate YAML frontmatter key '$key' in '$SourceFile'."
        }
        $seen[$key] = $true

        if ([string]::IsNullOrWhiteSpace($value) -or
            $value -match '^[!&*\[\{]' -or
            $value -match '^(?i:null|true|false|yes|no|on|off|~|[-+]?(?:0|[1-9][0-9_]*)(?:\.[0-9_]+)?(?:e[-+]?[0-9]+)?|[-+]?\.(?:inf|nan)|[0-9]{4}-[0-9]{2}-[0-9]{2})$' -or
            ($value.StartsWith("'") -and -not $value.EndsWith("'")) -or
            ($value.StartsWith('"') -and -not $value.EndsWith('"'))) {
            throw "Unsupported non-string or structured YAML scalar for '$key' in '$SourceFile'. Use one plain or quoted string."
        }
    }
}

# Transform one Copilot agent (agents/<name>.agent.md) into a Claude Code
# subagent (.claude/agents/<name>.md) with translated frontmatter. The body is
# copied verbatim. Tolerates the .agent.md and plain .md source suffixes so a
# legacy source name still maps to the same dest name; callers pass *.agent.md.
function Convert-ToClaudeAgent {
    param(
        [string]$SourceFile,
        [string]$DestDir,
        [System.Text.Encoding]$Encoder
    )

    $name = [System.IO.Path]::GetFileName($SourceFile) -replace '\.agent\.md$', '' -replace '\.md$', ''
    $raw = Get-Content -LiteralPath $SourceFile -Raw -Encoding UTF8
    $lines = $raw -split "`r`n"

    $descValue = $null
    $modelLine = $null
    $toolsDeclaration = [pscustomobject]@{ Declared = $false; Inner = $null }
    $bodyStart = 0

    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        $close = -1
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { $close = $i; break }
        }
        if ($close -lt 0) {
            throw "Unclosed YAML frontmatter in Copilot agent: $SourceFile"
        }
        if ($close -gt 0) {
            Assert-NoClaudeFrontmatterBlockScalars -Lines $lines -Start 1 -End $close -SourceFile $SourceFile
            Assert-ClaudeFrontmatterScalarShape -Lines $lines -Start 1 -End $close -SourceFile $SourceFile
            for ($i = 1; $i -lt $close; $i++) {
                $fl = $lines[$i]
                if ($fl -match '^\s*description:\s*(.+)$') { $descValue = $Matches[1].Trim() }
                elseif ($fl -match '^\s*model:\s*(.+)$') { $modelLine = $Matches[1].Trim() }
            }
            $toolsDeclaration = Get-CopilotToolsDeclaration -Lines $lines -Start 1 -End $close
            $bodyStart = $close + 1
        }
    }

    $body = if ($bodyStart -lt $lines.Count) {
        ($lines[$bodyStart..($lines.Count - 1)]) -join "`r`n"
    } else {
        ''
    }

    $fm = New-Object System.Collections.Generic.List[string]
    $fm.Add('---')
    $fm.Add("name: $name")
    if ($descValue) { $fm.Add("description: $descValue") }

    $toolsCsv = $null
    if ($toolsDeclaration.Declared) { $toolsCsv = Convert-ToolsToClaude -ToolsInner $toolsDeclaration.Inner -Declared }
    if ($toolsCsv) { $fm.Add("tools: $toolsCsv") }

    $alias = Get-ClaudeModelAlias -ModelLine $modelLine
    if ($alias -and $alias -ne 'inherit') { $fm.Add("model: $alias") }

    $fm.Add('---')
    $fm.Add("<!-- Generated from $name (Copilot agent) by install.bat (dual-platform mirror). Do not edit directly. -->")
    $fm.Add('')

    $out = ($fm -join "`r`n") + "`r`n" + $body
    $dest = Join-Path -Path $DestDir -ChildPath "$name.md"
    [System.IO.File]::WriteAllText($dest, $out, $Encoder)
}

# Transform one Copilot prompt file (prompts/<name>.prompt.md) into a Claude Code
# slash command (.claude/commands/<name>.md) with translated frontmatter. The body
# is copied verbatim. Copilot prompt frontmatter maps as: description -> description,
# argument-hint -> argument-hint, tools -> allowed-tools (via Convert-ToolsToClaude;
# unsupported tokens omitted without broadening mapped restrictions), model -> mapped alias.
# The Copilot-only `agent` field has no Claude equivalent and is dropped.
function Convert-ToClaudeCommand {
    param(
        [string]$SourceFile,
        [string]$DestDir,
        [System.Text.Encoding]$Encoder
    )

    $name = [System.IO.Path]::GetFileName($SourceFile) -replace '\.prompt\.md$', '' -replace '\.md$', ''
    $raw = Get-Content -LiteralPath $SourceFile -Raw -Encoding UTF8
    $lines = $raw -split "`r`n"

    $descValue = $null
    $modelLine = $null
    $toolsDeclaration = [pscustomobject]@{ Declared = $false; Inner = $null }
    $argHint = $null
    $bodyStart = 0

    if ($lines.Count -gt 0 -and $lines[0].Trim() -eq '---') {
        $close = -1
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { $close = $i; break }
        }
        if ($close -lt 0) {
            throw "Unclosed YAML frontmatter in Copilot prompt: $SourceFile"
        }
        if ($close -gt 0) {
            Assert-NoClaudeFrontmatterBlockScalars -Lines $lines -Start 1 -End $close -SourceFile $SourceFile
            Assert-ClaudeFrontmatterScalarShape -Lines $lines -Start 1 -End $close -SourceFile $SourceFile
            for ($i = 1; $i -lt $close; $i++) {
                $fl = $lines[$i]
                if ($fl -match '^\s*description:\s*(.+)$') { $descValue = $Matches[1].Trim() }
                elseif ($fl -match '^\s*model:\s*(.+)$') { $modelLine = $Matches[1].Trim() }
                elseif ($fl -match '^\s*argument-hint:\s*(.+)$') { $argHint = $Matches[1].Trim() }
            }
            $toolsDeclaration = Get-CopilotToolsDeclaration -Lines $lines -Start 1 -End $close
            $bodyStart = $close + 1
        }
    }

    $body = if ($bodyStart -lt $lines.Count) {
        ($lines[$bodyStart..($lines.Count - 1)]) -join "`r`n"
    } else {
        ''
    }

    # Collect only the frontmatter fields that have a value. Command frontmatter is
    # optional in Claude Code, so when a prompt has no mappable metadata (common for
    # our prose-only prompts) we skip the fences entirely and keep the file clean.
    $fields = New-Object System.Collections.Generic.List[string]
    if ($descValue) { $fields.Add("description: $descValue") }
    if ($argHint) { $fields.Add("argument-hint: $argHint") }

    $toolsCsv = $null
    if ($toolsDeclaration.Declared) { $toolsCsv = Convert-ToolsToClaude -ToolsInner $toolsDeclaration.Inner -Declared }
    if ($toolsCsv) { $fields.Add("allowed-tools: $toolsCsv") }

    $alias = Get-ClaudeModelAlias -ModelLine $modelLine
    if ($alias -and $alias -ne 'inherit') { $fields.Add("model: $alias") }

    $banner = "<!-- Generated from $name (Copilot prompt) by install.bat (dual-platform mirror). Do not edit directly. -->"

    $out = New-Object System.Collections.Generic.List[string]
    if ($fields.Count -gt 0) {
        $out.Add('---')
        foreach ($f in $fields) { $out.Add($f) }
        $out.Add('---')
    }
    $out.Add($banner)
    $out.Add('')

    $final = ($out -join "`r`n") + "`r`n" + $body
    $dest = Join-Path -Path $DestDir -ChildPath "$name.md"
    [System.IO.File]::WriteAllText($dest, $final, $Encoder)
}

# Rewrite links from root CLAUDE.md to companion documents mirrored under
# .claude/ with Claude-native names.
function Convert-ClaudeInstructionLinks {
    param([string]$Content)

    foreach ($doc in @("architecture.html", "architecture.md", "data-model.md", "infra-nutshell.md")) {
        $Content = $Content.Replace("./copilot-$doc", "./.claude/copilot-$doc")
    }
    $Content = $Content.Replace("./copilot-instructions.md", "./CLAUDE.md")
    # Runtime architecture/session artifacts remain authoritative under .github
    # and are intentionally not copied into .claude. Preserve explicit .github
    # links and rebase tier-relative artifact links before the generic rewrite.
    $Content = $Content -replace '(\]\()\./\.github/artifacts/', '$1__DEVA_GITHUB_ARTIFACTS__/'
    $Content = $Content -replace '(\]\()\.github/artifacts/', '$1__DEVA_GITHUB_ARTIFACTS__/'
    $Content = $Content -replace '(\]\()\.?/?artifacts/', '$1__DEVA_GITHUB_ARTIFACTS__/'
    $Content = $Content -replace '(\]\()\./\.github/', '$1./.claude/'
    $Content = $Content -replace '(\]\()\.github/', '$1.claude/'
    foreach ($directory in @("docs", "images", "agents", "skills", "scripts")) {
        $Content = $Content -replace "(\]\()\./$directory/", "`$1./.claude/$directory/"
    }
    $Content = $Content.Replace('](__DEVA_GITHUB_ARTIFACTS__/', '](./.github/artifacts/')
    return $Content
}

# Rewrite links in framework documents copied under .claude. Root README links
# climb once to CLAUDE.md; documents under .claude/docs climb twice.
function Convert-ClaudeFrameworkDocumentLinks {
    param(
        [string]$Content,
        [ValidateSet('root', 'docs')]
        [string]$Location,
        [int]$NestedDepth = 0
    )

    if ($Location -eq 'docs') {
        $sourcePrefix = '../' * ($NestedDepth + 1)
        $targetPrefix = '../' * ($NestedDepth + 2)
        return $Content.Replace(
            "${sourcePrefix}copilot-instructions.md",
            "${targetPrefix}CLAUDE.md"
        )
    }
    return $Content.Replace('copilot-instructions.md', '../CLAUDE.md')
}

# Mirror general content directories recursively. Markdown documentation needs
# its instruction links rebased for its final location under .claude/docs.
function Copy-ClaudeContentDirectories {
    param(
        [string]$SourceRoot,
        [string]$ClaudeDir
    )

    foreach ($directory in @("docs", "images")) {
        $source = Join-Path -Path $SourceRoot -ChildPath $directory
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
        $destination = Join-Path -Path $ClaudeDir -ChildPath $directory
        if (-not (Test-Path -LiteralPath $destination)) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
        }
        Get-ChildItem -Path $source -Force -ErrorAction Stop | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        }
        if ($directory -eq 'docs') {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            Get-ChildItem -LiteralPath $destination -Filter '*.md' -File -Recurse | ForEach-Object {
                $relativeDirectory = $_.DirectoryName.Substring($destination.Length).TrimStart('\', '/')
                $nestedDepth = @($relativeDirectory -split '[\\/]' | Where-Object { $_ }).Count
                $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
                $content = Convert-ClaudeFrameworkDocumentLinks -Content $content -Location docs -NestedDepth $nestedDepth
                [System.IO.File]::WriteAllText($_.FullName, $content, $utf8NoBom)
            }
        }
    }
}

# Copy architecture companion documents under Claude-native names and rewrite
# their cross-file references so links still resolve after the rename.
function Copy-ClaudeArchitectureDocuments {
    param(
        [string]$SourceRoot,
        [string]$ClaudeDir,
        [System.Text.Encoding]$Encoder
    )

    foreach ($doc in @("copilot-architecture.html", "copilot-architecture.md", "copilot-data-model.md", "copilot-infra-nutshell.md")) {
        $src = Join-Path -Path $SourceRoot -ChildPath $doc
        if (-not (Test-Path -LiteralPath $src)) { continue }

        $destName = $doc -replace '^copilot-', 'claude-'
        $content = Get-Content -LiteralPath $src -Raw -Encoding UTF8
        $content = $content -replace 'copilot-architecture\.html', 'claude-architecture.html'
        $content = $content -replace 'copilot-architecture\.md', 'claude-architecture.md'
        $content = $content -replace 'copilot-data-model\.md', 'claude-data-model.md'
        $content = $content -replace 'copilot-infra-nutshell\.md', 'claude-infra-nutshell.md'
        [System.IO.File]::WriteAllText((Join-Path -Path $ClaudeDir -ChildPath $destName), $content, $Encoder)
    }
}

# Normalize a local overlay tier source path. Absolute paths are used as-is;
# relative paths resolve against the current working directory. Returns "" for
# empty input.
function Resolve-LocalTierSource {
    param([string]$LocalPath)

    if ([string]::IsNullOrWhiteSpace($LocalPath)) { return "" }
    $candidate = $LocalPath
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path -Path (Get-Location).Path -ChildPath $candidate
    }
    return [System.IO.Path]::GetFullPath($candidate)
}

# True when a directory exists and holds at least one real file (ignoring
# .gitkeep placeholders).
function Test-TierHasContent {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    if (-not (Test-Path -Path $Root)) { return $false }
    $files = @(Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.gitkeep' })
    return ($files.Count -gt 0)
}

# --- Company-wide protected configuration ----------------------------------
# default-config.yaml and guardrails.yaml are org-wide fixed: the base copy is
# authoritative and NO overlay tier (workspace, repo, or local) may replace it.
# The base install writes them first; these helpers keep an overlay tier from
# overriding them in .github/config and in the flat .claude mirror.
function Get-ProtectedConfigFileName {
    return @('default-config.yaml', 'guardrails.yaml')
}

# True when a tier-relative path targets a protected config file, either under
# config/<name> or at the tier root (which flattens into .github/<name>).
function Test-ProtectedOverlayConfigPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/').ToLowerInvariant()
    foreach ($name in (Get-ProtectedConfigFileName)) {
        $lowerName = $name.ToLowerInvariant()
        if ($normalized -eq ('config/' + $lowerName)) { return $true }
        if ($normalized -eq $lowerName) { return $true }
    }
    return $false
}

function Test-ReservedOverlayPath {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/').TrimStart('/').ToLowerInvariant()
    return $normalized -eq '.overlay-manifests' -or $normalized.StartsWith('.overlay-manifests/')
}

# Warn through the caller's Log-Message when present, else to the host.
function Write-ProtectedConfigWarning {
    param([string]$Message)

    $logger = Get-Command -Name 'Log-Message' -ErrorAction SilentlyContinue
    if ($logger) { Log-Message $Message 'WARN' }
    else { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
}

# Copy one overlay tier into .github without allowing protected config bytes to
# touch the destination. Returns the number of copied non-placeholder files.
function Copy-OverlayTierToGithub {
    param(
        [string]$SourceRoot,
        [string]$GithubDir,
        [string]$TierLabel = 'overlay'
    )

    $copied = 0
    Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Force -ErrorAction Stop | ForEach-Object {
        $relativePath = $_.FullName.Substring($SourceRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if (Test-ProtectedOverlayConfigPath -RelativePath $relativePath) {
            Write-ProtectedConfigWarning "Protected config '$($_.Name)' cannot be overridden by the $TierLabel tier; excluded from the physical copy."
            return
        }
        if (Test-ReservedOverlayPath -RelativePath $relativePath) { return }
        if ($_.Name -eq '.gitkeep') { return }
        $targetPath = Join-Path -Path $GithubDir -ChildPath $relativePath
        $targetParent = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Force -ErrorAction Stop
        $copied++
    }
    return $copied
}

# Copy a tier's config/*.yaml into the flat .claude directory, skipping the
# protected files so the base .claude copy stays authoritative.
function Copy-ClaudeTierConfigYaml {
    param([string]$SourceDir, [string]$ClaudeDir)

    if (-not (Test-Path -LiteralPath $SourceDir)) { return }
    $protected = Get-ProtectedConfigFileName
    foreach ($pattern in @('*.yaml', '*.yml')) {
        Get-ChildItem -Path $SourceDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($protected -notcontains $_.Name) {
                Copy-Item -Path $_.FullName -Destination $ClaudeDir -Force -ErrorAction Stop
            } else {
                Write-ProtectedConfigWarning "Protected config '$($_.Name)' is not mirrored from an overlay tier into .claude; kept the base copy."
            }
        }
    }
}

# Record the installer-established SHA-256 baseline for the protected config
# files so resolve-config.py can detect post-install tampering (a hand-edit,
# not an overlay override). Called once per base install, right after the
# base tier is copied into .github, so the baseline always reflects whatever
# bytes the installer just wrote as authoritative.
function Write-ProtectedConfigBaseline {
    param([string]$GithubDir)

    $configDir = Join-Path -Path $GithubDir -ChildPath 'config'
    $protectedPaths = [ordered]@{}
    foreach ($name in (Get-ProtectedConfigFileName)) {
        $path = Join-Path -Path $configDir -ChildPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Protected base config is incomplete; missing required file: $path"
        }
        $protectedPaths[$name] = $path
    }
    if ($protectedPaths.Count -ne (Get-ProtectedConfigFileName).Count) {
        throw 'Protected base config must contain exactly default-config.yaml and guardrails.yaml.'
    }

    $cacheConfigDir = Join-Path -Path $GithubDir -ChildPath 'cache/config'
    if (-not (Test-Path -LiteralPath $cacheConfigDir)) {
        New-Item -ItemType Directory -Path $cacheConfigDir -Force | Out-Null
    }

    $files = [ordered]@{}
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($name in $protectedPaths.Keys) {
            $digest = $hasher.ComputeHash([System.IO.File]::ReadAllBytes($protectedPaths[$name]))
            $files[$name] = ([System.BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
        }
    } finally {
        $hasher.Dispose()
    }
    $baseline = [ordered]@{
        schema = 1
        generated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        files = $files
    } | ConvertTo-Json -Depth 4

    $baselinePath = Join-Path -Path $cacheConfigDir -ChildPath 'protected-config-baseline.json'
    $temporaryPath = $baselinePath + '.tmp'
    [System.IO.File]::WriteAllText($temporaryPath, $baseline, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryPath -Destination $baselinePath -Force
}

# Overwrite a workspace/repo .github (and mirror to .claude) with a local overlay
# tier rooted at $SourceRoot. The tier layout matches overlays/workspace:
# root *.md/*.html/*.yaml/*.yml, agents/*.md, prompts/*.md, skills/*, and
# docs/**/*.md,*.json. Intended as the FINAL install step so local files win over
# both base and overlay. No-op (returns 0) when $SourceRoot is missing/empty.
function Apply-LocalOverlayTier {
    param(
        [string]$SourceRoot,
        [string]$GithubDir,
        [string]$WorkspaceRoot,
        [switch]$SkipClaude
    )

    if (-not $SkipClaude -and $env:AI_SKIP_CLAUDE -eq '1') { $SkipClaude = $true }

    if (-not (Test-TierHasContent -Root $SourceRoot)) { return 0 }
    if (-not (Test-Path -Path $GithubDir)) {
        New-Item -ItemType Directory -Path $GithubDir -Force | Out-Null
    }

    # --- .github: copy the entire local tier recursively (same as base/overlay) ---
    # Every file and sub-directory under the source lands in .github; root files
    # flatten to .github/, sub-directories (agents, prompts, skills, docs, ...)
    # copy as-is except for company-wide protected config, which is excluded
    # before any destination write rather than copied and restored afterward.
    $copied = Copy-OverlayTierToGithub -SourceRoot $SourceRoot -GithubDir $GithubDir -TierLabel 'local'

    # --- .claude mirror (same transforms as base/overlay) ---
    # Skipped entirely with -SkipClaude so the local tier never creates or
    # overrides .claude/CLAUDE.md (Copilot-only install).
    if ($SkipClaude) { return $copied }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $claudeDir = Join-Path -Path $WorkspaceRoot -ChildPath ".claude"
    if (-not (Test-Path -Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

    $instr = Join-Path -Path $SourceRoot -ChildPath "copilot-instructions.md"
    if (Test-Path -LiteralPath $instr) {
        $banner = "<!-- Generated from the local overlay copilot-instructions.md by install.bat (dual-platform mirror). Do not edit directly. -->"
        $content = Get-Content -LiteralPath $instr -Raw -Encoding UTF8
        $content = Convert-ClaudeInstructionLinks -Content $content
        [System.IO.File]::WriteAllText((Join-Path -Path $WorkspaceRoot -ChildPath "CLAUDE.md"), ($banner + "`r`n`r`n" + $content), $utf8NoBom)
    }

    $agentsSrc = Join-Path -Path $SourceRoot -ChildPath "agents"
    if (Test-Path -LiteralPath $agentsSrc) {
        $claudeAgents = Join-Path -Path $claudeDir -ChildPath "agents"
        if (-not (Test-Path -Path $claudeAgents)) { New-Item -ItemType Directory -Path $claudeAgents -Force | Out-Null }
        Get-ChildItem -Path $agentsSrc -Filter '*.agent.md' -ErrorAction SilentlyContinue | ForEach-Object {
            Convert-ToClaudeAgent -SourceFile $_.FullName -DestDir $claudeAgents -Encoder $utf8NoBom
        }
    }

    $skillsSrc = Join-Path -Path $SourceRoot -ChildPath "skills"
    if (Test-Path -LiteralPath $skillsSrc) {
        $claudeSkills = Join-Path -Path $claudeDir -ChildPath "skills"
        if (-not (Test-Path -Path $claudeSkills)) { New-Item -ItemType Directory -Path $claudeSkills -Force | Out-Null }
        Copy-Item -Path (Join-Path -Path $skillsSrc -ChildPath "*") -Destination $claudeSkills -Recurse -Force -ErrorAction Stop
    }

    $scriptsSrc = Join-Path -Path $SourceRoot -ChildPath "scripts"
    if (Test-Path -LiteralPath $scriptsSrc) {
        $claudeScripts = Join-Path $claudeDir -ChildPath "scripts"
        if (-not (Test-Path -Path $claudeScripts)) { New-Item -ItemType Directory -Path $claudeScripts -Force | Out-Null }
        Copy-Item -Path (Join-Path -Path $scriptsSrc -ChildPath "*") -Destination $claudeScripts -Recurse -Force -ErrorAction Stop
    }

    Copy-ClaudeArchitectureDocuments -SourceRoot $SourceRoot -ClaudeDir $claudeDir -Encoder $utf8NoBom
    Copy-ClaudeContentDirectories -SourceRoot $SourceRoot -ClaudeDir $claudeDir

    $promptsSrc = Join-Path -Path $SourceRoot -ChildPath "prompts"
    if (Test-Path -LiteralPath $promptsSrc) {
        $promptFiles = @(Get-ChildItem -Path $promptsSrc -Filter "*.prompt.md" -ErrorAction SilentlyContinue)
        if ($promptFiles.Count -gt 0) {
            $claudeCommands = Join-Path $claudeDir -ChildPath "commands"
            if (-not (Test-Path -Path $claudeCommands)) { New-Item -ItemType Directory -Path $claudeCommands -Force | Out-Null }
            $promptFiles | ForEach-Object {
                Convert-ToClaudeCommand -SourceFile $_.FullName -DestDir $claudeCommands -Encoder $utf8NoBom
            }
        }
    }

    $protectedNames = Get-ProtectedConfigFileName
    foreach ($pattern in @("*.yaml", "*.yml")) {
        Get-ChildItem -Path $SourceRoot -Filter $pattern -File -ErrorAction SilentlyContinue |
            Where-Object { $protectedNames -notcontains $_.Name } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $claudeDir -Force -ErrorAction Stop
            }
    }

    Copy-ClaudeTierConfigYaml -SourceDir (Join-Path -Path $SourceRoot -ChildPath "config") -ClaudeDir $claudeDir

    return $copied
}

function Write-ClaudeEffectiveMirror {
    param(
        [string]$GithubDir,
        [string]$WorkspaceRoot
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $claudeDir = Join-Path -Path $WorkspaceRoot -ChildPath '.claude'
    $claudeMd = Join-Path -Path $WorkspaceRoot -ChildPath 'CLAUDE.md'
    if (-not (Test-Path -LiteralPath $claudeDir -PathType Container)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $instructions = Join-Path -Path $GithubDir -ChildPath 'copilot-instructions.md'
    if (Test-Path -LiteralPath $instructions -PathType Leaf) {
        $banner = '<!-- Generated from .github/copilot-instructions.md by install.bat (dual-platform mirror). Do not edit directly. -->'
        $content = Get-Content -LiteralPath $instructions -Raw -Encoding UTF8
        $content = Convert-ClaudeInstructionLinks -Content $content
        [System.IO.File]::WriteAllText($claudeMd, ($banner + "`r`n`r`n" + $content), $utf8NoBom)
    }

    $agentsSrc = Join-Path -Path $GithubDir -ChildPath 'agents'
    if (Test-Path -LiteralPath $agentsSrc -PathType Container) {
        $agentsDest = Join-Path -Path $claudeDir -ChildPath 'agents'
        New-Item -ItemType Directory -Path $agentsDest -Force | Out-Null
        Get-ChildItem -LiteralPath $agentsSrc -Filter '*.agent.md' -File | ForEach-Object {
            Convert-ToClaudeAgent -SourceFile $_.FullName -DestDir $agentsDest -Encoder $utf8NoBom
        }
    }

    foreach ($directory in @('skills', 'scripts')) {
        $source = Join-Path -Path $GithubDir -ChildPath $directory
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
        $destination = Join-Path -Path $claudeDir -ChildPath $directory
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        }
    }

    $promptsSrc = Join-Path -Path $GithubDir -ChildPath 'prompts'
    if (Test-Path -LiteralPath $promptsSrc -PathType Container) {
        $commandsDest = Join-Path -Path $claudeDir -ChildPath 'commands'
        New-Item -ItemType Directory -Path $commandsDest -Force | Out-Null
        Get-ChildItem -LiteralPath $promptsSrc -Filter '*.prompt.md' -File | ForEach-Object {
            Convert-ToClaudeCommand -SourceFile $_.FullName -DestDir $commandsDest -Encoder $utf8NoBom
        }
    }

    $configSrc = Join-Path -Path $GithubDir -ChildPath 'config'
    if (Test-Path -LiteralPath $configSrc -PathType Container) {
        Get-ChildItem -LiteralPath $configSrc -File | Where-Object { $_.Extension -in @('.yaml', '.yml') } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $claudeDir -Force -ErrorAction Stop
        }
    }
    # Root YAML is mirrored after config/, so protected names are excluded here to
    # keep a stray root copy from overwriting the base copy already mirrored.
    $protectedNames = Get-ProtectedConfigFileName
    Get-ChildItem -LiteralPath $GithubDir -File | Where-Object { $_.Extension -in @('.yaml', '.yml') -and $protectedNames -notcontains $_.Name } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $claudeDir -Force -ErrorAction Stop
    }

    Copy-ClaudeArchitectureDocuments -SourceRoot $GithubDir -ClaudeDir $claudeDir -Encoder $utf8NoBom
    Copy-ClaudeContentDirectories -SourceRoot $GithubDir -ClaudeDir $claudeDir

    $readme = Join-Path -Path $GithubDir -ChildPath 'README.md'
    if (Test-Path -LiteralPath $readme -PathType Leaf) {
        $content = Get-Content -LiteralPath $readme -Raw -Encoding UTF8
        $content = Convert-ClaudeFrameworkDocumentLinks -Content $content -Location root
        [System.IO.File]::WriteAllText((Join-Path -Path $claudeDir -ChildPath 'README.md'), $content, $utf8NoBom)
    }
}

function Rebuild-ClaudeEffectiveMirror {
    param(
        [string]$GithubDir,
        [string]$WorkspaceRoot
    )

    $manifestDir = Join-Path -Path $GithubDir -ChildPath '.overlay-manifests'
    $manifestPath = Join-Path -Path $manifestDir -ChildPath 'claude-effective.json'
    $stagingRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("deva-claude-mirror-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    try {
        Write-ClaudeEffectiveMirror -GithubDir $GithubDir -WorkspaceRoot $stagingRoot

        $stagedFiles = @()
        $stagedClaude = Join-Path -Path $stagingRoot -ChildPath '.claude'
        if (Test-Path -LiteralPath $stagedClaude -PathType Container) {
            $stagedFiles += @(Get-ChildItem -LiteralPath $stagedClaude -Recurse -File | ForEach-Object {
                [pscustomobject]@{
                    path = '.claude/' + $_.FullName.Substring($stagedClaude.Length).TrimStart('\', '/').Replace('\', '/')
                    source = $_.FullName
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            })
        }
        $stagedClaudeMd = Join-Path -Path $stagingRoot -ChildPath 'CLAUDE.md'
        if (Test-Path -LiteralPath $stagedClaudeMd -PathType Leaf) {
            $stagedFiles += [pscustomobject]@{
                path = 'CLAUDE.md'
                source = $stagedClaudeMd
                sha256 = (Get-FileHash -LiteralPath $stagedClaudeMd -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

        $currentPaths = @{}
        foreach ($entry in $stagedFiles) { $currentPaths[$entry.path.ToLowerInvariant()] = $true }
        $staleTargets = New-Object System.Collections.Generic.List[object]
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $prior = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($prior.files)) {
                $relativePath = [string]$entry.path
                if ([string]::IsNullOrWhiteSpace($relativePath) -or $currentPaths.ContainsKey($relativePath.ToLowerInvariant())) { continue }
                $target = Get-ContainedPath -Root $WorkspaceRoot -Child $relativePath -Description 'Stale generated Claude file'
                if ((Test-Path -LiteralPath $target) -and
                    (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$entry.sha256) {
                    $staleTargets.Add([pscustomobject]@{ path = $relativePath; target = $target })
                } else {
                    Write-Warning "Preserved changed stale Claude path: $target"
                }
            }
        }

        $rollbackRoot = Join-Path -Path $stagingRoot -ChildPath 'rollback'
        New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
        $rollbackEntries = New-Object System.Collections.Generic.List[object]
        $rollbackPaths = @{}
        $mutationCandidates = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $stagedFiles) {
            $mutationCandidates.Add([pscustomobject]@{
                path = $entry.path
                target = Get-ContainedPath -Root $WorkspaceRoot -Child $entry.path -Description 'Generated Claude file'
            })
        }
        foreach ($entry in $staleTargets) { $mutationCandidates.Add($entry) }
        foreach ($candidate in $mutationCandidates) {
            $pathKey = $candidate.target.ToLowerInvariant()
            if ($rollbackPaths.ContainsKey($pathKey)) { continue }
            if (Test-Path -LiteralPath $candidate.target -PathType Container) {
                throw "Generated Claude file path collides with a directory: $($candidate.target)"
            }
            $existed = Test-Path -LiteralPath $candidate.target -PathType Leaf
            $backup = Join-Path -Path $rollbackRoot -ChildPath ([guid]::NewGuid().ToString('N'))
            if ($existed) {
                Copy-Item -LiteralPath $candidate.target -Destination $backup -Force -ErrorAction Stop
            }
            $rollbackEntries.Add([pscustomobject]@{ target = $candidate.target; existed = $existed; backup = $backup })
            $rollbackPaths[$pathKey] = $true
        }

        $manifestExisted = Test-Path -LiteralPath $manifestPath -PathType Leaf
        $manifestBackup = Join-Path -Path $rollbackRoot -ChildPath 'manifest.json'
        if ($manifestExisted) {
            Copy-Item -LiteralPath $manifestPath -Destination $manifestBackup -Force -ErrorAction Stop
        }

        try {
            foreach ($entry in $staleTargets) {
                Remove-Item -LiteralPath $entry.target -Force -ErrorAction Stop
            }
            foreach ($entry in $stagedFiles) {
                $target = Get-ContainedPath -Root $WorkspaceRoot -Child $entry.path -Description 'Generated Claude file'
                $targetParent = Split-Path -Path $target -Parent
                if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $entry.source -Destination $target -Force -ErrorAction Stop
            }

            if (-not (Test-Path -LiteralPath $manifestDir -PathType Container)) {
                New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
            }
            $manifest = [ordered]@{
                schema = 1
                files = @($stagedFiles | ForEach-Object { [ordered]@{ path = $_.path; sha256 = $_.sha256 } })
            } | ConvertTo-Json -Depth 5
            $manifestTemp = $manifestPath + '.tmp'
            [System.IO.File]::WriteAllText($manifestTemp, $manifest, (New-Object System.Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force
        } catch {
            foreach ($entry in $rollbackEntries) {
                if ($entry.existed) {
                    $targetParent = Split-Path -Path $entry.target -Parent
                    if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
                        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $entry.backup -Destination $entry.target -Force -ErrorAction Stop
                } elseif (Test-Path -LiteralPath $entry.target -PathType Leaf) {
                    Remove-Item -LiteralPath $entry.target -Force -ErrorAction Stop
                }
            }
            if ($manifestExisted) {
                Copy-Item -LiteralPath $manifestBackup -Destination $manifestPath -Force -ErrorAction Stop
            } elseif (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
            }
            if (Test-Path -LiteralPath ($manifestPath + '.tmp') -PathType Leaf) {
                Remove-Item -LiteralPath ($manifestPath + '.tmp') -Force -ErrorAction SilentlyContinue
            }
            throw
        }
        foreach ($entry in $staleTargets) {
            Write-Host "Removed stale generated Claude file: $($entry.target)"
        }
        Write-Host "Reconciled Claude mirror from effective GitHub instructions: $WorkspaceRoot"
    } finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Unconditionally remove every Git placeholder file (.gitignore, .gitkeep) under
# each rendered target root without prompting. The framework payload ships these
# files only to keep empty runtime directories tracked in source control; once
# installed they confuse tooling such as Deva session resume. The externally
# owned modernize/java-upgrade/.gitignore is the sole exception because it is
# owned by separate Java migration tooling, not this framework.
function Remove-VcsPlaceholderFiles {
    param(
        [string[]]$Roots
    )

    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
        $preserved = [System.IO.Path]::GetFullPath((Join-Path -Path $rootFull -ChildPath 'modernize\java-upgrade\.gitignore'))

        Get-ChildItem -LiteralPath $rootFull -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '.gitignore' -or $_.Name -eq '.gitkeep' } |
            ForEach-Object {
                if ($_.Name -eq '.gitignore' -and
                    [string]::Equals($_.FullName, $preserved, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return
                }
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    Write-Host "Removed Git placeholder $($_.FullName)"
                } catch {
                    Write-Host "WARNING: Could not remove $($_.FullName): $($_.Exception.Message)"
                }
            }
    }
}
