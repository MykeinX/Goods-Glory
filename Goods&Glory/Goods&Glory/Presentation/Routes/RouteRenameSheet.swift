//
//  RouteRenameSheet.swift
//  Goods&Glory
//
//  Lightweight rename surface. System alerts-with-text-fields freeze over a
//  live SpriteKit map (keyboard cold-start + alert presentation); a plain
//  sheet with a pre-warmed keyboard stays responsive.
//

import SwiftUI

struct RouteRenameSheet: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    var accent: Color

    @State private var draft = ""
    @State private var commandError: CommandError?
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.stroke.opacity(1.5))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(accent.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rename Route")
                            .font(.gg(21, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Shown on the fleet list and map cards.")
                            .font(.gg(12.5, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                TextField("Route name", text: $draft)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .font(.gg(16, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(accent)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(nameFocused ? accent : Theme.stroke, lineWidth: nameFocused ? 1.6 : 1)
                    )

                if commandError != nil {
                    Label(
                        "Could not rename this route. Try again.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.coral)
                }

                Spacer(minLength: 0)

                VStack(spacing: 9) {
                    Button(action: save) {
                        Text("Save Name")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: accent))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)

                    Button("Keep Name") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.backgroundBottom)
        .tint(accent)
        .onAppear {
            // Pay keyboard construction before focus — same idea as the main menu.
            KeyboardPrewarm.runOnce()
            if draft.isEmpty {
                draft = session.state?.route(routeID)?.name ?? ""
            }
            Task { @MainActor in
                // Let the sheet finish presenting, then focus the warm keyboard.
                try? await Task.sleep(for: .milliseconds(80))
                nameFocused = true
            }
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let error = session.perform(.renameRoute(routeID: routeID, name: trimmed)) {
            commandError = error
        } else {
            dismiss()
        }
    }
}
