import AppKit
import SwiftUI
import CoreAudio
import ApplicationServices

func currentAudioOutput() -> String {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return "未知输出" }
    address.mSelector = kAudioObjectPropertyName
    var name: CFString = "" as CFString
    size = UInt32(MemoryLayout<CFString>.size)
    let result = withUnsafeMutablePointer(to: &name) { pointer in
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
    }
    guard result == noErr else { return "未知输出" }
    return name as String
}

final class VolumeModel: ObservableObject {
    @Published var monitors: [Monitor] = []
    @Published var selectedID = ""
    @Published var percent: Double = 15
    @Published var reading: VolumeReading?
    @Published var status = "正在检测显示器…"
    @Published var detail = ""
    @Published var busy = false
    @Published var writeOnly = false
    @Published var keyboardEnabled = false
    @Published var lastWrite: Int?
    @Published var muted = false
    @Published var audioOutput = ""
    @Published var softwareMode = false
    private let audioEngine = AudioVolumeEngine()
    private let audioQueue = DispatchQueue(label: "local.screenvolume.audio-setup")
    private var audioTimer: Timer?
    private var lastSignalFrames = UInt64(0)
    private var restoredPercent: Double = 15
    private var selectionVersion = 0
    private var desiredVersion = 0
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "local.screenvolume.hardware")
    private var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc") }
    var selectedMonitor: Monitor? { monitors.first { $0.id == selectedID } }
    var canControl: Bool { softwareMode || (selectedMonitor != nil && (reading != nil || writeOnly)) }
    var targetIsAudioOutput: Bool {
        if softwareMode { return audioEngine.matchesCurrentOutput }
        let output = currentAudioOutput()
        return selectedMonitor?.name == output && monitors.filter { $0.name == output }.count == 1
    }

    func refresh() {
        guard !busy else { return }
        if softwareMode {
            if !audioEngine.matchesCurrentOutput { stopSoftwareVolume() }
            return
        }
        busy = true
        status = "正在检测显示器…"
        audioOutput = currentAudioOutput()
        let executable = helper
        queue.async {
            let result = DDCCommand.run(executable: executable, arguments: ["display", "list"])
            let displays = MonitorParser.parse(result.output)
            DispatchQueue.main.async {
                self.monitors = displays
                self.busy = false
                let matches = displays.filter { $0.name == self.audioOutput }
                let saved = UserDefaults.standard.string(forKey: "selectedMonitor") ?? ""
                let chosen = displays.first { $0.id == self.selectedID }
                    ?? (matches.count == 1 ? matches[0] : nil)
                    ?? displays.first { $0.id == saved }
                guard let chosen else {
                    self.invalidateSelection()
                    self.selectedID = ""
                    self.status = displays.isEmpty ? "未发现外接显示器" : "请选择要控制的显示器"
                    self.detail = displays.isEmpty ? result.output : "当前音频输出无法与显示器唯一匹配。"
                    return
                }
                self.select(chosen.id)
            }
        }
    }

    private func invalidateSelection() {
        selectionVersion += 1
        desiredVersion += 1
        pending?.cancel()
        reading = nil
        lastWrite = nil
        muted = false
        writeOnly = false
    }

    func select(_ id: String) {
        guard !softwareMode else { return }
        invalidateSelection()
        selectedID = id
        UserDefaults.standard.set(id, forKey: "selectedMonitor")
        probe()
    }

    func probe() {
        guard !softwareMode else { return }
        guard selectedMonitor != nil else { return }
        busy = true
        status = "正在读取音量…"
        detail = ""
        let id = selectedID, version = selectionVersion, executable = helper
        queue.async {
            let result = DDCCommand.run(executable: executable, arguments: ["display", id, "read", "volume"])
            let volume = result.code == 0 ? VolumeReading.parse(result.output) : nil
            DispatchQueue.main.async {
                guard self.selectionVersion == version else { return }
                self.busy = false
                self.reading = volume
                self.lastWrite = nil
                if let volume {
                    self.percent = volume.percent
                    self.muted = volume.current == 0
                    self.status = "已读取显示器音量"
                    self.detail = "可以拖动滑块调节。"
                } else {
                    self.status = result.output.contains("DDC_EMPTY_REPLY") ? "显示器有响应，音量未读到" : "无法读取显示器音量"
                    self.detail = "硬件音量控制暂时不可用。可启用软件音量，实时调节当前声音输出。"
                }
            }
        }
    }

    func enableWriteOnly(_ enabled: Bool) {
        writeOnly = enabled
        pending?.cancel()
        desiredVersion += 1
        lastWrite = nil
        percent = reading?.percent ?? 15
        status = enabled ? "只写测试模式" : (reading != nil ? "已读取显示器音量" : "无法读取显示器音量")
        detail = enabled ? "按 0–100 范围发送。显示器实际音量待你核对。启用模式不会自动改变音量。" : "请开启 DDC/CI，或重新检测。"
    }

    func setVolume(_ value: Double, immediate: Bool = false) {
        guard canControl else { return }
        percent = min(100, max(0, value))
        muted = percent == 0
        if softwareMode {
            audioEngine.setVolume(percent)
            return
        }
        pending?.cancel()
        desiredVersion += 1
        let requestVersion = desiredVersion, selectedVersion = selectionVersion
        let id = selectedID, maximum = reading?.maximum ?? 100
        let raw = VolumeReading.rawValue(percent: percent, maximum: maximum)
        let executable = helper, expected = percent
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.desiredVersion == requestVersion, self.selectionVersion == selectedVersion else { return }
            self.busy = true
            self.status = "正在发送音量…"
            self.queue.async {
                let stillCurrent = DispatchQueue.main.sync {
                    self.desiredVersion == requestVersion && self.selectionVersion == selectedVersion
                }
                guard stillCurrent else { return }
                let result = DDCCommand.run(executable: executable, arguments: ["display", id, "set", "volume", String(raw)])
                let verification = result.code == 0
                    ? DDCCommand.run(executable: executable, arguments: ["display", id, "read", "volume"])
                    : CommandResult(code: -1, output: "")
                let received = verification.code == 0 ? VolumeReading.parse(verification.output) : nil
                DispatchQueue.main.async {
                    guard self.selectionVersion == selectedVersion else { return }
                    self.busy = false
                    guard self.desiredVersion == requestVersion else { return }
                    if result.code != 0 {
                        self.status = "发送失败"
                        self.detail = "连接未能接收指令。请检查 DDC/CI 和线材，再重新检测。"
                        self.lastWrite = nil
                        if let prior = self.reading { self.percent = prior.percent; self.muted = prior.current == 0 }
                    } else if let received {
                        self.reading = received
                        self.percent = received.percent
                        self.muted = received.current == 0
                        self.lastWrite = nil
                        self.status = received.current == raw ? "音量已确认" : "显示器返回的音量与目标不同"
                        self.detail = "显示器读回 \(Int(received.percent.rounded()))%。"
                    } else {
                        self.reading = nil
                        self.writeOnly = true
                        self.lastWrite = raw
                        self.percent = expected
                        self.status = "已发送，实际效果待核对"
                        self.detail = "请观察显示器音量或听感。读取暂时不可用。"
                    }
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.18), execute: work)
    }

    func toggleMute() {
        guard canControl else { return }
        if percent > 0 { restoredPercent = percent; setVolume(0, immediate: true) }
        else { setVolume(restoredPercent, immediate: true) }
    }

    func change(by amount: Double) { setVolume(percent + amount) }

    func startSoftwareVolume() {
        guard !busy, !softwareMode else { return }
        invalidateSelection()
        busy = true
        percent = 30
        status = "正在申请系统音频访问…"
        detail = "请允许系统弹出的音频访问请求。音频仅在本机实时处理。"
        audioQueue.async {
            do {
                try self.audioEngine.start(percent: 30)
                DispatchQueue.main.async {
                    self.busy = false
                    self.softwareMode = true
                    self.audioOutput = self.audioEngine.outputName
                    self.status = "软件音量处理已启动"
                    self.detail = "请播放声音，再拖动滑块核对实际音量。显示器自身音量保持固定。"
                    self.lastSignalFrames = 0
                    self.audioTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in self?.checkAudioRoute() }
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "软件音量未能启动"
                    self.detail = message + " 可在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Voice。"
                }
            }
        }
    }

    private func checkAudioRoute() {
        guard softwareMode else { return }
        guard audioEngine.matchesCurrentOutput else { stopSoftwareVolume(); return }
        let frames = audioEngine.signalFrameCount
        status = frames > lastSignalFrames ? "已检测到播放声音" : "等待播放声音"
        detail = frames > lastSignalFrames
            ? "正在实时调节音频信号。静音或拖动滑块可核对效果。"
            : "请播放声音。若持续没有反应，请检查系统音频访问权限后重新启用。"
        lastSignalFrames = frames
    }

    func stopSoftwareVolume() {
        audioTimer?.invalidate()
        audioTimer = nil
        softwareMode = false
        busy = true
        audioQueue.async {
            self.audioEngine.stop()
            DispatchQueue.main.async {
                self.busy = false
                self.status = "软件音量已停止"
                self.detail = "声音恢复由原来的输出设备直接播放。"
                self.reading = nil
                self.lastWrite = nil
                self.writeOnly = false
            }
        }
    }

    func shutdown() {
        audioTimer?.invalidate()
        audioQueue.sync { audioEngine.stop() }
    }
}

