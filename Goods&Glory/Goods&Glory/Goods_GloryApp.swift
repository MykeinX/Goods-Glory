//
//  Goods_GloryApp.swift
//  Goods&Glory

import SwiftUI

@main
struct Goods_GloryApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}

/// Loads and validates the content catalog before showing the game.
/// A broken catalog is a controlled launch failure, never a silent fallback.
private struct AppBootstrapView: View {
    @State private var session: GameSession?
    @State private var loadFailure: String?

    var body: some View {
        Group {
            if let session {
                RootView()
                    .environment(session)
            } else if let loadFailure {
                ContentUnavailableView {
                    Label("Content Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadFailure)
                }
            } else {
                ProgressView()
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .onAppear(perform: bootstrap)
    }

    private func bootstrap() {
        guard session == nil, loadFailure == nil else { return }
        do {
            let catalog = try GameCatalog.load(from: .main)
            session = GameSession(catalog: catalog)
        } catch {
            loadFailure = String(describing: error)
        }
    }
}

#Preview("Goods & Glory App") {
    AppBootstrapView()
}
