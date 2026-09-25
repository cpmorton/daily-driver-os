#Requires -Version 5.1
<#
.SYNOPSIS
  Set this machine's daily-driver-os defaults, from Windows, before installing.

.DESCRIPTION
  Writes \EFI\daily-driver\defaults.json on this machine's EFI system partition,
  which Windows and Linux share in a dual boot. First boot on Linux reads it and
  offers each value on the console, where Enter accepts it or you type another:

    hostname, localadmin's password hash, how the encrypted disk unlocks
    (tpm2, tpm2-pin, fido2, passphrase), the daily users (name, full name,
    UID, shell, home size, must-change-password), extra Flatpaks.

  Never any user's password: each is typed at first boot. The file holds
  localadmin's password *hash*, readable by anyone who can read this disk, so
  use a strong password. Reinstalling Linux leaves the file in place; run the
  script again to change it, or -Delete to remove it.

  Run in an elevated PowerShell (Run as administrator); Windows only lets
  administrators mount the EFI partition. Runs on Windows PowerShell 5.1.

.EXAMPLE
  # Machine values; asks for localadmin's password and stores only its hash.
  .\Set-DailyDriverDefaults.ps1 -Hostname lap-01 -SetLocalAdminPassword -DiskUnlock tpm2-pin

.EXAMPLE
  # Add or update a daily user; run once per user.
  .\Set-DailyDriverDefaults.ps1 -User chris -RealName 'Chris' -Uid 60101 -Shell /bin/zsh -HomeSizeGB 200

.EXAMPLE
  .\Set-DailyDriverDefaults.ps1 -AddFlatpak org.gnome.Boxes
  .\Set-DailyDriverDefaults.ps1            # show what's set

.NOTES
  If Windows blocks the script: powershell -ExecutionPolicy Bypass -File .\Set-DailyDriverDefaults.ps1 ...
  Details: docs/runbooks/machine-defaults.md in the daily-driver-os repository.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$', Options = 'None')]
    [string] $Hostname,

    # Ask for localadmin's password here and store its SHA-512 crypt hash.
    [switch] $SetLocalAdminPassword,

    # Or give a hash yourself, e.g. copied from /etc/shadow ($y$... or $6$...).
    [ValidatePattern('^\$(y|6)\$[^:\s]+$', Options = 'None')]
    [string] $LocalAdminHash,

    # Remove localadmin's hash: first boot then asks for the password.
    [switch] $ClearLocalAdminPassword,

    [ValidateSet('tpm2', 'tpm2-pin', 'fido2', 'passphrase')]
    [string] $DiskUnlock,

    # Add or update one daily user.
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$', Options = 'None')]
    [string] $User,
    [ValidatePattern('^[^:\r\n]*$', Options = 'None')]
    [string] $RealName,
    [ValidateRange(60001, 60513)]
    [int] $Uid,
    [ValidatePattern('^/[A-Za-z0-9/._+-]+$', Options = 'None')]
    [string] $Shell,
    [ValidateRange(10, 4096)]
    [int] $HomeSizeGB,
    # Someone else types this user's first password; they must change it.
    [switch] $MustChangePassword,

    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$', Options = 'None')]
    [string] $RemoveUser,

    [ValidatePattern('^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$', Options = 'None')]
    [string[]] $AddFlatpak,
    [string[]] $RemoveFlatpak,

    # Remove the defaults file altogether.
    [switch] $Delete,

    # Only print a hash for the password you type (nothing is written).
    [switch] $PrintHash,

    # Write under this folder instead of the EFI partition (testing).
    [string] $Path,

    # Hash parameters; the defaults are right for real use.
    [ValidatePattern('^[./0-9A-Za-z]{1,16}$', Options = 'None')]
    [string] $Salt,
    [ValidateRange(1000, 9999999)]
    [int] $Rounds = 500000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --- SHA-512 crypt (glibc/libxcrypt "$6$"), per Ulrich Drepper's specification --
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

