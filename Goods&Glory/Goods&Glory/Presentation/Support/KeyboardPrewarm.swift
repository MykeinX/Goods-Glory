//
//  KeyboardPrewarm.swift
//  Goods&Glory
//
//  The first tap on any text field in an iOS app pays for the keyboard's
//  one-time construction: input modes, the autocorrect stack and the layout
//  itself are all built lazily, and on a cold launch that lands as a visible
//  freeze — right at the moment the player types their company name, which is
//  the first thing they ever do here.
//
//  So we pay it earlier, off the critical path: a detached, off-screen field
//  becomes first responder for one runloop turn while the main menu is idle.
//  Nothing is shown, nothing is typed, and by the time the founding screen
//  opens the keyboard is already warm.
//

import SwiftUI
import UIKit

enum KeyboardPrewarm {
    private static var hasRun = false

    /// Safe to call repeatedly; only the first call does any work.
    @MainActor
    static func runOnce() {
        guard !hasRun else { return }
        hasRun = true

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: \.isKeyWindow) else { return }

        let field = UITextField(frame: .zero)
        // Zero alpha, zero size, behind everything: it must never be visible or
        // hittable, it only needs to exist in a window to become first responder.
        field.alpha = 0
        field.isUserInteractionEnabled = false
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        // Removing it synchronously can cancel the work we just triggered, so
        // let the runloop finish the construction first.
        DispatchQueue.main.async { field.removeFromSuperview() }
    }
}

extension View {
    /// Warms the keyboard once the view is on screen and settled.
    func prewarmsKeyboard() -> some View {
        task {
            // A beat after appearing: launch work and first layout come first.
            try? await Task.sleep(for: .milliseconds(400))
            KeyboardPrewarm.runOnce()
        }
    }
}
