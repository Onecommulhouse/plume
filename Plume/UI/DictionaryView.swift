import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                title: "Dictionnaire",
                subtitle: "Les noms et mots que Plume doit toujours bien écrire : clients, marques, prénoms, jargon."
            )

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ajouter un mot")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.navy)
                    HStack(spacing: 10) {
                        TextField("Ex. : Domino's, DaVinci, Gathrat", text: $newWord)
                            .textFieldStyle(.plain)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.navy)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.canvas)
                            )
                            .onSubmit(add)
                        Button("Ajouter", action: add)
                            .buttonStyle(PillButtonStyle())
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Astuce : écris le mot exactement comme il doit apparaître, avec ses majuscules.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text(settings.vocabulary.count <= 1 ? "\(settings.vocabulary.count) mot" : "\(settings.vocabulary.count) mots")
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(Theme.navy)
                    if settings.vocabulary.isEmpty {
                        Text("Ton dictionnaire est vide.")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(settings.vocabulary, id: \.self) { word in
                                WordChip(word: word) { settings.removeWord(word) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func add() {
        settings.addWord(newWord)
        newWord = ""
    }
}

private struct WordChip: View {
    let word: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.navy)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.navy : Theme.muted)
            }
            .buttonStyle(.plain)
            .help("Retirer")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.mustardTint))
        .overlay(Capsule().strokeBorder(hovering ? Theme.mustard : Color.clear, lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

/// Dispose les éléments en lignes qui reviennent à la ligne automatiquement.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
