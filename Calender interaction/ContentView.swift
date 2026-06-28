import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Model

struct CalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    var startMinute: Int
    let durationMinutes: Int
    let color: Color

    var durationLabel: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        if h > 0, m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }
}

// MARK: - Layout

private enum Layout {
    static let slotHeight: CGFloat      = 48
    static let minutesPerSlot: Int      = 60
    static let ptPerMinute: CGFloat     = slotHeight / 60  // 0.8 pt/min
    static let timeColumnWidth: CGFloat = 60
    static let slotCount: Int           = 24
    static let snapInterval: Int        = 15
    static let columnGap: CGFloat       = 16
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8)  & 0xFF) / 255,
            blue:  Double( n        & 0xFF) / 255
        )
    }
}

// MARK: - Haptics

private func impact() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #elseif canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    #endif
}

private func impactMedium() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #elseif canImport(AppKit)
    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    #endif
}

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedDay = 6
    @State private var events: [CalendarEvent] = [
        .init(title: "Daily stand up", startMinute: 9 * 60,  durationMinutes: 150, color: Color(hex: "1d639d")),
        .init(title: "Go for a ride",  startMinute: 20 * 60, durationMinutes: 30,  color: Color(hex: "157a68"))
    ]

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    private let dates      = [22, 23, 24, 25, 26, 27, 28]
    private let isWeekend  = [false, false, false, false, false, true, true]

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
            weekStrip
            Divider()
            TimelineView(events: $events)
        }
        .background(Color.white)
    }

    private var calendarHeader: some View {
        HStack {
            Button(action: {}) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("June")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(Color(hex: "2a2a2a"))
                .padding(.horizontal, 20)
                .frame(height: 40)
                .glassEffect(.regular, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            Image("avatar")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 3) {
                    Text(dayLabels[i])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: isWeekend[i] ? "8d8d8d" : "595959"))
                    ZStack {
                        Circle()
                            .fill(selectedDay == i ? Color.black : Color.clear)
                            .frame(width: 32, height: 32)
                        Text("\(dates[i])")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(
                                selectedDay == i ? .white
                                : Color(hex: isWeekend[i] ? "8d8d8d" : "595959")
                            )
                    }
                    .frame(width: 32, height: 32)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedDay)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDay = i
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - TimelineView

struct TimelineView: View {
    @Binding var events: [CalendarEvent]
    @State private var currentMinute: Int   = 0
    @State private var draggingID: UUID?    = nil
    @State private var liveOffset: CGFloat  = 0   // raw finger translation — NOT snapped
    @State private var timelineWidth: CGFloat = 300

    private var timelineHeight: CGFloat { CGFloat(Layout.slotCount) * Layout.slotHeight }

    // Absolute Y for an event, including live finger offset for the dragged one
    private func yPos(for event: CalendarEvent) -> CGFloat {
        let base = CGFloat(event.startMinute) * Layout.ptPerMinute
        return event.id == draggingID ? base + liveOffset : base
    }

    // (column, totalColumns) for an event given current overlap state.
    // Compares in point space (CGFloat) so the split triggers the exact pixel
    // edges touch — no integer-minute rounding delay.
    private func colInfo(for event: CalendarEvent) -> (col: Int, total: Int) {
        let eTop    = yPos(for: event)
        let eBottom = eTop + CGFloat(event.durationMinutes) * Layout.ptPerMinute
        for other in events where other.id != event.id {
            let oTop    = yPos(for: other)
            let oBottom = oTop + CGFloat(other.durationMinutes) * Layout.ptPerMinute
            guard eTop < oBottom && oTop < eBottom else { continue }
            return (col: event.id.uuidString < other.id.uuidString ? 0 : 1, total: 2)
        }
        return (col: 0, total: 1)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Grid
                    VStack(spacing: 0) {
                        ForEach(0..<Layout.slotCount, id: \.self) { slot in
                            TimeRow(label: String(format: "%02d:00", slot))
                                .id("slot-\(slot)")
                        }
                    }

                    // Events — position is owned here, animation is owned inside the container
                    ForEach($events) { $event in
                        let info = colInfo(for: event)
                        EventBlockContainer(
                            event: $event,
                            isDragging: event.id == draggingID,
                            col: info.col,
                            totalCols: info.total,
                            timelineWidth: timelineWidth,
                            yPos: yPos(for: event),
                            onDragChanged: { dy in
                                if draggingID == nil { impactMedium() }
                                draggingID = event.id
                                liveOffset = dy   // raw translation — no snapping, follows finger directly
                            },
                            onDragEnded: { dy in
                                let delta    = Int(dy / Layout.ptPerMinute)
                                let snapped  = (delta / Layout.snapInterval) * Layout.snapInterval
                                let maxStart = Layout.slotCount * Layout.minutesPerSlot - event.durationMinutes
                                event.startMinute = max(0, min(maxStart, event.startMinute + snapped))
                                draggingID = nil
                                liveOffset = 0
                                impactMedium()
                            }
                        )
                        .zIndex(event.id == draggingID ? 1 : 0)
                    }

                    CurrentTimeLine(minute: currentMinute)
                        .frame(maxWidth: .infinity)
                }
                .frame(minHeight: timelineHeight)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear { timelineWidth = geo.size.width }
                    }
                )
            }
            .scrollDisabled(draggingID != nil)
            .onAppear {
                let cal = Calendar.current
                let now = Date()
                currentMinute = cal.component(.hour, from: now) * 60
                              + cal.component(.minute, from: now)
                let scrollSlot = max(0, currentMinute / 60 - 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation { proxy.scrollTo("slot-\(scrollSlot)", anchor: .top) }
                }
            }
        }
    }
}