final class MediaKeys {
    weak var model: VolumeModel?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        if tap != nil { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<MediaKeys>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let model = keys.model, model.keyboardEnabled, model.canControl,
                  model.targetIsAudioOutput, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            let key = (ns.data1 >> 16) & 0xffff
            guard key == 0 || key == 1 || key == 7 else { return Unmanaged.passUnretained(event) }
            let down = ((ns.data1 >> 8) & 0xff) == 0x0a
            if down {
                let fine = ns.modifierFlags.contains(.shift) && ns.modifierFlags.contains(.option)
                if key == 7 { model.toggleMute() }
                else { model.change(by: (key == 0 ? 1 : -1) * (fine ? 1 : 5)) }
            }
            return nil
        }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                             options: .defaultTap, eventsOfInterest: CGEventMask(1 << 14),
                                             callback: callback, userInfo: context) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}

struct VolumePanel: View {
    @ObservedObject var model: VolumeModel
    let keys: MediaKeys
    @State private var showOptions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(nsImage: NSImage(named: "VoiceIcon") ?? NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Voice")!)
                    .resizable().scaledToFit().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice").font(.headline)
                    Text("外接显示器的声音，随手调节").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            Picker("显示器", selection: Binding(get: { model.selectedID }, set: { model.select($0) })) {
                Text("选择显示器").tag("")
                ForEach(model.monitors) { monitor in Text(monitor.name).tag(monitor.id) }
            }
            .pickerStyle(.menu)
            .disabled(model.softwareMode || model.busy)
            HStack(alignment: .firstTextBaseline) {
                Text(model.softwareMode ? "软件音量" : (model.reading != nil ? "显示器音量" : "目标音量（待核对）")).foregroundStyle(.secondary)
                Spacer()
                Text(model.softwareMode || model.reading != nil || model.lastWrite != nil || model.writeOnly ? "\(Int(model.percent.rounded()))%" : "—")
                    .font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.percent }, set: { model.setVolume($0) }), in: 0...100, step: 1)
                    .disabled(!model.canControl)
                    .accessibilityLabel("显示器音量")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            HStack {
                Button { model.toggleMute() } label: {
                    Label(model.muted ? "恢复音量" : "静音", systemImage: model.muted ? "speaker.wave.2" : "speaker.slash")
                }.disabled(!model.canControl)
                Spacer()
                Button("−5") { model.change(by: -5) }.disabled(!model.canControl)
                Button("+5") { model.change(by: 5) }.disabled(!model.canControl)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(model.status, systemImage: model.reading != nil ? "checkmark.circle" : "info.circle")
                    .font(.callout).fontWeight(.medium)
                Text(model.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !model.audioOutput.isEmpty {
                    Text("声音正在输出到：\(model.audioOutput)").font(.caption).foregroundStyle(.secondary)
                }
                if model.canControl && !model.targetIsAudioOutput {
                    Text("所选显示器与当前声音输出不同。可在系统声音设置中切换输出。").font(.caption).foregroundStyle(.orange)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if model.softwareMode {
                Button("停止软件音量") { model.stopSoftwareVolume() }.disabled(model.busy)
            } else if model.reading == nil {
                Button { model.startSoftwareVolume() } label: {
                    Label("启用软件音量", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(model.busy)
                Text("实时调节送往当前声音输出的信号，需要系统音频访问权限。").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("设置与连接测试", isExpanded: $showOptions) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("接管键盘音量键", isOn: Binding(get: { model.keyboardEnabled }, set: { enabled in
                        if enabled {
                            model.keyboardEnabled = keys.start()
                            if !model.keyboardEnabled {
                                model.detail = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Voice，然后重新启用。"
                            }
                        } else { model.keyboardEnabled = false; keys.stop() }
                    })).disabled(model.busy)
                    Text("仅在当前音频输出匹配所选显示器时接管。Option + Shift 可按 1% 微调。").font(.caption).foregroundStyle(.secondary)
                    if model.reading == nil && !model.softwareMode {
                        Toggle("尝试只写模式", isOn: Binding(get: { model.writeOnly }, set: { model.enableWriteOnly($0) })).disabled(model.busy)
                        Text("读取失败时尝试发送音量指令，效果需要核对。数值按 0–100 估算。").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("打开系统声音设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                }.padding(.top, 8)
            }.font(.callout)
            Divider()
            HStack {
                Button("重新检测") { model.refresh() }.disabled(model.busy)
                Spacer()
                Button("关于") {
                    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Voice", .applicationVersion: "0.3.0 · Beta", .credits: NSAttributedString(string: "显示器音量调节 · Monitor volume control\nhttps://github.com/FengBuL/voice-control")])
                }
                Button("退出") { NSApp.terminate(nil) }
            }.buttonStyle(.borderless).font(.caption)
        }.padding(22).frame(width: 350)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = VolumeModel()
    let keys = MediaKeys()
    private var item: NSStatusItem!
    private var popover: NSPopover!
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keys.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Voice 音量调节")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: VolumePanel(model: model, keys: keys))
        model.refresh()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.model.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.togglePanel() }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                print("SMOKE: panel=\(self.popover.isShown), displays=\(self.model.monitors.count), selected=\(self.model.selectedMonitor?.name ?? "none"), status=\(self.model.status), controlEnabled=\(self.model.canControl)")
                let passed = self.popover.contentViewController != nil && self.item.button != nil && !self.model.busy
                exit(passed ? 0 : 1)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keys.stop()
        model.shutdown()
    }

    @objc private func displayChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.model.refresh() }
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            model.audioOutput = currentAudioOutput()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@main
enum ScreenVolumeApp {
    static func main() {
        if CommandLine.arguments.contains("--audio-preflight") {
            let engine = AudioVolumeEngine()
            do {
                try engine.prepare(percent: 30)
                print("AUDIO PREFLIGHT: private route created; output=\(engine.outputName); captureStarted=false")
                engine.stop()
                print("AUDIO PREFLIGHT: route and tap removed")
                exit(0)
            } catch {
                print("AUDIO PREFLIGHT FAILED: \(error.localizedDescription)")
                exit(1)
            }
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
