<#
.SYNOPSIS
  Fetches OpenCore + all kexts/drivers referenced by EFI/OC/config.plist (Sequoia track).
  Small downloads only (~200MB). Does NOT download macOS (use gibMacOS/macRecovery, ~15GB).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File Tools\Download-Sequoia.ps1
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$DlDir    = Join-Path $RepoRoot 'Downloads-prereqs'
$KextDir  = Join-Path $RepoRoot 'EFI\OC\Kexts'
$DrvDir   = Join-Path $RepoRoot 'EFI\OC\Drivers'
$ToolDir  = Join-Path $RepoRoot 'EFI\OC\Tools'
New-Item -ItemType Directory -Force -Path $DlDir, $KextDir, $DrvDir, $ToolDir | Out-Null

function Pick-Asset($assets, [string[]]$NameMatch) {
  $cands = @()
  foreach ($a in $assets) {
    foreach ($m in $NameMatch) {
      if ($a.name -like $m) { $cands += $a; break }
    }
  }
  if (-not $cands) { return $null }
  $pick = ($cands | Where-Object { $_.name -like '*RELEASE*' } | Select-Object -First 1)
  if (-not $pick) { $pick = $cands[0] }
  return $pick
}

function Get-LatestAsset {
  param([string]$Repo, [string[]]$NameMatch, [string]$OutDir)
  $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
  $pick = Pick-Asset $rel.assets $NameMatch
  if (-not $pick) { throw "No asset matching ($($NameMatch -join ',')) in $Repo latest release ($($rel.tag_name))." }
  $dest = Join-Path $OutDir $pick.name
  if (-not (Test-Path $dest)) {
    Write-Host "  downloading $($pick.name) ..."
    Invoke-WebRequest -Uri $pick.browser_download_url -OutFile $dest
  } else { Write-Host "  cached $($pick.name)" }
  return $dest
}

function Get-PrereleaseAsset {
  param([string]$Repo, [string[]]$NameMatch, [string]$OutDir)
  $rels = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=5"
  foreach ($rel in $rels) {
    $pick = Pick-Asset $rel.assets $NameMatch
    if ($pick) {
      $dest = Join-Path $OutDir $pick.name
      if (-not (Test-Path $dest)) {
        Write-Host "  downloading $($pick.name) [pre-release $($rel.tag_name)] ..."
        Invoke-WebRequest -Uri $pick.browser_download_url -OutFile $dest
      } else { Write-Host "  cached $($pick.name)" }
      return $dest
    }
  }
  throw "No asset matching ($($NameMatch -join ',')) in $Repo recent releases (incl. pre-releases)."
}

function Expand-Zip($Zip, $Dest) {
  $d = Join-Path $DlDir $Dest
  if (Test-Path $d) { Write-Host "  already extracted: $Dest"; return $d }
  Write-Host "  extracting $(Split-Path $Zip -Leaf) ..."
  Expand-Archive -Path $Zip -DestinationPath $d
  return $d
}

function Copy-Kext($SrcDir, $KextName, $DestDir = $KextDir) {
  $found = Get-ChildItem -Path $SrcDir -Directory -Recurse -Filter $KextName | Select-Object -First 1
  if (-not $found) { throw "Kext $KextName not found under $SrcDir" }
  $dest = Join-Path $DestDir $KextName
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Copy-Item -Recurse -Force $found.FullName $dest
  Write-Host "  installed $KextName"
}

Write-Host "== 1. OpenCore =="
$ocZip = Get-LatestAsset 'acidanthera/OpenCorePkg' @('OpenCore-*-RELEASE.zip') $DlDir
$ocDir = Expand-Zip $ocZip 'OpenCorePkg'
$ocRoot = Get-ChildItem $ocDir -Directory -Recurse -Filter 'X64' |
  Where-Object { Test-Path (Join-Path $_.FullName 'EFI\OC\OpenCore.efi') } |
  Select-Object -First 1
if (-not $ocRoot) { throw "X64 EFI tree not found under $ocDir" }
$ocRoot = $ocRoot.Parent
$bootDest = Join-Path $RepoRoot 'EFI\BOOT'
New-Item -ItemType Directory -Force -Path $bootDest | Out-Null
Copy-Item -Recurse -Force (Join-Path $ocRoot.FullName 'X64\EFI\BOOT\*') $bootDest
Copy-Item -Force (Join-Path $ocRoot.FullName 'X64\EFI\OC\OpenCore.efi') (Join-Path $RepoRoot 'EFI\OC\OpenCore.efi')
foreach ($f in 'OpenRuntime.efi','OpenCanopy.efi','AudioDxe.efi') {
  Copy-Item -Force (Join-Path $ocRoot.FullName "X64\EFI\OC\Drivers\$f") (Join-Path $DrvDir $f)
}
foreach ($f in 'OpenShell.efi','CleanNvram.efi','ResetSystem.efi') {
  Copy-Item -Force (Join-Path $ocRoot.FullName "X64\EFI\OC\Tools\$f") (Join-Path $ToolDir $f)
}
$ocUtil = Join-Path $DlDir 'OC-Utilities'
New-Item -ItemType Directory -Force -Path $ocUtil | Out-Null
Copy-Item -Recurse -Force (Join-Path $ocRoot.FullName 'Utilities') $ocUtil -ErrorAction SilentlyContinue
Write-Host "OpenCore core files installed."

Write-Host "== 2. HfsPlus.efi =="
$hfs = Join-Path $DrvDir 'HfsPlus.efi'
if (-not (Test-Path $hfs)) {
  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/acidanthera/OcBinaryData/master/Drivers/HfsPlus.efi' -OutFile $hfs
}
Write-Host "  installed HfsPlus.efi"

