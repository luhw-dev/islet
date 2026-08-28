import SwiftUI

/// Página de uso: um anel por assistente e, embaixo, as janelas de limite do
/// que estiver selecionado.
struct UsageView: View {
    @EnvironmentObject private var usage: UsageMonitor

    var body: some View {
        VStack(spacing: 8) {
            aneis
            detalhe
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // O botão fica por cima dos anéis, e não numa linha de cabeçalho: as
        // três barras do Claude só cabem se ninguém gastar altura com título.
        .overlay(alignment: .topTrailing) { botaoAtualizar }
    }

    private var botaoAtualizar: some View {
        Button {
            Haptics.tap()
            usage.refresh(manual: true)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(usage.isRefreshing ? 0.2 : 0.4))
                // Gira enquanto consulta, para a espera ter sinal.
                .rotationEffect(.degrees(usage.isRefreshing ? 360 : 0))
                .animation(
                    usage.isRefreshing
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .default,
                    value: usage.isRefreshing)
                // O ícone é pequeno demais para ser o alvo do clique.
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
    }

    private var aneis: some View {
        HStack(spacing: 26) {
            ForEach(usage.providers) { provider in
                UsageRing(
                    provider: provider,
                    state: usage.state(for: provider),
                    isSelected: usage.selected == provider
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        usage.selected = provider
                    }
                }
            }
        }
        .frame(height: 50)
    }

    @ViewBuilder
    private var detalhe: some View {
        switch usage.state(for: usage.selected) {
        case .ready(let snapshot):
            VStack(spacing: 5) {
                ForEach(snapshot.windows.prefix(3)) { janela in
                    UsageBar(window: janela, isStale: snapshot.isStale)
                }
                if snapshot.isDated {
                    // O Codex só publica limite quando roda; sem essa linha o
                    // número velho passaria por atual.
                    Text("medido \(UsageFormat.relativo(snapshot.measuredAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .loading:
            aviso(usage.isRefreshing ? "Consultando…" : "Sem leitura ainda", icone: "ellipsis")

        case .unavailable(let motivo):
            aviso(motivo, icone: "exclamationmark.triangle")
        }
    }

    private func aviso(_ texto: String, icone: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icone)
                .font(.system(size: 11, weight: .medium))
            Text(texto)
                .font(.system(size: 11))
                .lineLimit(2)
        }
        .foregroundStyle(.white.opacity(0.35))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Anel

private struct UsageRing: View {
    let provider: UsageProvider
    let state: UsageState
    let isSelected: Bool

    private var percent: Double { state.snapshot?.headline ?? 0 }
    private var isStale: Bool { state.snapshot?.isStale ?? false }
    private var temDado: Bool { state.snapshot != nil }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(1, percent / 100)))
                    .stroke(
                        UsageFormat.cor(percent).opacity(isStale ? 0.5 : 1),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    // Começa em cima, como todo medidor.
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: percent)
                BrandGlyphShape(glyph: provider.glyph)
                    .fill(.white.opacity(temDado ? 0.9 : 0.35))
                    .frame(width: 14, height: 14)
            }
            .frame(width: 32, height: 32)

            Text(temDado ? "\(Int(percent.rounded()))%" : "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: percent))
                .foregroundStyle(.white.opacity(temDado ? 0.85 : 0.3))
                .animation(.snappy, value: percent)
        }
        // O não selecionado continua legível, só recua.
        .opacity(isSelected ? 1 : 0.5)
        .scaleEffect(isSelected ? 1 : 0.94)
    }
}

// MARK: - Barra de uma janela

private struct UsageBar: View {
    let window: UsageWindow
    let isStale: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 4)
                if let reset = UsageFormat.reset(window.resetsAt) {
                    Text(reset)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text("\(Int(window.percent.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(UsageFormat.cor(window.percent).opacity(isStale ? 0.5 : 1))
                        .frame(width: max(2, geo.size.width * min(1, window.percent / 100)))
                }
            }
            .frame(height: 4)
        }
        .animation(.easeOut(duration: 0.3), value: window.percent)
    }
}

// MARK: - Formatação

enum UsageFormat {
    /// A cor vem do quanto foi gasto, não da marca: é o mesmo código de leitura
    /// em qualquer provedor.
    static func cor(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case ..<75: return Color(red: 0.98, green: 0.82, blue: 0.25)
        default: return Color(red: 1.0, green: 0.38, blue: 0.25)
        }
    }

    /// "em 51 min", "em 3 h", "qui 00:00".
    static func reset(_ data: Date?) -> String? {
        guard let data else { return nil }
        let restante = data.timeIntervalSinceNow
        if restante <= 0 { return "renovando" }
        if restante < 3600 { return "em \(Int(restante / 60)) min" }
        if restante < 12 * 3600 { return "em \(Int((restante / 3600).rounded())) h" }

        let formatador = DateFormatter()
        formatador.locale = Locale(identifier: "pt_BR")
        formatador.dateFormat = restante < 6 * 86400 ? "EEE HH:mm" : "dd/MM HH:mm"
        return formatador.string(from: data)
    }

    /// "há 2 h", "há 3 d".
    static func relativo(_ data: Date) -> String {
        let idade = max(0, Date().timeIntervalSince(data))
        if idade < 3600 { return "há \(Int(idade / 60)) min" }
        if idade < 86400 { return "há \(Int(idade / 3600)) h" }
        return "há \(Int(idade / 86400)) d"
    }
}
