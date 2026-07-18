//
//  RootView.swift
//  Goods&Glory
//
//  Top-level navigation between main menu, company founding and gameplay.
//

import SwiftUI

struct RootView: View {
    @Environment(GameSession.self) private var session

    var body: some View {
        switch session.phase {
        case .mainMenu:
            MainMenuView()
        case .founding:
            CompanyFoundingView()
        case .playing:
            GameView()
        }
    }
}
