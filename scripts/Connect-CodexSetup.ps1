[CmdletBinding()]
param(
    [string] $CodexRoot = $(
        if ($env:CODEX_HOME) {
            $env:CODEX_HOME
        }
        else {
            Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
        }
    ),

    [string] $PersonalSkillsPath = $(
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

function Connect-Junction {
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Junction source does not exist: $Source"
    }

    $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        $target = @($existing.Target)[0]
        if ($existing.LinkType -eq 'Junction' -and
            $target -and
            [System.IO.Path]::GetFullPath($target).TrimEnd('\') -ieq
                [System.IO.Path]::GetFullPath($Source).TrimEnd('\')) {
            Write-Host "Already connected: $Destination -> $Source"
            return
        }

        throw "Path already exists and is not the expected junction: $Destination"
    }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    New-Item -ItemType Junction -Path $Destination -Target $Source | Out-Null
    Write-Host "Connected: $Destination -> $Source"
}

Connect-Junction `
    -Source (Join-Path $repositoryRoot 'skills') `
    -Destination $PersonalSkillsPath

Connect-Junction `
    -Source (Join-Path $repositoryRoot 'agents') `
    -Destination (Join-Path $CodexRoot 'agents')
