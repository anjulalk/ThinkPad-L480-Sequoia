<#
.SYNOPSIS  Toggle AX210 Wi-Fi mode in EFI/OC/config.plist
.EXAMPLE   .\Switch-WiFiMode.ps1 -Mode Airport   # native menu (default)
.EXAMPLE   .\Switch-WiFiMode.ps1 -Mode HeliPort  # itlwm + HeliPort app
#>
param([ValidateSet('Airport','HeliPort')][string]$Mode = 'Airport')
$ErrorActionPreference = 'Stop'
$Plist = Join-Path (Split-Path -Parent $PSScriptRoot) 'EFI\OC\config.plist'
python3 -c "
import plistlib
p = r'$Plist'
cfg = plistlib.load(open(p,'rb'))
want_airport = ('$Mode' == 'Airport')
for k in cfg['Kernel']['Add']:
    if k['BundlePath'] == 'AirportItlwm.kext': k['Enabled'] = want_airport
    if k['BundlePath'] == 'itlwm.kext':        k['Enabled'] = (not want_airport)
plistlib.dump(cfg, open(p,'wb'))
print('Mode set to: $Mode')
print('  AirportItlwm enabled:', want_airport)
print('  itlwm enabled:       ', (not want_airport))
"
if ($Mode -eq 'HeliPort') {
  Write-Host ""
  Write-Host "HeliPort mode: after installing macOS, install the HeliPort app"
  Write-Host "(see HeliPort-installer file saved by Download-Prereqs.ps1)."
  Write-Host "Wi-Fi will appear as Ethernet (en0) -- this is normal for itlwm."
} else {
  Write-Host ""
  Write-Host "Airport mode: Wi-Fi appears in the native macOS Wi-Fi menu. No extra app needed."
}
Write-Host "Reset NVRAM at the OpenCore picker (Space -> Clear NVRAM) after switching."