// MARK: - EventBlockContainer
//
// Owns layout position. Tracks col/totalCols as @State so X/width
// spring-animate independently — Y is set directly with no animation.

struct EventBlockContainer: View {
    @Binding var event: CalendarEvent
    let isDragging: Bool
    let col: Int
    let totalCols: Int
    let timelineWidth: CGFloat
    let yPos: CGFloat
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    // Local animated copies — only these change inside withAnimation
    @State private var animCol: Int   = 0
    @State private var animTotal: Int = 1

    private var contentWidth: CGFloat {
        timelineWidth - Layout.timeColumnWidth - 8 - 16
    }
    private var colWidth: CGFloat {
        animTotal > 1 ? (contentWidth - Layout.columnGap) / 2 : contentWidth
    }
    private var xPos: CGFloat {
        Layout.timeColumnWidth + 8 + CGFloat(animCol) * (colWidth + Layout.columnGap)
    }

    var body: some View {
        EventBlock(
            event: $event,
            isDragging: isDragging,
            isCompact: animTotal > 1,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
        // Width and X spring-animate when column assignment changes
        .frame(width: colWidth, height: CGFloat(event.durationMinutes) * Layout.ptPerMinute)
        .offset(x: xPos, y: yPos)   // Y is NEVER wrapped in withAnimation — follows finger directly
        .onAppear {
            animCol   = col
            animTotal = totalCols
        }
        // Stationary events spring into new column; dragged event snaps instantly
        // so the spring never fights the gesture tracking.
        .onChange(of: col) { _, newCol in
            if isDragging {
                animCol = newCol
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    animCol = newCol
                }
            }
        }
        .onChange(of: totalCols) { _, newTotal in
            if isDragging {
                animTotal = newTotal
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    animTotal = newTotal
                }
            }
        }
    }
}

// MARK: - EventBlock

struct EventBlock: View {
    @Binding var event: CalendarEvent
    let isDragging: Bool
    let isCompact: Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var lastSnapBoundary: Int = 0
    @State private var rubberX: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(event.color)
                .shadow(
                    color: isDragging ? .black.opacity(0.22) : .clear,
                    radius: 10, x: 0, y: 5
                )
            HStack(alignment: .top) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer()
                if !isCompact {
//                    Text(event.durationLabel)
//                        .font(.system(size: 12, weight: .medium))
//                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        // Rubber band: resists horizontal pull and springs back on release.
        // Suppressed when paired so split blocks don't push into each other.
        .offset(x: isCompact ? 0 : rubberX)
        .onChange(of: isCompact) { _, compact in
            if compact {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { rubberX = 0 }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    let dy = value.translation.height
                    let dx = value.translation.width
                    onDragChanged(dy)

                    // Horizontal rubber band: dampened resistance, caps at ±18pt
                    if !isCompact {
                        let rubber = dx / (1 + abs(dx) * 0.03)
                        rubberX = min(50, max(-50, rubber))
                    }

                    // Haptic every time we cross a 15-min snap boundary
                    let boundary = Int(dy / Layout.ptPerMinute) / Layout.snapInterval
                    if boundary != lastSnapBoundary {
                        lastSnapBoundary = boundary
                        impact()
                    }
                }
                .onEnded { value in
                    onDragEnded(value.translation.height)
                    lastSnapBoundary = 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                        rubberX = 0
                    }
                }
        )
    }
}

// MARK: - TimeRow

struct TimeRow: View {
    let label: String
    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "8d8d8d"))
                .frame(width: Layout.timeColumnWidth, alignment: .trailing)
                .padding(.trailing, 8)
            Rectangle()
                .fill(Color(hex: "e0e0e0"))
                .frame(height: 0.5)
        }
        .frame(height: Layout.slotHeight, alignment: .top)
    }
}

// MARK: - CurrentTimeLine

struct CurrentTimeLine: View {
    let minute: Int
    var body: some View {
        Canvas { ctx, size in
            let y     = CGFloat(minute) * Layout.ptPerMinute
            let color = GraphicsContext.Shading.color(Color(hex: "f31668"))
            let x0    = Layout.timeColumnWidth
            ctx.fill(
                Path(roundedRect: CGRect(x: x0, y: y - 6, width: 2, height: 12), cornerRadius: 1),
                with: color
            )
            ctx.fill(
                Path(roundedRect: CGRect(x: x0 + 4, y: y - 1, width: size.width - x0 - 20, height: 2), cornerRadius: 1),
                with: color
            )
        }
        .allowsHitTesting(false)
    }
}

#Preview { ContentView() }

#Playground { _ = 1 + 2 }