public static class DailyDriverSha512Crypt
{
    const string Itoa64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    static byte[] Sha(params byte[][] parts)
    {
        using (SHA512 sha = SHA512.Create())
        using (MemoryStream ms = new MemoryStream())
        {
            foreach (byte[] p in parts) ms.Write(p, 0, p.Length);
            return sha.ComputeHash(ms.ToArray());
        }
    }

    // The first n bytes of block repeated as often as needed.
    static byte[] Stretch(byte[] block, int n)
    {
        byte[] r = new byte[n];
        for (int i = 0; i < n; i++) r[i] = block[i % block.Length];
        return r;
    }

    public static string Hash(string password, string salt, int rounds)
    {
        byte[] p = Encoding.UTF8.GetBytes(password);
        byte[] s = Encoding.ASCII.GetBytes(salt);

        byte[] b = Sha(p, s, p);
        MemoryStream a = new MemoryStream();
        a.Write(p, 0, p.Length);
        a.Write(s, 0, s.Length);
        byte[] bs = Stretch(b, p.Length);
        a.Write(bs, 0, bs.Length);
        for (int len = p.Length; len > 0; len >>= 1)
        {
            if ((len & 1) != 0) a.Write(b, 0, b.Length); else a.Write(p, 0, p.Length);
        }
        byte[] digest = Sha(a.ToArray());

        MemoryStream dp = new MemoryStream();
        for (int i = 0; i < p.Length; i++) dp.Write(p, 0, p.Length);
        byte[] pSeq = Stretch(Sha(dp.ToArray()), p.Length);

        MemoryStream ds = new MemoryStream();
        for (int i = 0; i < 16 + digest[0]; i++) ds.Write(s, 0, s.Length);
        byte[] sSeq = Stretch(Sha(ds.ToArray()), s.Length);

        using (SHA512 sha = SHA512.Create())
        {
            for (int i = 0; i < rounds; i++)
            {
                MemoryStream c = new MemoryStream();
                if ((i & 1) != 0) c.Write(pSeq, 0, pSeq.Length); else c.Write(digest, 0, digest.Length);
                if (i % 3 != 0) c.Write(sSeq, 0, sSeq.Length);
                if (i % 7 != 0) c.Write(pSeq, 0, pSeq.Length);
                if ((i & 1) != 0) c.Write(digest, 0, digest.Length); else c.Write(pSeq, 0, pSeq.Length);
                digest = sha.ComputeHash(c.ToArray());
            }
        }

        StringBuilder o = new StringBuilder("$6$");
        if (rounds != 5000) o.Append("rounds=").Append(rounds).Append('$');
        o.Append(salt).Append('$');
        for (int k = 0; k < 21; k++)
        {
            int x = k, y = k + 21, z = k + 42;
            int[] t = (k % 3 == 0) ? new int[] { x, y, z } : (k % 3 == 1) ? new int[] { y, z, x } : new int[] { z, x, y };
            Encode(o, digest[t[0]], digest[t[1]], digest[t[2]], 4);
        }
        Encode(o, 0, 0, digest[63], 2);
        return o.ToString();
    }

    static void Encode(StringBuilder o, int b2, int b1, int b0, int n)
    {
        int w = (b2 << 16) | (b1 << 8) | b0;
        for (int i = 0; i < n; i++) { o.Append(Itoa64[w & 0x3f]); w >>= 6; }
    }

    public static string NewSalt()
    {
        byte[] r = new byte[16];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(r);
        StringBuilder sb = new StringBuilder();
        foreach (byte x in r) sb.Append(Itoa64[x & 0x3f]);
        return sb.ToString();
    }
}
'@

function Read-NewPassword([string] $Prompt) {
    while ($true) {
        $a = Read-Host -AsSecureString $Prompt
        $b = Read-Host -AsSecureString 'Repeat it'
        $pa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $pb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
        if ($pa -ne $pb) { Write-Warning 'They differ; try again.'; continue }
        if ($pa.Length -lt 12) { Write-Warning 'Use at least 12 characters: the hash is readable by anyone with this disk.'; continue }
        return $pa
    }
}

