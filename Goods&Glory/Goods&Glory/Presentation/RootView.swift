//
//  RootView.swift
//  Goods&Glory
//
//  Top-level navigation between main menu, company founding and gameplay.
//

import SwiftUI

struct RootView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .mainMenu:
                MainMenuView()
            case .founding:
                CompanyFoundingView()
            case .playing:
                GameView()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                session.persist()
            }
        }
    }
}
