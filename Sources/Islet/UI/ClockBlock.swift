import SwiftUI

/// Relógio + data. `compact` é a versão de rodapé.
struct ClockBlock: View {
    var compact = false

    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if compact {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .onReceive(tick) { now = $0 }
    }
}