function New-PasswordHash {
    $plain = Read-NewPassword "Password for localadmin"
    $s = if ($Salt) { $Salt } else { [DailyDriverSha512Crypt]::NewSalt() }
    $hash = [DailyDriverSha512Crypt]::Hash($plain, $s, $Rounds)
    Remove-Variable plain
    return $hash
}

if ($PrintHash) {
    New-PasswordHash
    return
}

function Write-JsonFile([string] $File, $Object) {
    # UTF-8 without BOM, LF line endings: read by jq on Linux.
    $json = (ConvertTo-Json -InputObject $Object -Depth 6) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($File, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Get-Prop($Object, [string] $Name) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

$changing = $Hostname -or $SetLocalAdminPassword -or $LocalAdminHash -or $ClearLocalAdminPassword -or
    $DiskUnlock -or $User -or $RemoveUser -or $AddFlatpak -or $RemoveFlatpak -or $Delete
if ($SetLocalAdminPassword -and $LocalAdminHash) { throw 'Use -SetLocalAdminPassword or -LocalAdminHash, not both.' }
if ($User -eq 'localadmin' -or $RemoveUser -eq 'localadmin') { throw 'localadmin is not a daily user.' }
if (-not $User -and ($RealName -or $Uid -or $Shell -or $HomeSizeGB -or $MustChangePassword)) {
    throw '-RealName, -Uid, -Shell, -HomeSizeGB and -MustChangePassword need -User.'
}
foreach ($id in @($RemoveFlatpak)) {
    if ($id -and $id -cnotmatch '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2,}$') { throw "Not a Flatpak ID: $id" }
}

# --- Reach the EFI partition ---------------------------------------------------
$letter = $null
if ($Path) {
    $root = $Path
} else {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) { throw 'Run this in PowerShell opened with "Run as administrator".' }
    $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.ToUpper() })
    $letter = [char[]]'SRQPONMLKJIHGFEDTUVWXYZ' | Where-Object { $used -notcontains [string]$_ } | Select-Object -First 1
    if (-not $letter) { throw 'No free drive letter to mount the EFI partition on.' }
    & mountvol.exe "${letter}:" /S
    if ($LASTEXITCODE -ne 0) { throw "mountvol couldn't mount the EFI partition (is this a UEFI install of Windows?)." }
    $root = "${letter}:\"
}

