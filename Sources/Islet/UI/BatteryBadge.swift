import SwiftUI

/// Anel de bateria com porcentagem no meio.
struct BatteryRing: View {
    @EnvironmentObject private var battery: BatteryMonitor
    var diameter: CGFloat = 52

    private var level: Double { Double(battery.percentage) / 100 }

    private var tint: Color {
        if battery.isCharging { return .green }
        if battery.percentage <= 10 { return .red }
        if battery.percentage <= 20 { return .yellow }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, level))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: battery.percentage)

            if battery.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: diameter * 0.3, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text("\(battery.percentage)")
                    .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(battery.percentage)))
                    .animation(.snappy, value: battery.percentage)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Bloco de bateria usado no estado expandido.
struct BatteryBadge: View {
    @EnvironmentObject private var battery: BatteryMonitor

    private var subtitle: String {
        if !battery.hasBattery { return "Na tomada" }
        if let minutes = battery.minutesToFull, battery.isCharging {
            let horas = minutes / 60
            let restante = minutes % 60
            return horas > 0 ? "\(horas)h \(restante)min para 100%" : "\(restante)min para 100%"
        }
        if battery.isCharging { return "Carregando" }
        if battery.isPluggedIn { return "Na tomada" }
        return "Na bateria"
    }

    var body: some View {
        HStack(spacing: 10) {
            BatteryRing()
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.hasBattery ? "\(battery.percentage)%" : "Energia")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(battery.percentage)))
                    .animation(.snappy, value: battery.percentage)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }
}

/// Versão miúda, para o rodapé quando a mídia ocupa o topo.
struct BatteryPill: View {
    @EnvironmentObject private var battery: BatteryMonitor

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percentage {
        case 0..<15: return "battery.0percent"
        case 15..<40: return "battery.25percent"
        case 40..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        if battery.isCharging { return .green }
        if battery.percentage <= 15 { return .red }
        return .white.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text("\(battery.percentage)%")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(battery.percentage)))
                .animation(.snappy, value: battery.percentage)
        }
        .opacity(battery.hasBattery ? 1 : 0)
    }
}
