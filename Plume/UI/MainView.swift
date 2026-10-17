import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard
    case history
    case dictionary
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Tableau de bord"
        case .history: return "Historique"
        case .dictionary: return "Dictionnaire"
        case .settings: return "Réglages"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var section: AppSection = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
                .frame(width: 248)
            ScrollView {
                Group {
                    switch section {
                    case .dashboard: DashboardView(section: $section)
                    case .history: HistoryView()
                    case .dictionary: DictionaryView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 40)
                .padding(.bottom, 36)
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @Binding var section: AppSection
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nommage back-office ONE COM : « one com » + nom de l'app en jaune moutarde.
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.paper.opacity(0.08))
                    WaveMark(barWidth: 2.6, spacing: 2.2)
                        .frame(width: 24, height: 20)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("one com")
                        .font(Theme.font(11, .semibold))
                        .foregroundStyle(Theme.paper.opacity(0.65))
                    Text("Plume")
                        .font(Theme.font(22, .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.mustard)
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 22)
            .padding(.bottom, 30)

            VStack(spacing: 4) {
                ForEach(AppSection.allCases) { item in
                    SidebarItem(item: item, selected: item == section) {
                        section = item
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            StatusCard()
                .padding(14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.navy)
    }
}

private struct SidebarItem: View {
    let item: AppSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? Theme.mustard : Theme.paper.opacity(0.7))
                    .frame(width: 20)
                Text(item.title)
                    .font(Theme.font(14, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.paper : Theme.paper.opacity(0.75))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.paper.opacity(selected ? 0.10 : (hovering ? 0.05 : 0)))
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Theme.mustard).frame(width: 3, height: 18).offset(x: -6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct StatusCard: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isReady ? Theme.mustard : Theme.soft)
                    .frame(width: 8, height: 8)
                Text(controller.statusLine)
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(2)
            }
            Text("Maintiens \(settings.hotkey.label), parle, relâche.")
                .font(Theme.font(12))
                .foregroundStyle(Theme.paper.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.paper.opacity(0.06))
        )
    }
}

/// Titre de page commun.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.font(28, .bold))
                .tracking(-0.8)
                .foregroundStyle(Theme.navy)
            Text(subtitle)
                .font(Theme.font(14))
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 8)
    }
}