try {
    $dir = [System.IO.Path]::Combine($root, 'EFI', 'daily-driver')
    $file = [System.IO.Path]::Combine($dir, 'defaults.json')

    if ($Delete) {
        if (Test-Path $file) { Remove-Item -Force $file; Write-Host "Deleted $file." }
        else { Write-Host 'No defaults file to delete.' }
        return
    }

    # --- Load, change, save --------------------------------------------------
    $old = $null
    # Windows PowerShell 5.1 reads BOM-less files as ANSI; this file is UTF-8.
    if (Test-Path $file) { $old = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }

    $config = [ordered]@{ version = 1 }
    foreach ($k in 'hostname', 'diskUnlock') { $v = Get-Prop $old $k; if ($null -ne $v) { $config[$k] = $v } }
    $oldHash = Get-Prop (Get-Prop $old 'localadmin') 'hashedPassword'
    if ($oldHash) { $config.localadmin = [ordered]@{ hashedPassword = $oldHash } }
    $users = New-Object System.Collections.ArrayList
    foreach ($u in @(Get-Prop $old 'users')) {
        if ($null -eq $u) { continue }
        $entry = [ordered]@{ userName = $u.userName }
        foreach ($k in 'realName', 'uid', 'shell', 'diskSize', 'passwordChangeNow') {
            $v = Get-Prop $u $k; if ($null -ne $v) { $entry[$k] = $v }
        }
        [void]$users.Add($entry)
    }
    $flatpaks = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-Prop $old 'flatpaks')) { if ($f) { [void]$flatpaks.Add([string]$f) } }

    if ($Hostname) { $config.hostname = $Hostname }
    if ($DiskUnlock) { $config.diskUnlock = $DiskUnlock }
    if ($ClearLocalAdminPassword) { $config.Remove('localadmin') }
    if ($LocalAdminHash) { $config.localadmin = [ordered]@{ hashedPassword = $LocalAdminHash.Trim() } }
    if ($SetLocalAdminPassword) { $config.localadmin = [ordered]@{ hashedPassword = (New-PasswordHash) } }

    if ($RemoveUser) {
        $users = [System.Collections.ArrayList]@($users | Where-Object { $_.userName -ne $RemoveUser })
    }
    if ($User) {
        $entry = $users | Where-Object { $_.userName -eq $User } | Select-Object -First 1
        if (-not $entry) { $entry = [ordered]@{ userName = $User }; [void]$users.Add($entry) }
        if ($RealName) { $entry.realName = $RealName }
        if ($Uid) {
            $clash = $users | Where-Object { $_.userName -ne $User -and $_.Contains('uid') -and $_.uid -eq $Uid }
            if ($clash) { throw "UID $Uid already belongs to $($clash.userName)." }
            $entry.uid = $Uid
        }
        if ($Shell) { $entry.shell = $Shell }
        if ($HomeSizeGB) { $entry.diskSize = [int64]$HomeSizeGB * 1GB }
        if ($PSBoundParameters.ContainsKey('MustChangePassword')) { $entry.passwordChangeNow = [bool]$MustChangePassword }
    }
    foreach ($f in @($AddFlatpak)) { if ($f -and -not $flatpaks.Contains($f)) { [void]$flatpaks.Add($f) } }
    foreach ($f in @($RemoveFlatpak)) { if ($f) { $flatpaks.Remove($f) } }

    $config.users = [object[]]$users.ToArray()
    $config.flatpaks = [object[]]$flatpaks.ToArray()

    if ($changing) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Write-JsonFile $file $config
    }

    # --- Summary -------------------------------------------------------------
    Write-Host ''
    if (-not (Test-Path $file)) { Write-Host 'No defaults set on this machine yet.'; return }
    $h = if ($config.Contains('hostname')) { $config.hostname } else { '(asked at first boot)' }
    $l = if ($config.Contains('localadmin')) { 'hash stored (' + $config.localadmin.hashedPassword.Substring(0, 3) + '...)' } else { '(asked at first boot)' }
    $d = if ($config.Contains('diskUnlock')) { $config.diskUnlock } else { '(asked at first boot)' }
    Write-Host "Defaults in $file"
    Write-Host "  hostname:             $h"
    Write-Host "  localadmin password:  $l"
    Write-Host "  disk unlock:          $d"
    if ($users.Count) {
        foreach ($u in $users) {
            $bits = @()
            if ($u.Contains('realName')) { $bits += $u.realName }
            if ($u.Contains('uid')) { $bits += "UID $($u.uid)" }
            if ($u.Contains('shell')) { $bits += $u.shell }
            if ($u.Contains('diskSize')) { $bits += "$([int64]$u.diskSize / 1GB) GB" }
            if ($u.Contains('passwordChangeNow') -and $u.passwordChangeNow) { $bits += 'must change password' }
            Write-Host "  user:                 $($u.userName)  $($bits -join ', ')"
        }
    } else { Write-Host '  users:                (asked at first boot)' }
    if ($flatpaks.Count) { Write-Host "  extra Flatpaks:       $($flatpaks -join ', ')" }
    Write-Host ''
    Write-Host 'Every user password is typed at first boot. Reinstalling Linux keeps this file.'
} finally {
    if ($letter) { & mountvol.exe "${letter}:" /D | Out-Null }
}
