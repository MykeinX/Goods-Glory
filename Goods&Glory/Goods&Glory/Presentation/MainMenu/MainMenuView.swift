//
//  MainMenuView.swift
//  Goods&Glory
//
//  Title screen: night-logistics backdrop, glowing brand mark, capsule actions.
//

import SwiftUI

struct MainMenuView: View {
    @Environment(GameSession.self) private var session
    @State private var showsOverwriteConfirmation = false

    var body: some View {
        ZStack {
            AnimatedWorldBackground()

            VStack(spacing: 0) {
                Spacer()

                // Brand block
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Theme.gold.opacity(0.18))
                            .frame(width: 150, height: 150)
                            .blur(radius: 30)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Theme.backgroundTop)
                            .frame(width: 96, height: 96)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.gold, Theme.gold.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .shadow(color: Theme.gold.opacity(0.5), radius: 18, y: 6)
                    }

                    VStack(spacing: 8) {
                        Text("Goods & Glory")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Theme.gold.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("Build a global logistics empire.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()
                Spacer()

                // Actions
                VStack(spacing: 14) {
                    if session.hasSave {
                        Button {
                            session.continueGame()
                        } label: {
                            Label("Continue", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            showsOverwriteConfirmation = true
                        } label: {
                            Label("New Game", systemImage: "plus")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button {
                            session.beginFounding()
                        } label: {
                            Label("New Game", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 56)
            }
        }
        .confirmationDialog(
            "Starting a new game will delete your current campaign.",
            isPresented: $showsOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete and Start New", role: .destructive) {
                // Eski kayıt founding iptal edilirse kalsın; yeni kampanya startNewGame ile üzerine yazılır.
                session.beginFounding()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
