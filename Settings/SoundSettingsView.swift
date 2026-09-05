// Shared sound controls. Keep in step with the iOS copy.
import SwiftUI

struct SoundSettingsView: View {
    @Bindable private var sound = SoundEngine.shared
    @AppStorage("haptics.enabled") private var hapticsEnabled = true

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: DS.space24) {
            Text("Sound & Haptics").font(DS.pageTitle).foregroundStyle(DS.text)
            SettingsGroupedBox {
                SoundProfileControl(sound: sound).padding(DS.space16)
                SettingsRowDivider()
                SoundVolumeControl(sound: sound).padding(DS.space16)
                SettingsRowDivider()
                Toggle("Haptic feedback", isOn: $hapticsEnabled).padding(DS.space16)
                    .help("Tactile feedback on a supported trackpad")
            }
            SoundPreviewGroup(sound: sound)
            Text("Haptics use a supported trackpad. Sounds pause when you leave the app.")
                .font(DS.footnote).foregroundStyle(DS.textMuted)
        }
        #else
        Section {
            SoundProfileControl(sound: sound)
            SoundVolumeControl(sound: sound)
            Toggle("Haptic feedback", isOn: $hapticsEnabled)
            SoundPreviewRow(title: "Complete a task", cue: .complete, sound: sound)
            SoundPreviewRow(title: "Finish a focus session", cue: .focus, sound: sound)
            SoundPreviewRow(title: "Reach a milestone", cue: .milestone, sound: sound)
        } header: {
            Text("Sound & Haptics")
        } footer: {
            Text("Sounds follow silent mode and stay quiet during music and videos. Haptics work independently.")
        }
        #endif
    }
}

private struct SoundProfileControl: View {
    @Bindable var sound: SoundEngine

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Picker("Sounds", selection: $sound.profile) {
                ForEach(SoundProfile.allCases, id: \.self) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.accent)
            Text(sound.profile.detail)
                .font(DS.footnote).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SoundVolumeControl: View {
    @Bindable var sound: SoundEngine

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                Text("Volume").font(DS.callout)
                Spacer()
                Text(sound.volume, format: .percent.precision(.fractionLength(0)))
                    .font(DS.footnote.monospacedDigit()).foregroundStyle(DS.textSecondary)
            }
            Slider(value: $sound.volume, in: 0...1, step: 0.05) {
                Text("Interface sound volume")
            } minimumValueLabel: {
                Image(systemName: "speaker").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.2").accessibilityHidden(true)
            }
            .labelsHidden()
            .accessibilityLabel("Interface sound volume")
            .tint(DS.accent)
            .disabled(sound.profile == .off)
        }
        .foregroundStyle(DS.text)
    }
}

#if os(macOS)
private struct SoundPreviewGroup: View {
    let sound: SoundEngine

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            SettingsSectionHeader(label: "PREVIEW")
            SettingsGroupedBox {
                SoundPreviewRow(title: "Complete a task", cue: .complete, sound: sound).padding(.horizontal, DS.space16)
                SettingsRowDivider()
                SoundPreviewRow(title: "Finish a focus session", cue: .focus, sound: sound).padding(.horizontal, DS.space16)
                SettingsRowDivider()
                SoundPreviewRow(title: "Reach a milestone", cue: .milestone, sound: sound).padding(.horizontal, DS.space16)
            }
        }
    }
}
#endif

private struct SoundPreviewRow: View {
    let title: String
    let cue: SoundCue
    let sound: SoundEngine
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            sound.play(cue, preview: true)
            #if os(iOS)
            if cue == .complete { Haptics.completion() } else { Haptics.commit() }
            #else
            CosmicHaptics.shared.play(.success)
            #endif
        } label: {
            HStack(spacing: DS.space12) {
                Text(title).font(DS.callout).foregroundStyle(DS.text)
                Spacer(minLength: DS.space8)
                Image(systemName: "play.circle").font(DS.title2).foregroundStyle(DS.textSecondary)
                    .frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
            .background(DS.accentSoft.opacity(hovered ? 0.5 : 0), in: .rect(cornerRadius: DS.space8))
        }
        .buttonStyle(.plain)
        .disabled(sound.profile == .off || sound.volume == 0)
        .opacity(sound.profile == .off || sound.volume == 0 ? 0.45 : 1)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : ProMotionSprings.snappy, value: hovered)
        .accessibilityLabel("Preview: \(title)")
        .help("Preview: \(title)")
    }
}
