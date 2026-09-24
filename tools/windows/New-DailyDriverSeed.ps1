#Requires -Version 5.1
<#
.SYNOPSIS
  Write a DDSEED provisioning stick for a daily-driver-os install, on Windows.

.DESCRIPTION
  The installer ISO is generic and public. This writes the machine- and
  person-specific part to a separate FAT32/exFAT volume labelled DDSEED, which
  the installed system imports once, at first boot, and then deletes:

    daily-driver-seed\seed.json          hostname, localadmin password hash
    daily-driver-seed\users\<name>.json  one encrypted-home user record each
    daily-driver-seed\skel\<name>\...    optional files for that user's home

  Run it once per machine with -Hostname and -LocalAdminHash, and once per
  daily user with -User. Runs on Windows PowerShell 5.1; nothing to install.

  The stick holds each user's initial password in plain text until first boot
  (systemd-homed needs it to create the encrypted home), so keep it with you.
  Users must change it at first login unless -NoPasswordChange is given.

.EXAMPLE
  # Once: format the stick and set the machine-wide values.
  .\New-DailyDriverSeed.ps1 -Drive E: -Format -Hostname chris-laptop `
      -LocalAdminHash (Get-Content .\localadmin.hash)

.EXAMPLE
  # Then one run per daily user; asks for the initial password.
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

    # yescrypt ($y$...) or SHA-512 ($6$...) crypt hash, from your secret store.
    [ValidatePattern('^\$(y|6)\$')]
    [string] $LocalAdminHash,

    # Folder copied into localadmin's home.
    [string] $LocalAdminSkelPath,

    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [string] $User,

    [string] $RealName,

    [ValidateRange(10, 4096)]
    [int] $HomeSizeGB = 100,

    # Folder copied into the user's new encrypted home.
    [string] $SkelPath,

    # Don't force a password change at first login.
    [switch] $NoPasswordChange
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Label = 'DDSEED'

function Write-JsonFile([string] $File, $Object) {
    # UTF-8 without BOM, LF line endings: read by jq on Linux.
    $json = ($Object | ConvertTo-Json -Depth 6) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($File, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Read-InitialPassword([string] $Name) {
    while ($true) {
        $a = Read-Host -AsSecureString "Initial password for $Name"
        $b = Read-Host -AsSecureString "Repeat it"
        $pa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $pb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
        if ($pa -ne $pb) { Write-Warning 'They differ; try again.'; continue }
        if ($pa.Length -lt 8) { Write-Warning 'Use at least 8 characters.'; continue }
        return $pa
    }
}

if (-not $Hostname -and -not $LocalAdminHash -and -not $LocalAdminSkelPath -and -not $User) {
    throw 'Nothing to do: give -Hostname/-LocalAdminHash for the machine, and/or -User for a daily user.'
}
if ($User -eq 'localadmin') { throw 'localadmin is set with -LocalAdminHash, not -User.' }

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
    if ($existing.PSObject.Properties['localadmin']) {
        $config.localadmin = [ordered]@{ hashedPassword = $existing.localadmin.hashedPassword }
    }
}
if ($Hostname) { $config.hostname = $Hostname }
if ($LocalAdminHash) { $config.localadmin = [ordered]@{ hashedPassword = $LocalAdminHash.Trim() } }
if ($Hostname -or $LocalAdminHash) { Write-JsonFile $configFile $config }

if ($LocalAdminSkelPath) {
    $dest = [System.IO.Path]::Combine($skel, 'localadmin')
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force -Path (Join-Path $LocalAdminSkelPath '*') -Destination $dest
}

# --- One daily user ---------------------------------------------------------
if ($User) {
    $password = Read-InitialPassword $User
    $record = [ordered]@{
        userName          = $User
        realName          = $(if ($RealName) { $RealName } else { $User })
        storage           = 'luks'
        diskSize          = [int64]$HomeSizeGB * 1GB
        passwordChangeNow = -not [bool]$NoPasswordChange
        secret            = [ordered]@{ password = @($password) }
    }
    Write-JsonFile ([System.IO.Path]::Combine($users, "$User.json")) $record
    Remove-Variable password
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
    $l = if ($c.PSObject.Properties['localadmin']) { 'from seed' } else { 'asked on screen at first boot' }
    Write-Host "  hostname:            $h"
    Write-Host "  localadmin password: $l"
}
$names = @(Get-ChildItem -Path $users -Filter *.json | ForEach-Object { $_.BaseName })
if ($names.Count) { Write-Host "  daily users:         $($names -join ', ')" }
else { Write-Host '  daily users:         none; asked on screen at first boot' }
Write-Host ''
Write-Host 'Keep this stick with you: it holds initial passwords in plain text until'
Write-Host 'first boot, which imports it and deletes them.'
