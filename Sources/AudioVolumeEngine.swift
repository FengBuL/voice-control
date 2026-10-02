import Foundation
import CoreAudio

struct AudioRouteError: LocalizedError {
    let operation: String
    let code: OSStatus
    var errorDescription: String? { "\(operation)失败（\(code)）。请检查系统音频访问权限。" }
}

final class AudioVolumeEngine {
    private var tap = AudioObjectID(0)
    private var aggregate = AudioDeviceID(0)
    private var output = AudioDeviceID(0)
    private var proc: AudioDeviceIOProcID?
    private var registration: AudioDeviceIOProcID?
    private var context: UnsafeMutableRawPointer?
    private(set) var outputName = ""
    private(set) var isRunning = false
    var frameCount: UInt64 { SVAudioFrames(context) }
    var signalFrameCount: UInt64 { SVAudioSignalFrames(context) }
    var matchesCurrentOutput: Bool {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var current = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current) == noErr && current == output
    }

    private func check(_ code: OSStatus, _ operation: String) throws {
        guard code == noErr else { throw AudioRouteError(operation: operation, code: code) }
    }
    private func property(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = property(selector), size = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        try check(result, "读取设备信息")
        return value as String
    }

    // Preparation creates private objects but does not start audio capture or mute playback.
    func prepare(percent: Double) throws {
        stop()
        do {
            var address = property(kAudioHardwarePropertyDefaultOutputDevice)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &output), "读取当前声音输出")
            let uid = try stringProperty(output, kAudioDevicePropertyDeviceUID)
            outputName = try stringProperty(output, kAudioObjectPropertyName)

            // Ensure our HAL process exists, so replay is explicitly excluded from the tap.
            try check(AudioDeviceCreateIOProcID(output, SVAudioIOProc, nil, &registration), "注册音频进程")
            var pid = getpid(), ownProcess = AudioObjectID(0)
            address = property(kAudioHardwarePropertyTranslatePIDToProcessObject)
            size = UInt32(MemoryLayout<AudioObjectID>.size)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                 UInt32(MemoryLayout<pid_t>.size), &pid, &size, &ownProcess), "定位音频进程")
            guard ownProcess != kAudioObjectUnknown else { throw AudioRouteError(operation: "排除自身音频回路", code: -1) }
            let description = CATapDescription(excludingProcesses: [ownProcess], deviceUID: uid, stream: 0)
            description.name = "Voice 本地音量处理"
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(description, &tap), "建立系统音频通道")

            var format = AudioStreamBasicDescription()
            address = property(kAudioTapPropertyFormat)
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "读取输入音频格式")
            try validateFormat(format)
            context = SVAudioCreate(Float(min(100, max(0, percent)) / 100), format.mSampleRate)
            guard context != nil else { throw AudioRouteError(operation: "分配音频处理缓冲", code: -1) }

            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Voice 本地音量路由",
                kAudioAggregateDeviceUIDKey: "io.github.fengbul.voicecontrol." + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "建立本地音频路由")
            var outputFormat = AudioStreamBasicDescription()
            address = property(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeOutput)
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &outputFormat), "读取输出音频格式")
            try validateFormat(outputFormat)
            guard abs(outputFormat.mSampleRate - format.mSampleRate) < 1 else {
                throw AudioRouteError(operation: "匹配音频采样率", code: -1)
            }
            try check(AudioDeviceCreateIOProcID(aggregate, SVAudioIOProc, context, &proc), "建立音频处理回调")
        } catch {
            stop()
            throw error
        }
    }

    private func validateFormat(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mChannelsPerFrame == 2, format.mSampleRate > 0 else {
            throw AudioRouteError(operation: "匹配双声道浮点音频格式", code: -1)
        }
    }

    func start(percent: Double) throws {
        try prepare(percent: percent)
        do {
            try check(AudioDeviceStart(aggregate, proc), "启动音频处理")
            isRunning = true
        } catch { stop(); throw error }
    }

    func setVolume(_ percent: Double) {
        SVAudioSetGain(context, Float(min(100, max(0, percent)) / 100))
    }

    func stop() {
        if aggregate != 0 {
            if isRunning { AudioDeviceStop(aggregate, proc) }
            if let proc { AudioDeviceDestroyIOProcID(aggregate, proc) }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        proc = nil
        aggregate = 0
        isRunning = false
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        tap = 0
        if let registration { AudioDeviceDestroyIOProcID(output, registration) }
        registration = nil
        if let context { SVAudioDestroy(context) }
        context = nil
    }

    deinit { stop() }
}