Write-Host "== 3. Kexts =="
$kextJobs = @(
  @{ Repo='acidanthera/Lilu';                Match=@('Lilu-*.zip');                 Kext='Lilu.kext' },
  @{ Repo='acidanthera/VirtualSMC';          Match=@('VirtualSMC-*.zip');           Kext='VirtualSMC.kext','SMCBatteryManager.kext','SMCProcessor.kext','SMCSuperIO.kext' },
  @{ Repo='acidanthera/WhateverGreen';       Match=@('WhateverGreen-*.zip');       Kext='WhateverGreen.kext' },
  @{ Repo='acidanthera/AppleALC';            Match=@('AppleALC-*.zip');            Kext='AppleALC.kext' },
  @{ Repo='acidanthera/NVMeFix';             Match=@('NVMeFix-*.zip');             Kext='NVMeFix.kext' },
  @{ Repo='acidanthera/HibernationFixup';    Match=@('HibernationFixup-*.zip');    Kext='HibernationFixup.kext' },
  @{ Repo='acidanthera/RTCMemoryFixup';      Match=@('RTCMemoryFixup-*.zip');      Kext='RTCMemoryFixup.kext' },
  @{ Repo='acidanthera/IntelMausi';          Match=@('IntelMausi-*.zip');          Kext='IntelMausi.kext' },
  @{ Repo='acidanthera/BrightnessKeys';      Match=@('BrightnessKeys-*.zip');      Kext='BrightnessKeys.kext' },
  @{ Repo='al3xtjames/NoTouchID';            Match=@('NoTouchID*.zip');            Kext='NoTouchID.kext' },
  @{ Repo='averycblack/ECEnabler';           Match=@('ECEnabler-*.zip','*.zip');   Kext='ECEnabler.kext' },
  @{ Repo='acidanthera/CPUFriend';           Match=@('CPUFriend-*.zip');           Kext='CPUFriend.kext' },
  @{ Repo='acidanthera/VoodooPS2';           Match=@('VoodooPS2Controller-*.zip'); Kext='VoodooPS2Controller.kext' },
  @{ Repo='VoodooSMBus/VoodooRMI';           Match=@('VoodooRMI-*-RELEASE.zip','VoodooRMI-*.zip'); Kext='VoodooRMI.kext','VoodooSMBus.kext' },
  @{ Repo='OpenIntelWireless/IntelBluetoothFirmware'; Match=@('IntelBluetoothFirmware-*.zip','IntelBluetooth-*.zip','*.zip'); Kext='IntelBluetoothFirmware.kext','IntelBTPatcher.kext' },
  @{ Repo='acidanthera/BrcmPatchRAM';        Match=@('BrcmPatchRAM-*.zip');        Kext='BlueToolFixup.kext' },
  @{ Repo='OpenIntelWireless/itlwm';         Match=@('itlwm_v2.3.0_stable.kext.zip','itlwm*.zip'); Kext='itlwm.kext' }
)
foreach ($j in $kextJobs) {
  Write-Host "-- $($j.Repo)"
  $zip = Get-LatestAsset $j.Repo $j.Match $DlDir
  $dir = Expand-Zip $zip ($j.Repo -replace '/','_')
  foreach ($k in $j.Kext) { Copy-Kext $dir $k }
}

Write-Host "-- AirportItlwm Sequoia (laobamac pre-release, experimental, ships DISABLED)"
$zip = Get-PrereleaseAsset 'laobamac/itlwm' @('AirportItlwm-Sequoia-*-RELEASE-*.zip') $DlDir
$dir = Expand-Zip $zip 'AirportItlwm-Sequoia'
Copy-Kext $dir 'AirportItlwm.kext'

Write-Host "-- HeliPort (required for default itlwm mode)"
try {
  $heli = Get-LatestAsset 'OpenIntelWireless/HeliPort' @('HeliPort*.dmg','HeliPort*.zip') $DlDir
  Copy-Item -Force $heli (Join-Path $RepoRoot 'HeliPort-installer.bin')
} catch { Write-Host "  WARNING: HeliPort fetch failed: $_" }

Write-Host ""
Write-Host "== 4. Verify against config.plist =="
python3 -c "
import plistlib, os, sys
base = r'$RepoRoot\EFI\OC'
cfg = plistlib.load(open(os.path.join(base,'config.plist'),'rb'))
ok = True
for k in cfg['Kernel']['Add']:
    if not k['Enabled']: continue
    p = os.path.join(base,'Kexts',k['BundlePath'].replace('/','\\\\'))
    if not os.path.isdir(p): print('MISSING DIR:', k['BundlePath']); ok=False
    elif not os.path.exists(os.path.join(p,'Contents','Info.plist')): print('MISSING Info.plist:', k['BundlePath']); ok=False
for e in cfg['ACPI']['Add']:
    if e['Enabled'] and not os.path.exists(os.path.join(base,'ACPI',e['Path'])): print('MISSING AML:', e['Path']); ok=False
for d in cfg['UEFI']['Drivers']:
    if d['Enabled'] and not os.path.exists(os.path.join(base,'Drivers',d['Path'])): print('MISSING DRIVER:', d['Path']); ok=False
print('ALL PRESENT' if ok else 'GAPS FOUND -- see above')
sys.exit(0 if ok else 1)
"
Write-Host ""
Write-Host "Done. Next: Tools\Generate-SMBIOS.ps1, then build the USB (see README)."
