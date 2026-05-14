// BoulderWidget.swift
//
// WidgetKit widget that displays the user's growing Boulder.
// Reads BoulderModel from the shared App Group container written by
// the main app's Persistence layer. Refreshes every 15 minutes.

import WidgetKit
import SwiftUI

// MARK: - App Group identifier

private let appGroupID = "group.com.benburnette.Boulder"

// MARK: - Timeline entry

struct BoulderEntry: TimelineEntry {
    let date: Date
    let pixels: [BoulderPixel]
    let tags: [FocusTag]
}

// MARK: - Timeline provider

struct BoulderTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoulderEntry {
        BoulderEntry(date: Date(), pixels: [], tags: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (BoulderEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoulderEntry>) -> Void) {
        let entry = loadEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [entry], policy: .after(refresh))
        completion(timeline)
    }

    private func loadEntry() -> BoulderEntry {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID),
            let data = try? Data(contentsOf: container.appendingPathComponent("widget-state.json")),
            let model = try? JSONDecoder().decode(BoulderModel.self, from: data)
        else {
            return BoulderEntry(date: Date(), pixels: [], tags: [])
        }
        return BoulderEntry(date: Date(), pixels: model.pixels, tags: model.tags)
    }
}

// MARK: - Widget definition

struct BoulderWidget: Widget {
    let kind: String = "BoulderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoulderTimelineProvider()) { entry in
            BoulderWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Boulder")
        .description("Your growing focus boulder.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry view

struct BoulderWidgetEntryView: View {
    let entry: BoulderEntry

    @Environment(\.widgetFamily) private var family

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.42, blue: 0.42),
                Color(red: 0.757, green: 0.278, blue: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            gradient
            content
        }
        .containerBackground(gradient, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if entry.pixels.isEmpty {
            emptyState
        } else {
            filledState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("🪨")
                .font(.system(size: family == .systemSmall ? 32 : 44))
            Text("Start focusing\nin Boulder")
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(8)
    }

    private var filledState: some View {
        VStack(spacing: 4) {
            if family != .systemSmall {
                Text("🪨 Boulder")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }

            BoulderRenderer(
                pixels: entry.pixels,
                paletteFor: { pixel in
                    if let tag = entry.tags.first(where: { $0.id == pixel.tagID }) {
                        return tag.palette
                    }
                    if let t = pixel.legacyType { return t.palette }
                    return BoulderRenderer.fallbackPalette
                },
                autoScale: true,
                groundLine: false,
                shadowBelow: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("\(entry.pixels.count) px")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.bottom, family == .systemSmall ? 6 : 10)
        }
    }
}
