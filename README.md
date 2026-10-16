# ThinkPad L480 + Intel AX200/AX210 — macOS Sequoia Hackintosh (OpenCore)

OpenCore EFI for the **Lenovo ThinkPad L480** (i5-8250U / i5-8350U / i7-8550U,
Kaby Lake-R, UHD 620, Realtek ALC257) with an **Intel AX200 or AX210** Wi-Fi card,
targeting **macOS Sequoia 15**. SMBIOS `MacBookPro15,2`, OpenCore 1.0.x.
Also covers the **stock Intel 8265** card (see [Wireless options](#wireless-options)).

> **Status: experimental.** The sibling Sonoma build from the same baseline boots
> and installs cleanly on real L480 hardware; this Sequoia track is assembled from
> it with Sequoia-specific Wi-Fi handling but has **not yet completed a verified
> install**. Bluetooth is **broken / under investigation**. Details below — please
> report results (good or bad) as issues.

## Hardware covered

| Part | This repo assumes | Notes |
|---|---|---|
| CPU | i5-8250U (Kaby Lake-R; 8350U/8550U same family) | NOT Whiskey Lake, despite what some older guides say |
| GPU | Intel UHD 620 | Full accel via WhateverGreen on internal panel |
| Audio | Realtek ALC257 | `alcid=11` |
| Wi-Fi | **Intel AX210** (tested config); AX200 expected-compatible, untested | AX200/AX201/AX210/AX211 all use the same `iwx` driver family |
| Ethernet | Intel I219-LM/V | IntelMausi |
| Keyboard/TrackPad | PS2 + Synaptics RMI | VoodooPS2 + VoodooRMI stack |
| SSD | SATA/AHCI (e.g. SanDisk X400-class) | Samsung PM981/PM991 NVMe are known Hackintosh-killers — avoid |

## Wireless options

This EFI defaults to `itlwm.kext` + HeliPort (Mode B), which is card-agnostic —
it works identically for **AX210, AX200, and the stock Intel 8265**. Differences:

| Card | Wi-Fi on Sequoia | Bluetooth | Notes |
|---|---|---|---|
| AX210 (this repo's config) | itlwm+HeliPort ✅ (default) | ❌ Broken, under investigation (Gen3 firmware) | Native-menu path = experimental alpha, disabled |
| AX200 | itlwm+HeliPort ✅ expected | Likely working (mature Gen2 BT 5.0 firmware) — untested, please report | Same kexts, no config change |
| Stock 8265 | itlwm+HeliPort ✅ expected | Likely working (mature Gen2 BT 4.2 firmware) — untested, please report | Same kexts, no config change |

- **No AirportItlwm native-menu path exists on Sequoia for ANY Intel card** in a
  stable release — that's an Intel-wireless-on-Sequoia limitation, not this EFI.
  (The disabled alpha entry is AX210-tested; 8265/AX200 behavior with it is unknown.)
- The cosmetic `model` string under `DeviceProperties → PciRoot(0x0)/Pci(0x1D,0x2)/Pci(0x0,0x0)`
  says "Intel Wi-Fi 6E AX210" — 8265/AX200 users can rename it to match their card
  (Hackintool → PCIe will show the real hardware regardless; purely cosmetic).
- Bluetooth rides the same HS07 USB lane on all three cards — no USB map change needed.
- `IntelBTPatcher.kext` stays loaded for all cards: it only activates on Gen3
  firmware devices and is inert otherwise.

## What works / what doesn't (Sequoia track, honest edition)

| Feature | Status |
|---|---|
| Boot to installer / Recovery | Expected (same ACPI/device config as proven Sonoma build) |
| Internal display accel, HDMI | Expected |
| Battery %, sleep/wake, keyboard, brightness keys, audio, webcam, Ethernet | Expected (carried over, re-verify on Sequoia) |
| Wi-Fi via `itlwm.kext` + HeliPort (**default**) | Expected — shows as Ethernet (en0); simplest path to working iMessage/FaceTime |
| Wi-Fi via native menu (AirportItlwm) | **Experimental** — laobamac v2.4.0-alpha Sequoia build ships present-but-**disabled**; days old, for testing only |
| **Bluetooth (AX210)** | **BROKEN — under investigation** |
| AirDrop / Apple Watch unlock / Sidecar-over-Wi-Fi | Not available with Intel wireless, by design |
| Fingerprint reader | No macOS driver exists — permanently unsupported |

### Bluetooth investigation notes (for contributors)
Proven requirements already in this EFI, so the fault is elsewhere:
- Stack + order: `IntelBluetoothFirmware` → `IntelBTPatcher` (mandatory for Gen3 AX210
  on Monterey+, needs Lilu ≥ 1.6.2 — we ship 1.7.x) → `BlueToolFixup`. No `IntelBluetoothInjector` (breaks ≥Monterey).
- BT rides USB: must enumerate on **HS07 marked internal (255)** in our `USBPorts.kext`.
  Verify with Hackintool/USBToolBox — if the BT device isn't on HS07, fix the map first.
- NVRAM already contains `bluetoothExternalDongleFailed = 00` and zeroed
  `bluetoothInternalControllerInfo`.
- Debug path: `sudo dmesg | grep -i bluetooth`, check System Report → Bluetooth for
  firmware version, try multiple NVRAM resets, compare itlwm vs AirportItlwm mode,
  test newer `IntelBluetoothFirmware`/`BlueToolFixup` releases.

## BIOS (L480, from a real install)

Security tab: Execution Prevention **Enabled**, Intel Virtualization **Enabled**,
Intel VT-d **Enabled**, Secure Boot **Off**, Computrace **Off**.
Startup tab: **UEFI Only**, CSM **No**. Disable Thunderbolt, fingerprint reader if present.

Observed quirks (not typos):
- **DVMT Pre-Allocated offers only 256MB / 512MB — use 256MB.** 512MB panics the
  framebuffer init (~20% boot progress) with our `stolenmem` patch set. No 64MB option exists.
- **There is no SATA/AHCI mode setting** on this BIOS — nothing to change there.
- Firmware Secure Boot must be **Off** (OpenCore's loader is unsigned).
- Apple `SecureBootModel` is set to **`Disabled`** in this config: required to
  *install* anything newer than Sonoma 14.3 (leaving `Default` causes an installer-phase
  bootloop — verified on hardware). You may return it to `Default` once installed,
  but flip back to `Disabled` before any macOS update.

## Build the USB

You need: this repo, a 16GB+ USB stick, wired Ethernet for the L480 at install time
(AX210 Wi-Fi doesn't exist in Apple's recovery), and an unlimited-data window (~16GB).

1. **Binaries** (small, ~200MB, anytime):
   `powershell -ExecutionPolicy Bypass -File Tools\Download-Sequoia.ps1`
   Fetches OpenCore 1.0.x core, drivers, all kexts, HeliPort app, `ocvalidate`/`macserial`.
   Ends with a cross-check that every file `config.plist` references exists.
2. **Serials** (do NOT skip, do NOT share):
   `powershell -ExecutionPolicy Bypass -File Tools\Generate-SMBIOS.ps1`
3. **macOS** (BIG — unlimited window): with
   [gibMacOS](https://github.com/corpnewt/gibMacOS),
   download the Sequoia full installer, then build the stick with
   [macrecovery.py](https://dortania.github.io/OpenCore-Install-Guide/installer-guide/windows-install.html#downloading-macos)
   (genuine Apple recovery image) onto a FAT32 USB: create `com.apple.recovery.boot/`
   with the `.dmg` + `.chunklist`, copy this repo's `EFI/` to the USB root.
4. **Boot L480**: F12 → USB → Recovery (Space at the picker if hidden) →
   Disk Utility erase APFS → Install (pulls ~15GB over Ethernet).
   Reboot with USB each time; pick the Installer entry until it disappears.
5. **Post-install**: copy USB `EFI/` to the internal disk's EFI, reboot without USB,
   Reset NVRAM once. Install the HeliPort app (default Wi-Fi mode needs it).
   To try experimental native Wi-Fi: `Tools\Switch-WiFiMode.ps1` — except note the
   Sequoia AirportItlwm entry is intentionally left disabled; enable it only for testing.

## Repo layout

```
EFI/BOOT/               OpenCore bootstrap (from OpenCorePkg)
EFI/OC/config.plist     Full config — serials BLANK, generate your own (step 2)
EFI/OC/ACPI/            13 L480 SSDTs (EC-USBX, PLUG, PNLF, GPRW, PTSWAK, PMCR,
                        HRTF, KBRD, LED, BATT, EXT4, NTFY, VDEV)
EFI/OC/Drivers/         HfsPlus, OpenRuntime, OpenCanopy, AudioDxe
EFI/OC/Tools/           OpenShell, CleanNvram, ResetSystem
EFI/OC/Kexts/           All kexts incl. USBPorts.kext (HS07 = AX210 BT) and
                        CPUFriendDataProvider.kext (shared KBL-R 15W profile —
                        regen with CPUFriendFriend for purists)
Tools/                  Download-Sequoia.ps1, Generate-SMBIOS.ps1, Switch-WiFiMode.ps1
```

## Provenance & thanks

Baseline: [Lifebrowser/ThinkPad-L480-EFI](https://github.com/Lifebrowser/ThinkPad-L480-EFI)
(Sonoma-proven on this chassis), cross-checked with
[azwhikaru/OpenCore-ThinkPad-L480](https://github.com/azwhikaru/OpenCore-ThinkPad-L480) and
[Mayur-4285/Lenovo-Thinkpad-L480-Hackintosh-Opencore](https://github.com/Mayur-4285/Lenovo-Thinkpad-L480-Hackintosh-Opencore).
Wireless: [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm),
[DexterSLamb/itlwm](https://github.com/DexterSLamb/itlwm) (LinkQuality/iServices fix),
[laobamac/itlwm](https://github.com/laobamac/itlwm) (Sequoia alpha). Trackpad:
[VoodooSMBus/VoodooRMI](https://github.com/VoodooSMBus/VoodooRMI). Method:
[Dortania OpenCore Install Guide](https://dortania.github.io/OpenCore-Install-Guide/).
