import SwiftUI

/// Prateleira de arquivos: arraste para dentro para guardar, arraste para fora
/// para soltar em outro app.
struct ShelfView: View {
    @ObservedObject var model: IslandModel
    @EnvironmentObject private var shelf: ShelfStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(model.isDropTargeted ? 0.14 : 0.06))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(model.isDropTargeted ? 0.45 : 0.12),
                    style: StrokeStyle(lineWidth: 1, dash: shelf.items.isEmpty ? [4, 4] : [])
                )

            if shelf.items.isEmpty {
                Label("Solte arquivos aqui", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfChip(item: item) { shelf.remove(item) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
    }
}

private struct ShelfChip: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 28, height: 28)
            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
        }
        .padding(.top, 8)
        .frame(width: 64, height: 62)
        // Sem isto o hover só valia sobre os pixels desenhados, e o mouse
        // "caía no buraco" entre o ícone e o nome.
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Dentro dos limites de propósito: com deslocamento negativo
                // ele vazava e era cortado pelo recorte da página.
                .padding(2)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .onHover { estaSobre in
            withAnimation(.easeOut(duration: 0.12)) { hovering = estaSobre }
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }
}

/// Lixeira que só se acende quando o mouse chega perto.
struct BotaoDeLixeira: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.35))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.12 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { estaSobre in
            withAnimation(.easeOut(duration: 0.12)) { hovering = estaSobre }
        }
    }
}

/// Uma entrada do histórico de cópia. Clicar devolve o texto para a área de
/// transferência.
struct ClipboardRow: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    var onRemove: (() -> Void)?

    @State private var hovering = false
    @State private var copiado = false

    /// Miniatura para imagem, ícone do sistema para arquivo, glifo para texto —
    /// todos no mesmo tamanho, senão as linhas desalinham.
    @ViewBuilder
    private var visual: some View {
        switch item.content {
        case .image(_, let miniatura, _):
            Image(nsImage: miniatura)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .files(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path))
                .resizable()
                .frame(width: 18, height: 18)
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 18, height: 18)
        }
    }

    var body: some View {
        Button {
            onCopy()
            Haptics.tap()
            copiado = true
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                copiado = false
            }
        } label: {
            HStack(spacing: 8) {
                visual
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if hovering, !copiado, let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: copiado ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(copiado ? 0.9 : (hovering ? 0.6 : 0)))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.12 : 0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { estaSobre in
            withAnimation(.easeOut(duration: 0.14)) { hovering = estaSobre }
        }
    }
}
