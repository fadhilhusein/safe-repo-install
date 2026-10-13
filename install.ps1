<#
.SYNOPSIS
  Copy the safe-repo-install skill into your AI tool skill folders (Windows).

.DESCRIPTION
  Default targets: Claude Code (~\.claude\skills) and Codex (~\.codex\skills).
  Only copies SKILL.md, scripts\ and references\. Never runs anything from the skill.

.EXAMPLE
  .\install.ps1
  .\install.ps1 -All -Force
  .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
  [switch]$Claude,
  [switch]$Codex,
  [switch]$Agents,
  [switch]$All,
  [string]$Dest,
  [switch]$Force,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Name = 'safe-repo-install'
$Src = $PSScriptRoot
$UserHome = [Environment]::GetFolderPath('UserProfile')

if ($All) { $Claude = $true; $Codex = $true; $Agents = $true }
if (-not ($Claude -or $Codex -or $Agents -or $Dest)) { $Claude = $true; $Codex = $true }

$targets = @()
if ($Claude) { $targets += Join-Path $UserHome '.claude\skills' }
if ($Codex)  { $targets += Join-Path $UserHome '.codex\skills' }
if ($Agents) { $targets += Join-Path $UserHome '.agents\skills' }
if ($Dest)   { $targets += $Dest }

foreach ($base in $targets) {
  $target = Join-Path $base $Name

  if ($Uninstall) {
    if (Test-Path -LiteralPath $target) {
      Remove-Item -LiteralPath $target -Recurse -Force
      Write-Host "removed   $target"
    } else {
      Write-Host "absent    $target"
    }
    continue
  }

  if (Test-Path -LiteralPath $target) {
    if ($Force) {
      Remove-Item -LiteralPath $target -Recurse -Force
    } else {
      $ans = Read-Host "$target already exists. Overwrite? [y/N]"
      if ($ans -notmatch '^(y|yes)$') {
        Write-Host "skipped   $target"
        continue
      }
      Remove-Item -LiteralPath $target -Recurse -Force
    }
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $target 'scripts') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $target 'references') | Out-Null
  Copy-Item -LiteralPath (Join-Path $Src 'SKILL.md') -Destination $target
  Copy-Item -LiteralPath (Join-Path $Src 'scripts\audit_repo.sh') -Destination (Join-Path $target 'scripts')
  Copy-Item -LiteralPath (Join-Path $Src 'references\manual-checks.md') -Destination (Join-Path $target 'references')
  Write-Host "installed $target"
}

if (-not $Uninstall) {
  Write-Host ''
  Write-Host 'Done. Restart Claude Code / Codex so the skill loads.'
}
