// StatsView.swift
//
// At-a-glance focus stats: three big tiles (total / this week / streak),
// the year heatmap, and per-tag horizontal bars sorted descending.
// Empty state when no sessions and no dated pixels exist.

import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: BoulderStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0A0518), Color(hex: 0x1C1338)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            if hasAnyData {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        tileRow
                        divider
                        heatmapSection
                        divider
                        tagBarsSection
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: Empty state

    private var hasAnyData: Bool {
        if !store.model.sessions.isEmpty { return true }
        if store.model.pixels.contains(where: { $0.earnedAt != nil }) { return true }
        return false
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("📊").font(.system(size: 48))
            Text("No focus stats yet")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            Text("Your stats appear after your first focus session.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Tiles

    private var tileRow: some View {
        HStack(spacing: 12) {
            statTile(label: "TOTAL FOCUS",
                     value: formatHM(minutes: totalMinutes),
                     accent: Color(hex: 0xC147FF))
            statTile(label: "THIS WEEK",
                     value: formatHM(minutes: thisWeekMinutes),
                     accent: Color(hex: 0x47A0FF))
            statTile(label: "STREAK",
                     value: streakDays > 0 ? "\(streakDays) days" : "no streak yet",
                     accent: Color(hex: 0x2EE6A0))
        }
    }

    private func statTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(accent.opacity(0.9))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: Heatmap section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Activity")
            CalendarHeatmapView()
                .environmentObject(store)
        }
    }

    // MARK: Tag bars

    private var tagBarsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("By tag")
            let rows = perTagMinutes()
            if rows.isEmpty {
                Text("No tagged focus time yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let maxMins = rows.first?.minutes ?? 1
                VStack(spacing: 8) {
                    ForEach(rows.prefix(6), id: \.tag.id) { row in
                        tagBar(row: row, maxMinutes: maxMins)
                    }
                }
            }
        }
    }

    private func tagBar(row: TagRow, maxMinutes: Double) -> some View {
        let fraction = maxMinutes > 0 ? row.minutes / maxMinutes : 0
        return HStack(spacing: 10) {
            Text(row.tag.emoji)
                .font(.system(size: 16))
                .frame(width: 22)
            Text(row.tag.name)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(row.tag.chipColor.opacity(0.85))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text(formatHM(minutes: row.minutes))
                .font(.callout.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold).monospaced())
            .tracking(1.0)
            .foregroundStyle(.white.opacity(0.6))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: Data

    private struct TagRow {
        let tag: FocusTag
        let minutes: Double
    }

    /// Total minutes across all completed sessions. Falls back to
    /// pixel-derived minutes (5 min/pixel) if no sessions exist.
    private var totalMinutes: Double {
        let sessionMinutes = store.model.sessions
            .compactMap { s -> Double? in
                guard let ended = s.endedAt else { return nil }
                let secs = ended.timeIntervalSince(s.startedAt)
                return secs > 0 ? secs / 60.0 : nil
            }
            .reduce(0, +)
        if sessionMinutes > 0 { return sessionMinutes }
        let dated = store.model.pixels.filter { $0.earnedAt != nil }.count
        return Double(dated) * 5.0
    }

    private var thisWeekMinutes: Double {
        let cal = Calendar.current
        let now = Date()
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return store.model.sessions.reduce(0.0) { acc, session in
            guard let ended = session.endedAt else { return acc }
            // Overlap of (start..ended) with (weekStart..now+slack)
            let lo = max(session.startedAt, weekStart)
            let hi = min(ended, now)
            if hi <= lo { return acc }
            return acc + hi.timeIntervalSince(lo) / 60.0
        }
    }

    /// Consecutive days (going back from today) with at least 1 minute
    /// of focus. Stops counting at the first gap.
    private var streakDays: Int {
        let cal = Calendar.current
        let dayMinutes = perDayMinuteMap()
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        // Allow today to be 0-minute and still count yesterday's streak.
        if (dayMinutes[cursor] ?? 0) < 1 {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while (dayMinutes[cursor] ?? 0) >= 1 {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if streak > 3650 { break }  // sanity cap
        }
        return streak
    }

    private func perDayMinuteMap() -> [Date: Double] {
        let cal = Calendar.current
        var map: [Date: Double] = [:]
        let sessions = store.model.sessions.filter { $0.endedAt != nil }
        for session in sessions {
            guard let ended = session.endedAt else { continue }
            var cursor = session.startedAt
            while cursor < ended {
                let dayStart = cal.startOfDay(for: cursor)
                let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let segmentEnd = min(ended, nextDay)
                let secs = segmentEnd.timeIntervalSince(cursor)
                if secs > 0 { map[dayStart, default: 0] += secs / 60.0 }
                cursor = segmentEnd
            }
        }
        if map.isEmpty {
            // Fallback: pixels.
            for pixel in store.model.pixels {
                guard let earnedAt = pixel.earnedAt else { continue }
                let day = cal.startOfDay(for: earnedAt)
                map[day, default: 0] += 5.0
            }
        }
        return map
    }

    /// Minutes per tag, sorted descending. Uses sessions when available,
    /// falls back to pixel counts (5 min/pixel) otherwise.
    private func perTagMinutes() -> [TagRow] {
        var totals: [UUID: Double] = [:]
        let sessions = store.model.sessions.filter { $0.endedAt != nil }
        if !sessions.isEmpty {
            for s in sessions {
                guard let ended = s.endedAt else { continue }
                let mins = ended.timeIntervalSince(s.startedAt) / 60.0
                if mins > 0 { totals[s.tagID, default: 0] += mins }
            }
        } else {
            for p in store.model.pixels {
                guard let tagID = p.tagID else { continue }
                totals[tagID, default: 0] += 5.0
            }
        }
        let rows: [TagRow] = totals.compactMap { (id, mins) in
            guard let tag = store.tag(forID: id) else { return nil }
            return TagRow(tag: tag, minutes: mins)
        }
        return rows.sorted { $0.minutes > $1.minutes }
    }

    // MARK: Formatting

    private func formatHM(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m) m" }
        return "\(h) h \(m) m"
    }
}
