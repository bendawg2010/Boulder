// CalendarHeatmapView.swift
//
// GitHub-style year heatmap of focused minutes. 7 rows (Sun-Sat),
// 52-53 columns (weeks), most recent week on the right.
// Cell intensity is bucketed into 5 levels (none / light / mid /
// heavy / max), and the cell color blends from a faint white toward
// the day's DOMINANT-tag chipColor at max.

import SwiftUI

struct CalendarHeatmapView: View {
    @EnvironmentObject var store: BoulderStore

    /// One day of aggregate data.
    private struct DayBucket {
        let date: Date          // startOfDay
        let minutes: Double
        let pixelCount: Int
        let dominantTag: FocusTag?
    }

    // MARK: Layout knobs

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3
    private let weeks: Int = 53

    var body: some View {
        let buckets = computeBuckets()
        let totalMinutes = buckets.values.reduce(0.0) { $0 + $1.minutes }
        let totalDays = buckets.values.filter { $0.minutes > 0 }.count

        VStack(alignment: .leading, spacing: 8) {
            monthLabels(buckets: buckets)
            grid(buckets: buckets)
            legendRow(totalMinutes: totalMinutes, totalDays: totalDays)
        }
    }

    // MARK: Grid

    private func grid(buckets: [Date: DayBucket]) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anchor: the most recent Saturday (right edge column's bottom row).
        // Weekday: Sun=1...Sat=7. So Sat is weekday 7.
        let todayWeekday = cal.component(.weekday, from: today) // 1-7
        let daysUntilSat = (7 - todayWeekday) % 7
        let lastDayOfGrid = cal.date(byAdding: .day, value: daysUntilSat, to: today) ?? today

        // Build columns: each column is a week (Sun..Sat).
        // Right-most column ends on lastDayOfGrid (the upcoming Saturday).
        return HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(0..<weeks, id: \.self) { weekIdx in
                let columnEnd = cal.date(byAdding: .day, value: -7 * (weeks - 1 - weekIdx), to: lastDayOfGrid) ?? lastDayOfGrid
                let columnStart = cal.date(byAdding: .day, value: -6, to: columnEnd) ?? columnEnd
                VStack(spacing: cellSpacing) {
                    ForEach(0..<7, id: \.self) { row in
                        let day = cal.date(byAdding: .day, value: row, to: columnStart) ?? columnStart
                        let dayStart = cal.startOfDay(for: day)
                        cell(for: dayStart, bucket: buckets[dayStart], isFuture: dayStart > today)
                    }
                }
            }
        }
    }

    private func cell(for date: Date, bucket: DayBucket?, isFuture: Bool) -> some View {
        let minutes = bucket?.minutes ?? 0
        let level = intensityLevel(minutes: minutes)
        let baseChip = bucket?.dominantTag?.chipColor ?? Color(hex: 0xC147FF)
        let fill: Color = {
            if isFuture { return Color.white.opacity(0.02) }
            if level == 0 { return Color.white.opacity(0.04) }
            // Blend from a dim base (level 1) toward the tag chip (level 4)
            let t = Double(level) / 4.0
            return Color.white.opacity(0.06 * (1.0 - t))
                .opacity(1) // no-op; we'll just use baseChip with varying opacity
                .overlayProxy(baseChip.opacity(0.25 + 0.65 * t))
        }()

        let tooltip = tooltipText(date: date, bucket: bucket, isFuture: isFuture)
        return HeatmapCell(
            fill: fill,
            size: cellSize,
            tooltip: tooltip
        )
    }

    private func tooltipText(date: Date, bucket: DayBucket?, isFuture: Bool) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        let dateStr = df.string(from: date)
        if isFuture { return "\(dateStr) · upcoming" }
        guard let b = bucket, b.minutes > 0 else { return "\(dateStr) · no focus" }
        let mins = Int(b.minutes.rounded())
        let tagName = b.dominantTag?.name ?? "—"
        return "\(dateStr) · \(mins)m · \(b.pixelCount) px · \(tagName)"
    }

    // MARK: Month labels

    private func monthLabels(buckets: [Date: DayBucket]) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayWeekday = cal.component(.weekday, from: today)
        let daysUntilSat = (7 - todayWeekday) % 7
        let lastDayOfGrid = cal.date(byAdding: .day, value: daysUntilSat, to: today) ?? today

        // Determine month at the TOP of each week column. Show a label
        // for the first column of each month (when the month changes
        // moving left→right).
        var lastMonth = -1
        var labels: [(column: Int, label: String)] = []
        let mf = DateFormatter()
        mf.dateFormat = "LLL"
        for weekIdx in 0..<weeks {
            let columnEnd = cal.date(byAdding: .day, value: -7 * (weeks - 1 - weekIdx), to: lastDayOfGrid) ?? lastDayOfGrid
            let columnStart = cal.date(byAdding: .day, value: -6, to: columnEnd) ?? columnEnd
            let m = cal.component(.month, from: columnStart)
            if m != lastMonth {
                lastMonth = m
                labels.append((weekIdx, mf.string(from: columnStart)))
            }
        }

        let columnStride = cellSize + cellSpacing
        return ZStack(alignment: .topLeading) {
            ForEach(0..<labels.count, id: \.self) { i in
                Text(labels[i].label)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(labels[i].column) * columnStride, y: 0)
            }
        }
        .frame(height: 14, alignment: .leading)
    }

    // MARK: Legend

    private func legendRow(totalMinutes: Double, totalDays: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { lvl in
                    let t = Double(lvl) / 4.0
                    let base = Color(hex: 0xC147FF)
                    let fill: Color = lvl == 0
                        ? Color.white.opacity(0.06)
                        : base.opacity(0.25 + 0.65 * t)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fill)
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("\(Int(totalMinutes.rounded())) minutes across \(totalDays) days")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Intensity

    private func intensityLevel(minutes: Double) -> Int {
        switch minutes {
        case ..<1:      return 0
        case ..<15:     return 1
        case ..<45:     return 2
        case ..<120:    return 3
        default:        return 4
        }
    }

    // MARK: Data aggregation

    private func computeBuckets() -> [Date: DayBucket] {
        let cal = Calendar.current
        let sessions = store.model.sessions.filter { $0.endedAt != nil }

        // Walk sessions, distributing minute-overlap into per-day buckets.
        var perDayMinutes: [Date: Double] = [:]
        var perDayPixelTagCounts: [Date: [UUID?: Int]] = [:]
        var perDayPixelCount: [Date: Int] = [:]

        for session in sessions {
            guard let ended = session.endedAt else { continue }
            let start = session.startedAt
            if ended <= start { continue }

            // Distribute minutes across each calendar day the session spans.
            var cursor = start
            while cursor < ended {
                let dayStart = cal.startOfDay(for: cursor)
                let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let segmentEnd = min(ended, nextDay)
                let secs = segmentEnd.timeIntervalSince(cursor)
                if secs > 0 {
                    perDayMinutes[dayStart, default: 0] += secs / 60.0
                }
                cursor = segmentEnd
            }
        }

        // Aggregate pixels by their earnedAt day (for "dominant tag" and pixel count).
        for pixel in store.model.pixels {
            guard let earnedAt = pixel.earnedAt else { continue }
            let dayStart = cal.startOfDay(for: earnedAt)
            perDayPixelCount[dayStart, default: 0] += 1
            perDayPixelTagCounts[dayStart, default: [:]][pixel.tagID, default: 0] += 1
        }

        // Fallback: if there are no sessions at all but we have pixels with
        // earnedAt, derive minutes from pixel counts (5 minutes per pixel).
        if perDayMinutes.isEmpty {
            for (day, count) in perDayPixelCount {
                perDayMinutes[day] = Double(count) * 5.0
            }
        }

        // Build bucket map.
        var result: [Date: DayBucket] = [:]
        let allKeys = Set(perDayMinutes.keys).union(perDayPixelCount.keys)
        for key in allKeys {
            let mins = perDayMinutes[key] ?? 0
            let pxCount = perDayPixelCount[key] ?? 0
            let dominantTagID = perDayPixelTagCounts[key]?
                .max(by: { $0.value < $1.value })?
                .key
            let dominantTag = store.tag(forID: dominantTagID ?? nil)
            result[key] = DayBucket(
                date: key,
                minutes: mins,
                pixelCount: pxCount,
                dominantTag: dominantTag
            )
        }
        return result
    }
}

// MARK: - Cell view (hover scale)

private struct HeatmapCell: View {
    let fill: Color
    let size: CGFloat
    let tooltip: String
    @State private var hovered: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: size, height: size)
            .scaleEffect(hovered ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .help(tooltip)
            .onHover { hovered = $0 }
    }
}

// MARK: - Color blend helper

private extension Color {
    /// Returns the supplied overlay color (we only need it for the cell
    /// — there is no real "blend" in SwiftUI Color, so we just hand back
    /// the overlay; the caller is composing a tag chip color at a target
    /// opacity already, which gives us the perceived intensity ramp.
    func overlayProxy(_ other: Color) -> Color { other }
}
