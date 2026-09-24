#Requires -Version 5.1
<#
.SYNOPSIS
  Write a DDSEED provisioning stick for a daily-driver-os install, on Windows.

.DESCRIPTION
  The installer ISO is generic and public. This writes the machine- and
  person-specific part to a separate FAT32/exFAT volume labelled DDSEED, which
  the installed system imports once, at first boot, and then deletes:

    daily-driver-seed\seed.json          hostname
    daily-driver-seed\users\<name>.json  one daily user: name, full name, home size
    daily-driver-seed\skel\<name>\...    optional files for that user's home

  Run it once per machine with -Hostname, and once per daily user with -User.
  Runs on Windows PowerShell 5.1; nothing to install.

  No passwords go on the stick. At first boot the console asks for
  localadmin's password, then each user's (docs/decisions/0019).

.EXAMPLE
  # Once: format the stick and set the machine-wide values.
  .\New-DailyDriverSeed.ps1 -Drive E: -Format -Hostname chris-laptop

.EXAMPLE
  # Then one run per daily user.
  .\New-DailyDriverSeed.ps1 -Drive E: -User chris -RealName 'Chris' -HomeSizeGB 200 `
      -SkelPath C:\seed\chris

.NOTES
  If Windows blocks the script: powershell -ExecutionPolicy Bypass -File .\New-DailyDriverSeed.ps1 ...
  Format and every field: docs/runbooks/seed-stick.md in the daily-driver-os repository.
#>
[CmdletBinding(DefaultParameterSetName = 'Drive')]
param(
    # Drive letter of the seed stick, such as E:
    [Parameter(ParameterSetName = 'Drive', Mandatory = $true)]
    [ValidatePattern('^[A-Za-z]:?$')]
    [string] $Drive,

    # Or any folder (testing, or a partition mounted elsewhere).
    [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
    [string] $Path,

    # Erase the drive and format it exFAT, labelled DDSEED.
    [Parameter(ParameterSetName = 'Drive')]
    [switch] $Format,

    [ValidatePattern('^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')]
    [string] $Hostname,

    # Folder copied into localadmin's home.
    [string] $LocalAdminSkelPath,

    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [string] $User,

    [string] $RealName,

    [ValidateRange(10, 4096)]
    [int] $HomeSizeGB = 100,

    # Folder copied into the user's new encrypted home.
    [string] $SkelPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Label = 'DDSEED'

function Write-JsonFile([string] $File, $Object) {
    # UTF-8 without BOM, LF line endings: read by jq on Linux.
    $json = ($Object | ConvertTo-Json -Depth 6) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($File, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}

if (-not $Hostname -and -not $LocalAdminSkelPath -and -not $User) {
    throw 'Nothing to do: give -Hostname for the machine, and/or -User for a daily user.'
}
if ($User -eq 'localadmin') { throw 'localadmin is not a daily user; its files go in -LocalAdminSkelPath.' }

# --- Find (or make) the seed volume ------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Drive') {
    $letter = $Drive.Substring(0, 1).ToUpper()
    if ($Format) {
        Write-Warning "Erasing drive ${letter}: and formatting it as $Label."
        $confirm = Read-Host "Type the drive letter ($letter) to confirm"
        if ($confirm.ToUpper() -ne $letter) { throw 'Not confirmed; nothing changed.' }
        Format-Volume -DriveLetter $letter -FileSystem exFAT -NewFileSystemLabel $Label -Confirm:$false | Out-Null
    }
    $volume = Get-Volume -DriveLetter $letter
    if ($volume.FileSystemLabel -ne $Label) {
        throw "Drive ${letter}: is labelled '$($volume.FileSystemLabel)', not $Label. Use -Format, or relabel it."
    }
    $root = "${letter}:\"
} else {
    $root = $Path
}

$seed = [System.IO.Path]::Combine($root, 'daily-driver-seed')
$users = [System.IO.Path]::Combine($seed, 'users')
$skel = [System.IO.Path]::Combine($seed, 'skel')
New-Item -ItemType Directory -Force -Path $seed, $users, $skel | Out-Null

# --- Machine-wide values -------------------------------------------------------
$configFile = [System.IO.Path]::Combine($seed, 'seed.json')
$config = [ordered]@{ version = 1 }
if (Test-Path $configFile) {
    $existing = Get-Content -Raw -Path $configFile | ConvertFrom-Json
    if ($existing.PSObject.Properties['hostname']) { $config.hostname = $existing.hostname }
    # A stick made by an older version of this script may hold a password hash.
    if ($existing.PSObject.Properties['localadmin']) {
        Write-Warning 'Removing the localadmin password hash an older version of this script wrote.'
        Write-JsonFile $configFile $config
    }
}
if ($Hostname) {
    $config.hostname = $Hostname
    Write-JsonFile $configFile $config
}

# Same for user records holding a plaintext initial password: keep only the
# fields first boot reads.
foreach ($file in @(Get-ChildItem -Path $users -Filter *.json)) {
    $old = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
    if ($old.PSObject.Properties['secret']) {
        Write-Warning "Removing the stored password from $($file.Name)."
        $clean = [ordered]@{ userName = $old.userName }
        if ($old.PSObject.Properties['realName']) { $clean.realName = $old.realName }
        if ($old.PSObject.Properties['diskSize']) { $clean.diskSize = [int64]$old.diskSize }
        Write-JsonFile $file.FullName $clean
    }
}

if ($LocalAdminSkelPath) {
    $dest = [System.IO.Path]::Combine($skel, 'localadmin')
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force -Path (Join-Path $LocalAdminSkelPath '*') -Destination $dest
}

# --- One daily user ---------------------------------------------------------
if ($User) {
    $record = [ordered]@{
        userName = $User
        realName = $(if ($RealName) { $RealName } else { $User })
        diskSize = [int64]$HomeSizeGB * 1GB
    }
    Write-JsonFile ([System.IO.Path]::Combine($users, "$User.json")) $record
    if ($SkelPath) {
        $dest = [System.IO.Path]::Combine($skel, $User)
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Recurse -Force -Path (Join-Path $SkelPath '*') -Destination $dest
    }
}

# --- Summary -------------------------------------------------------------------
Write-Host ''
Write-Host "Seed on ${root}:"
if (Test-Path $configFile) {
    $c = Get-Content -Raw $configFile | ConvertFrom-Json
    $h = if ($c.PSObject.Properties['hostname']) { $c.hostname } else { '(installer default)' }
    Write-Host "  hostname:     $h"
}
$names = @(Get-ChildItem -Path $users -Filter *.json | ForEach-Object { $_.BaseName })
if ($names.Count) { Write-Host "  daily users:  $($names -join ', ')" }
else { Write-Host '  daily users:  none; asked on screen at first boot' }
Write-Host ''
Write-Host 'Passwords are typed on screen at first boot, never stored here. First boot'
Write-Host 'imports this seed and deletes it; until then, guard any files in skel\.'
