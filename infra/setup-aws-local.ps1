<#
    Set up the Agent Toolkit for AWS on a Windows developer machine.

    Installs the AWS CLI v2, signs in with `aws login`, installs the Agent
    Toolkit (the AWS skills plus the aws-mcp server), and writes the AWS rules
    file into a project that does not already carry one.

    Run this from PowerShell, not cmd.exe. If your coding agent runs inside
    WSL rather than on Windows, use infra/setup-aws-local.sh inside WSL
    instead: the toolkit must be installed in the same home directory the
    agent reads from.

    Usage:
        .\infra\setup-aws-local.ps1 [-Region eu-central-1]
#>

[CmdletBinding()]
param(
    [string]$Region = 'eu-central-1'
)

$ErrorActionPreference = 'Stop'

# The Agent Toolkit control plane is only reachable in us-east-1. This is not
# the region your resources live in, and it must not be swapped for $Region.
$ToolkitRegion = 'us-east-1'

$InstallerUrl = 'https://awscli.amazonaws.com/v2/install.ps1'
$RulesUrl     = 'https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Note($m) { Write-Host "    $m" }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "`nerror: $m" -ForegroundColor Red; exit 1 }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# The MSI edits the machine PATH, which the running session does not see.
function Update-PathFromRegistry {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') +
                ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

Step 'Checking prerequisites'

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Die 'PowerShell 5 or newer is required.'
}

try {
    Invoke-WebRequest -Uri $InstallerUrl -Method Head -UseBasicParsing | Out-Null
} catch {
    Die "cannot reach $InstallerUrl. Check network access and re-run."
}

Note "PowerShell $($PSVersionTable.PSVersion): ok"

# Nothing below installs through winget, but a machine that cannot reach it is
# worth one line while prerequisites are already being checked. The client
# ships inside the App Installer package and is reached only through an app
# execution alias. That alias is per user and survives reinstalls, so once it
# is switched off the package is still listed, every reinstall reports success,
# and the command stays gone.
if (Have 'winget') {
    Note 'winget: ok'
} else {
    # Probing the package is only interesting once the command is missing.
    # PowerShell 7 reaches Appx through the Windows PowerShell compatibility
    # layer, which is not always there; unknown is not a failure.
    $appInstaller = $null
    try {
        $appInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction Stop 3>$null
    } catch {
        $appInstaller = $null
    }

    if ($appInstaller) {
        Warn 'WARNING: App Installer is present but winget is not callable.'
        Warn '         Turn the alias back on under Settings > Apps > Advanced'
        Warn '         app settings > App execution aliases, or re-register it:'
        Warn '         Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    } else {
        Warn 'WARNING: winget not found. Install App Installer from the Microsoft'
        Warn '         Store, or from https://aka.ms/getwinget.'
    }
}

# ---------------------------------------------------------------------------
# 1. AWS CLI v2
# ---------------------------------------------------------------------------

# `aws login` arrived well after the first v2 releases, so an existing install
# is not automatically good enough. Reinstall when the subcommand is absent.
$needsCli = $true
if (Have 'aws') {
    $version = (aws --version 2>&1) -join ' '
    if ($version -match 'aws-cli/2\.') {
        aws login help *> $null
        if ($LASTEXITCODE -eq 0) {
            $needsCli = $false
        } else {
            Note "$version predates 'aws login'; upgrading"
        }
    }
}

if ($needsCli) {
    Step 'Installing AWS CLI v2'
    Invoke-RestMethod $InstallerUrl | Invoke-Expression
    Update-PathFromRegistry
} else {
    Step 'AWS CLI v2 already present'
}

if (-not (Have 'aws')) {
    Die 'aws still not on PATH after install. Open a new PowerShell window and re-run.'
}
Note ((aws --version 2>&1) -join ' ')

# ---------------------------------------------------------------------------
# 2. Region and sign in
# ---------------------------------------------------------------------------

Step "Setting default region to $Region"
aws configure set region $Region

# Re-running the whole script should not force a fresh browser round trip.
# Credentials last 12 hours, so a valid session is worth keeping.
aws sts get-caller-identity *> $null
if ($LASTEXITCODE -eq 0) {
    Step 'Existing credentials are still valid; skipping sign in'
} else {
    Step 'Signing in to AWS'
    Note 'A browser window will open. Complete sign in there.'
    Note 'If no browser opens, re-run:'
    Note "  aws login --region $Region --remote"
    aws login --region $Region
    if ($LASTEXITCODE -ne 0) { Die 'aws login did not complete.' }
}

# ---------------------------------------------------------------------------
# 3. Verify access
# ---------------------------------------------------------------------------

Step 'Verifying access'
aws sts get-caller-identity
if ($LASTEXITCODE -ne 0) {
    Die "credentials are not working. Re-run 'aws login --region $Region'."
}

# ---------------------------------------------------------------------------
# 4. Agent Toolkit
# ---------------------------------------------------------------------------

Step "Installing the Agent Toolkit (region $ToolkitRegion)"

# --yes is not accepted by every CLI build, and on a non-interactive stdin the
# wizard bails with 253. Fall back rather than leaving the toolkit uninstalled.
aws configure agent-toolkit --yes --region $ToolkitRegion
if ($LASTEXITCODE -ne 0) {
    Note 'non-interactive install failed; retrying as the interactive wizard'
    aws configure agent-toolkit --region $ToolkitRegion
    if ($LASTEXITCODE -ne 0) { Die 'the Agent Toolkit did not install.' }
}

Step 'Verifying the Agent Toolkit'
aws agent-toolkit list-available-skills --region $ToolkitRegion *> $null
if ($LASTEXITCODE -ne 0) {
    Die 'the toolkit did not install cleanly. Re-run this script.'
}
Note 'skill catalog reachable'

# The aws-mcp server is launched as 'uvx mcp-proxy-for-aws@latest'. Without uv
# the server entry exists but never starts, which is easy to miss.
if (Have 'uvx') {
    Note 'uvx: ok'
} else {
    Warn 'WARNING: uvx not found, so the aws-mcp server cannot start.'
    Warn '         Install it with: irm https://astral.sh/uv/install.ps1 | iex'
}

# ---------------------------------------------------------------------------
# 5. Rules file
# ---------------------------------------------------------------------------

Step 'Checking the AWS rules file'

$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
}
$rulesPath = Join-Path $repoRoot 'CLAUDE.md'

$tmpRules = [System.IO.Path]::GetTempFileName()
try {
    Invoke-WebRequest -Uri $RulesUrl -OutFile $tmpRules -UseBasicParsing

    if (-not (Test-Path $rulesPath)) {
        Copy-Item $tmpRules $rulesPath
        Note "wrote $rulesPath"
    } else {
        $a = (Get-FileHash $tmpRules).Hash
        $b = (Get-FileHash $rulesPath).Hash
        if ($a -eq $b) {
            Note "$rulesPath already matches upstream"
        } else {
            # Overwriting would discard project instructions that are not ours
            # to drop.
            Note "$rulesPath exists and differs from upstream; leaving it alone."
            Note 'Compare with:'
            Note "  Invoke-WebRequest $RulesUrl -OutFile upstream.md; Compare-Object (gc $rulesPath) (gc upstream.md)"
        }
    }
} finally {
    Remove-Item $tmpRules -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------

Step 'Done'
Note 'Credentials are valid for 12 hours, renewable for 90 days without'
Note 'repeating the browser sign in. Restart your agent session to pick up'
Note 'the aws-mcp server and the installed skills.'
