<#
.SYNOPSIS  Generate fresh MacBookPro15,2 SMBIOS values into EFI/OC/config.plist
.DESCRIPTION
  Uses macserial (fetched by Tools\Download-Sequoia.ps1 into Downloads-prereqs).
  NEVER boot with someone else's serials, and never share yours.
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Plist = Join-Path $RepoRoot 'EFI\OC\config.plist'

$macserial = Get-ChildItem -Path (Join-Path $RepoRoot 'Downloads-prereqs') -Recurse -Include 'macserial*.exe' |
  Where-Object { $_.Name -like '*.exe' } | Select-Object -First 1
if (-not $macserial) { throw "macserial not found. Run Tools\Download-Sequoia.ps1 first." }

Write-Host "Using: $($macserial.FullName)"
$out = & $macserial.FullName -g -m MacBookPro15,2 -n 5 | Out-String
Write-Host $out
$first = ($out -split "`n" | Where-Object { $_ -match '^\s*[A-Z0-9]+\s*\|\s*[A-Z0-9]+' } | Select-Object -First 1)
if (-not $first) { throw "Could not parse macserial output. Paste values manually with OCAT/ProperTree." }
$serial = ($first -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })[0]
$mlb    = ($first -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })[1]
$uuid   = [guid]::NewGuid().ToString().ToUpper()
Write-Host "Selected: serial=$serial mlb=$mlb uuid=$uuid"

python3 -c "
import plistlib
p = r'$Plist'
cfg = plistlib.load(open(p,'rb'))
g = cfg['PlatformInfo']['Generic']
g['SystemSerialNumber'] = '$serial'
g['MLB'] = '$mlb'
g['SystemUUID'] = '$uuid'
plistlib.dump(cfg, open(p,'wb'))
print('config.plist updated.')
"
Write-Host ""
Write-Host "SMBIOS written. Keep these private. Generate a NEW set if you ever share this EFI."
