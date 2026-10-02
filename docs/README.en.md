<p align="center"><img src="../Assets/VoiceIcon.png" width="128" alt="Voice icon"></p>
<h1 align="center">Voice</h1>
<p align="center">Monitor volume at your fingertips</p>

Voice puts volume and mute controls for your external monitor in the Mac menu bar. When the HDMI output has no adjustable system volume, software mode attenuates playback locally and sends it back to the same device. DDC/CI hardware control is also available when the monitor and connection support it.

**0.3.0 Beta · Apple Silicon · macOS 14.2+ · Chinese UI.** This build is ad-hoc signed and has not been notarized by Apple.

## Install

1. Download the DMG from [Releases](https://github.com/FengBuL/voice-control/releases).
2. Drag Voice into Applications and open it there.
3. If Gatekeeper blocks first launch, follow [Apple's instructions](https://support.apple.com/102445) in System Settings > Privacy & Security after verifying the download source. Do not disable system-wide security checks.
4. Open Voice from the menu bar speaker icon. This menu bar app does not normally show a Dock icon.

ZIP and SHA-256 files are also provided. Quit and delete Voice.app to uninstall. No audio driver is installed.

## Use

Select your monitor in Sound > Output. Open Voice, click **启用软件音量** (Enable Software Volume), and allow system audio access. Play audio, adjust the slider, or click **静音** (Mute). Software volume starts at 30% each time it is enabled. Re-enable after changing the output or cable.

Optional keyboard volume controls require Accessibility permission. Option + Shift uses 1% steps. The monitor's physical volume sets the loudness ceiling. Stopping or quitting removes software attenuation and may restore the original loudness; pause playback first or keep hardware volume comfortable.

Software mode is independent of USB-C-to-HDMI versus direct HDMI cabling. The system HDMI volume slider may remain disabled; use Voice's controls.

## Compatibility and privacy

- Volume and mute were confirmed by a user on USB-C to HDMI with a BenQ EW2780Q.
- Private route creation and cleanup passed on two existing BenQ HDMI audio devices. That check does not verify direct HDMI playback.
- Direct HDMI audible playback, keyboard control, broader devices, latency, protected content, and surround sound need further real-world testing.
- Current format support is stereo 32-bit float PCM with matching input/output sample rates.
- Minimum deployment target is macOS 14.2; the development machine runs macOS 27.0. Intel builds are not provided.
- Audio stays in memory on your Mac. No recording files, uploads, telemetry, ads, or accounts. See [Privacy](PRIVACY.md).
- DDC depends on hardware and connection support. Write-only percentages represent requested values and need physical verification.

## Build

Requires Apple Silicon, macOS 14.2+, Apple Command Line Tools, and Python 3.

```sh
git clone https://github.com/FengBuL/voice-control.git
cd voice-control
./test.sh
./build.sh
open build/Voice.app
./scripts/package.sh
```

Artifacts are written to `release/`. The scripts use ad-hoc signing; Developer ID signing and notarization are not configured. The project-local VFS overlay avoids duplicate Swift module maps in some toolchains without changing system files.

MIT licensed. The vendored [m1ddc](https://github.com/waydabber/m1ddc) retains its MIT license; see [upstream details](../Vendor/m1ddc/UPSTREAM.md). DDC uses private display interfaces, whose compatibility may change with macOS updates.

Report issues with macOS version, Mac and monitor models, cable path, output name, and reproduction steps at [Issues](https://github.com/FengBuL/voice-control/issues). Omit serial numbers and private information.
