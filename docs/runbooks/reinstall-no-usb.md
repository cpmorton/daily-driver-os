# Install without a USB stick

A first-class alternative to the installer stick in
[reinstall.md](reinstall.md): carry the installer on the disk itself. Windows
preparation, the installer screens and first boot are unchanged — this replaces
only "write and boot a USB stick". Parts are marked **[VERIFY]**: reasoned from
source, not yet proven on hardware.

## The idea

Carve an 8 GiB FAT32 partition out of the free space you made, copy the
installer ISO's *contents* onto it, and rename the volume label in `grub.cfg`
so the installer looks for that partition instead of the DVD. Boot
`\EFI\BOOT\BOOTX64.EFI` on it once; Anaconda installs into the remaining free
space and leaves the installer partition alone. Keep it afterwards and you have
a reinstall partition that never gets lost in a drawer.

### Why this works (checked in source, not yet on hardware)

| Question | Answer | Evidence |
| --- | --- | --- |
| How does the ISO find its files? | By volume label, in two places: GRUB `search --no-floppy --set=root -l '<label>'`, and the kernel arguments `inst.stage2=hd:LABEL=<label>` and `inst.ks=hd:LABEL=<label>:/osbuild.ks` | osbuild `stages/org.osbuild.grub2.iso`; osbuild/images `pkg/image/anaconda_container_installer_legacy.go` |
| What label? | `Fedora-S-dvd-x86_64-44` (this image keeps `ID=fedora`). Too long for FAT32's 11 characters, so we rename it rather than match it. The script reads the real label from the ISO, so a wrong guess costs nothing | images `pkg/distro/bootc/shared.go:LabelForISO` |
| Any file over FAT32's 4 GiB limit? | No. The payload is an OCI layout in `/container`, one file per layer; the largest layer is well under 1 GiB | GHCR manifest for `:stable`; payload path `/container` in `anaconda_container_installer_legacy.go` |
| Will the installer refuse the disk its source is on? | No. With an `hd:` stage2 on a plain partition, Anaconda marks **only that partition** protected. The whole disk is protected only for iso9660, cdrom or live media | anaconda `pyanaconda/modules/storage/devicetree/model.py:_mark_protected_devices` |
| Graphical or text installer? | Graphical (the package set includes `anaconda` and `gnome-kiosk`, with no `inst.text`), so *Encrypt my data* exists as in the runbook | images `data/distrodefs/fedora/imagetypes.yaml` |

One trap found while reading: Anaconda's **text** installer pre-selects *Use All
Space*. The graphical one shouldn't put you there, but if you ever see a
text-mode installer, stop and choose *Use Free Space*.

## Before you start

1. **Build a fresh ISO.** Actions → *Build installer ISO* → Run workflow → tag
   `stable` (~15 min). Expired artifacts must be rebuilt.
2. **Have off the laptop:** the BitLocker recovery key (aka.ms/myrecoverykey)
   and a plan for the disk passphrase (password manager).
3. **Confirm the free space.** Disk Management should show an *Unallocated* bar
   of at least 108 GiB (100 for Linux, 8 for the installer). If you formatted
   it as a volume, delete **that volume only**; *Automatic* mode uses only
   unallocated space.

## Step 1. Prepare Windows (unchanged from the runbook)

Admin PowerShell — the same three commands as [reinstall.md](reinstall.md) § 1:

```powershell
manage-bde -status C:          # Protection On? save the recovery key first
powercfg /h off                # Fast Startup off: NTFS stays cleanly unmounted
reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
```

Optional, same window: `tools\windows\Set-DailyDriverDefaults.ps1` (machine
defaults on the EFI partition; see [machine-defaults.md](machine-defaults.md)).

## Step 2. Make the installer partition

Disk Management is safest here — you click the exact region:

1. Right-click the **Unallocated** region → *New Simple Volume*.
2. Size **8192** MB. Any free drive letter (this guide says `I:`).
3. File system **FAT32**, label **`DDINSTALL`**, quick format.

Leave the rest unallocated. Confirm nothing else moved:

```powershell
Get-Partition -DiskNumber (Get-Partition -DriveLetter C).DiskNumber |
  Format-Table PartitionNumber, DriveLetter, Type, @{n='GiB';e={[math]::Round($_.Size/1GB,1)}}
Get-Volume -DriveLetter I      # FileSystem FAT32, FileSystemLabel DDINSTALL
```

**Touches the disk:** creates one partition inside unallocated space. Windows'
partitions, the EFI partition and the boot entries are not modified.

## Step 3. Download and check the ISO

```powershell
cd $env:USERPROFILE\Downloads
(Get-FileHash .\daily-driver-os-stable.iso -Algorithm SHA256).Hash.ToLower()
Get-Content .\daily-driver-os-stable.iso.sha256      # first field must match
```

## Step 4. Copy the ISO onto the partition and relabel

Admin PowerShell. Read it first; it only writes to `I:`.

