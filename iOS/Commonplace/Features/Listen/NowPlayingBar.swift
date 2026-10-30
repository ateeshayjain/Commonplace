import SwiftUI

/// The mini player above the tab bar while a save is being read aloud.
/// Nothing is shown when nothing is playing or paused.
struct NowPlayingBar: View {
    @ObservedObject private var speech = SpeechService.shared

    var body: some View {
        if let document = speech.document {
            HStack(spacing: CPSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.cpSubhead.weight(.semibold))
                        .foregroundColor(.cpText)
                        .lineLimit(1)
                    Text("\(speech.minutesLeft) min left \u{00B7} \(SpeedMenu.label(speech.speed))")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: CPSpacing.xs)

                Button(action: speech.skipBack) {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Previous paragraph")

                Button {
                    speech.isPlaying ? speech.pause() : speech.resume()
                } label: {
                    Image(systemName: speech.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .frame(width: 32)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(speech.isPlaying ? "Pause" : "Play")

                Button(action: speech.skipForward) {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Next paragraph")

                SpeedMenu()

                Button(action: speech.stop) {
                    Image(systemName: "xmark")
                        .font(.cpSubhead.weight(.semibold))
                        .foregroundColor(.cpTextSecondary)
                }
                .accessibilityLabel("Stop listening")
            }
            .font(.system(size: 17))
            .foregroundColor(.cpTint)
            .padding(.horizontal, CPSpacing.md)
            .padding(.vertical, CPSpacing.sm)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CPSpacing.cornerRadiusLarge))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, CPSpacing.sm)
            .padding(.bottom, CPSpacing.xs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Speed choices, shared by the mini player and the Listen button
struct SpeedMenu: View {
    @ObservedObject private var speech = SpeechService.shared

    static func label(_ speed: Float) -> String {
        speed == speed.rounded() ? "\(Int(speed))\u{00D7}" : "\(String(format: "%g", speed))\u{00D7}"
    }

    var body: some View {
        Menu {
            Picker("Speed", selection: $speech.speed) {
                ForEach(SpeechService.speeds, id: \.self) { speed in
                    Text(Self.label(speed)).tag(speed)
                }
            }
        } label: {
            Text(Self.label(speech.speed))
                .font(.cpFootnote.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 34)
        }
        .accessibilityLabel("Speed \(Self.label(speech.speed))")
    }
}
