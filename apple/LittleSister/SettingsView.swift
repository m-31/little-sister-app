//
//  SettingsView.swift
//  LittleSister
//

import SwiftUI
import UniformTypeIdentifiers

private struct DialogButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minWidth: 96)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? Color.accentColor : Color(nsColor: .controlColor))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct SettingsView: View {
    let viewModel: MonitoringViewModel
    private let settings = AppSettings()
    private let tokenStore = KeychainTokenStore()

    @State private var baseURLText = ""
    @State private var nodePathText = ""
    @State private var pollInterval = AppSettings.defaultPollInterval
    @State private var token = ""
    @State private var soundOnError = true
    @State private var alarmSoundName = AppSettings.defaultAlarmSoundName
    @State private var repeatAlarmSound = true
    @State private var useCustomAlarmSound = false
    @State private var customAlarmSoundPath: String? = nil
    @State private var modalAlertOnError = true

    private let minInterval = 5
    private let maxInterval = 3600

    var body: some View {
        Form {
            Section("Server") {
                TextField("Base URL", text: $baseURLText, prompt: Text("http://localhost:8000"))
                TextField("Node path", text: $nodePathText)
            }

            Section("Polling") {
                LabeledContent("Interval") {
                    HStack(spacing: 4) {
                        TextField("", value: $pollInterval, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                        Stepper("", value: $pollInterval, in: minInterval...maxInterval)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: pollInterval) { _, new in
                    let clamped = max(minInterval, new)
                    if clamped != new { pollInterval = clamped }
                }
            }

            Section("Authentication") {
                SecureField("Bearer token", text: $token, prompt: Text("Paste token here"))
                Text("Stored securely in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Alerts") {
                Toggle("Play sound for errors", isOn: $soundOnError)
                if soundOnError {
                    Toggle("Use a custom sound file", isOn: $useCustomAlarmSound)
                    if useCustomAlarmSound {
                        HStack {
                            Text(customAlarmSoundPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file chosen")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose File…") { chooseCustomSoundFile() }
                        }
                    } else {
                        HStack {
                            Picker("Alarm sound", selection: $alarmSoundName) {
                                ForEach(AppSettings.alarmSoundOptions, id: \.name) { option in
                                    Text(option.label).tag(option.name)
                                }
                            }
                            Button("Preview") { previewCurrentAlarmSound() }
                        }
                    }
                    if useCustomAlarmSound {
                        Button("Preview") { previewCurrentAlarmSound() }
                    }
                    Toggle("Repeat while in error", isOn: $repeatAlarmSound)
                }
                Toggle("Show alert dialog for errors", isOn: $modalAlertOnError)
            }

            Section {
                HStack {
                    Button("Cancel") {
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(DialogButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("OK") {
                        commitValues()
                        viewModel.manualRefresh()
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(DialogButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                }
                Text("OK applies and refreshes immediately. Cancel discards changes.")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, maxWidth: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadValues)
        .onDisappear {
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
        }
    }

    private func loadValues() {
        baseURLText = settings.baseURL.absoluteString
        nodePathText = settings.nodePath ?? ""
        pollInterval = settings.pollInterval
        token = tokenStore.loadToken() ?? ""
        soundOnError = settings.soundOnError
        alarmSoundName = settings.alarmSoundName
        repeatAlarmSound = settings.repeatAlarmSound
        useCustomAlarmSound = settings.useCustomAlarmSound
        customAlarmSoundPath = settings.customAlarmSoundPath
        modalAlertOnError = settings.modalAlertOnError
    }

    private func chooseCustomSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            customAlarmSoundPath = url.path
        }
    }

    private func previewCurrentAlarmSound() {
        if useCustomAlarmSound, let path = customAlarmSoundPath {
            NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true)?.play()
        } else {
            NSSound(named: alarmSoundName)?.play()
        }
    }

    private func commitValues() {
        if !baseURLText.isEmpty, let url = URL(string: baseURLText) {
            settings.baseURL = url
        }
        settings.nodePath = nodePathText.isEmpty ? nil : nodePathText
        settings.pollInterval = max(minInterval, pollInterval)
        settings.soundOnError = soundOnError
        settings.alarmSoundName = alarmSoundName
        settings.repeatAlarmSound = repeatAlarmSound
        settings.useCustomAlarmSound = useCustomAlarmSound
        settings.customAlarmSoundPath = customAlarmSoundPath
        settings.modalAlertOnError = modalAlertOnError
        if token.isEmpty { tokenStore.deleteToken() }
        else { tokenStore.save(token: token) }
        DebugLog.shared.record(
            "Settings updated: baseURL=\(settings.baseURL), nodePath=\(settings.nodePath ?? "(root)"), pollInterval=\(settings.pollInterval)s, soundOnError=\(settings.soundOnError), alarmSoundName=\(settings.alarmSoundName), repeatAlarmSound=\(settings.repeatAlarmSound), useCustomAlarmSound=\(settings.useCustomAlarmSound), customAlarmSoundPath=\(settings.customAlarmSoundPath ?? "(none)"), modalAlertOnError=\(settings.modalAlertOnError)",
            category: .settings
        )
    }
}

#Preview {
    SettingsView(viewModel: MonitoringViewModel(
        clientProvider: {
            StatusAPIClient(baseURL: URL(string: "http://localhost:8000")!, nodePath: nil, token: "")
        },
        notificationSender: LiveNotificationSender()
    ))
}