```powershell
$iso   = "$env:USERPROFILE\Downloads\daily-driver-os-stable.iso"
$dest  = 'I:\'
$label = 'DDINSTALL'

$vol = Mount-DiskImage -ImagePath $iso -PassThru | Get-Volume
$old = $vol.FileSystemLabel             # expect Fedora-S-dvd-x86_64-44
"ISO label: $old"

# Every file must fit FAT32; this should print nothing.
Get-ChildItem "$($vol.DriveLetter):\" -Recurse -File | Where-Object Length -ge 4GB

# /E: subdirectories including empty ones. Exit codes 0-7 are success.
robocopy "$($vol.DriveLetter):\" $dest /E /R:1 /W:1 /NFL /NDL /NP
if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }
Dismount-DiskImage -ImagePath $iso | Out-Null

# Files copied from an ISO arrive read-only.
attrib -r "$dest*" /s /d

# Point GRUB and Anaconda at the new label. -Encoding ascii avoids a BOM,
# which GRUB would read as garbage on the first line.
Get-ChildItem $dest -Recurse -Include *.cfg, *.conf | ForEach-Object {
  $t = Get-Content $_.FullName -Raw
  if ($t.Contains($old)) {
    $t.Replace($old, $label) | Set-Content $_.FullName -Encoding ascii -NoNewline
    "patched $($_.FullName)"
  }
}
Select-String -Path "${dest}EFI\BOOT\grub.cfg" -Pattern 'search|LABEL='
```

The last line should show `-l 'DDINSTALL'` and `hd:LABEL=DDINSTALL` and no trace
of the old label. **[VERIFY]** that `EFI\BOOT\grub.cfg` is the file patched; if
the patch list names a different path, that's fine as long as `Select-String`
over `I:\` finds no old label anywhere.

## Step 5. Boot the installer partition once

Secure Boot stays on: `BOOTX64.EFI` is Fedora's shim, signed by Microsoft's
third-party UEFI CA.

**Option A — firmware only (no changes to Windows):** reboot into the one-time
boot menu (usually F12; HP F9, ASUS F8/Esc) and pick *Boot from file* / *Boot
from EFI file*. Browse to `DDINSTALL` → `EFI` → `BOOT` → `BOOTX64.EFI`. Dell and
HP have this; many Lenovos don't. **[VERIFY]** on your model.

**Option B — a firmware boot entry made from Windows.** Use only if your
firmware has no *Boot from file*. **Touches firmware NVRAM and the BCD store**
(adds an entry; doesn't change `{bootmgr}` or the default). Copying `{bootmgr}`
for a non-Windows entry is an unsupported community technique. **[VERIFY]**

```powershell
bcdedit /export C:\bcd-backup-before-linux      # restore with: bcdedit /import
Suspend-BitLocker -MountPoint C: -RebootCount 3 # only if BitLocker is on
bcdedit /copy '{bootmgr}' /d "DD installer"     # prints a new {GUID}
$g = '{paste-the-GUID-here}'
bcdedit /set $g device partition=I:
bcdedit /set $g path \EFI\BOOT\BOOTX64.EFI
bcdedit /set '{fwbootmgr}' displayorder $g /addlast   # last: Windows stays default
bcdedit /enum firmware                                 # check it's listed
```

Then pick *DD installer* from the one-time boot menu, or from Windows:
Settings → System → Recovery → *Advanced startup* → *Use a device*.

## Step 6. Install

As in [reinstall.md](reinstall.md) § 4, with three things to watch:

1. **Installation Destination:** the internal disk, *Automatic*, tick **Encrypt
   my data**. The summary should say it will use the free space. If it offers to
   *reclaim* space, cancel — that dialog deletes partitions. `DDINSTALL` should
   appear protected or untouched.
2. **Create no user.** Root is already locked by the kickstart.
3. Anaconda puts shim and GRUB in `\EFI\fedora` on the **existing** EFI
   partition and adds a *Fedora* firmware entry ahead of Windows Boot Manager.
   Expected. Windows' own EFI files aren't modified.

**[VERIFY]**: a Windows-made 100 MB EFI partition has room
([decision 0017](../decisions/0017-dual-boot-internal-disk.md)). If Anaconda
complains about EFI partition size, stop and come back.

## Step 7. First boot, then tidy up

First boot is [first-boot.md](first-boot.md): disk passphrase, hostname,
localadmin, disk unlock method, users.

Afterwards:

- **Keep `DDINSTALL`.** To reinstall later, repeat steps 3–5 with a new ISO
  (wipe `I:\` first). It's public content, so leaving it unencrypted is fine.
  Hide it from Explorer if you like:
  `Remove-PartitionAccessPath -DriveLetter I -AccessPath I:\`.
- If you used option B: `bcdedit /delete '{GUID}'` once Linux boots on its own.

## Risks that touch Windows, in one place

| Risk | Where | Mitigation |
| --- | --- | --- |
| A partitioning option that deletes Windows | Step 6 | *Automatic* plus free space only; cancel any *reclaim* dialog; stop if a text installer offers *Use All Space* |
| BitLocker recovery prompt when Windows is started from **GRUB's** Windows entry | After install | Known Fedora issue: chainloading `bootmgfw.efi` from shim/GRUB changes the TPM measurements BitLocker sealed to. This repo's `windows-boot-entry` does that chainload. If it prompts, boot Windows from the firmware menu and note it for a decision record. **[VERIFY]** |
| NVRAM/BCD edits | Step 5 option B | `bcdedit /export` backup first; option A avoids it entirely |
| Shim refused with Secure Boot on | Step 5 | Secured-core laptops often ship with *Allow Microsoft 3rd-party UEFI CA* off. Turn that on in firmware rather than disabling Secure Boot. **[VERIFY]** |
| Windows updates resetting boot order | Ongoing | Firmware setup or the one-time menu ([decision 0017](../decisions/0017-dual-boot-internal-disk.md)) |
