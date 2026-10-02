# Voice 0.3.0 Beta

将外接显示器的音量调节放进 Mac 菜单栏。为 Voice 加入 macOS 风格图标、应用身份、关于面板，以及可拖入“应用程序”的安装包。

## 下载与安装

- Apple Silicon Mac（M 系列），macOS 14.2+。
- 推荐下载 `Voice-0.3.0-macOS-arm64.dmg`，打开后将 Voice 拖入 Applications。
- `Voice-0.3.0-macOS-arm64.zip` 为同一应用的压缩包。
- `SHA256SUMS.txt` 提供 SHA-256 校验值；`INSTALL.txt` 提供中英文操作说明。

本测试版采用临时签名，**尚未获得 Apple Developer ID 签名与公证**。首次打开可能被 macOS 阻止，请按 [Apple 的首次打开说明](https://support.apple.com/102445) 在“隐私与安全性”中操作；不要关闭整个系统的安全检查。

## 使用

在系统声音设置选择显示器，点击菜单栏扬声器，再点击“启用软件音量”并允许系统音频访问。拖动滑块或静音即可调节送往显示器的声音。软件初始音量为 30%；切换连接或输出后需要重新启用。

## 已验证与已知范围

- USB-C 转 HDMI → BenQ EW2780Q：用户实测调节和静音有效。
- 两个现有 BenQ HDMI 音频设备：私有通道创建和清理检查通过。
- HDMI 直连使用同一软件音频路径，实际播放仍待更多接线验证。
- 单元与协议检查覆盖音量换算、DDC 报文以及实时衰减、静音、平面声道和限幅。
- 当前限定双声道 32-bit float PCM；其他格式会提示不兼容。Intel Mac、环绕声、受保护内容和更广泛设备尚未验证。
- 键盘音量键为可选功能，需辅助功能权限，仍需更多实机验证。
- 系统 HDMI 音量滑块可能继续灰色。DDC 硬件模式依赖显示器与连接支持，本机 DDC 音量未生效。
- 停止软件音量或退出应用会结束衰减，可能恢复原始响度；先暂停播放或设置舒适的实体音量。

软件音量只在本机处理，不保存或上传音频，无第三方音频驱动。当前界面为中文。欢迎在 [Issues](https://github.com/FengBuL/voice-control/issues) 提供 macOS 版本、设备型号、连接方式与复现步骤，请省略序列号和私人信息。

## English

Voice brings monitor volume controls to your Mac menu bar. This beta includes a native-style app icon, a drag-to-Applications DMG, and bilingual setup instructions.

Requires Apple Silicon and macOS 14.2+. This build is ad-hoc signed and **not notarized by Apple**. Follow [Apple's guidance](https://support.apple.com/102445) if Gatekeeper blocks first launch.

Choose your monitor in Sound > Output, open Voice, enable software volume, and allow system audio access. Use the slider or mute. Re-enable when changing outputs. Audio stays on your Mac; no recording files, uploads, or third-party audio drivers.

Volume and mute were verified with USB-C to HDMI and a BenQ EW2780Q. Direct HDMI uses the same software route but audible playback needs more verification. Only stereo 32-bit float PCM is currently accepted. Intel, surround sound, protected content, and broader device compatibility are unverified. The UI is currently Chinese. Stopping or quitting restores unattenuated playback; pause playback first.
