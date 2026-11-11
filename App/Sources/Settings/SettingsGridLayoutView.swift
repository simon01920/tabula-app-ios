// Settings → General → Grid layout (route `settings.grid-layout`; human decision 2026-11-01/02): one app-wide choice
// (`AppSettings.gridLayout`) between days in rows (the default, the Slovak aSc timetable) and periods in rows (the layout
// up to Phase 8). The Grid view and the Grid export page follow it. An inline `Picker` in a Form, as in Colors: system
// checkmarks, one row per option with a small schematic of the layout, its name and one line on what it looks like.
// The schematic is decorative (hidden from VoiceOver): the name and the line carry the meaning.
// APIs: Picker(.inline), Canvas, GraphicsContext.fill(_:with:), Path(roundedRect:cornerRadius:), AnyLayout
//       (HStackLayout / VStackLayout, iOS 16+).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsGridLayoutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker(selection: selection) {
                    ForEach(GridLayoutStyle.knownValues, id: \.self) { style in
                        GridLayoutOptionRow(style: style).tag(style)
                    }
                } label: {
                    Text("settings.gridLayout.title")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(model.isReadOnly)
            } footer: {
                Text("settings.gridLayout.footer")
            }
        }
        .readableWidth()   // one readable column on wide screens (ADAPTIVE_LAYOUT.md)
        .navigationTitle(Text("settings.gridLayout.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selection: Binding<GridLayoutStyle> {
        Binding(get: { model.settings.effectiveGridLayout }, set: { value in
            model.apply(.settings { $0.gridLayout = value })
        })
    }
}

/// The catalog keys of a layout's name and description.
enum GridLayoutStrings {
    static func nameKey(_ style: GridLayoutStyle) -> String {
        style.effective == .periodsAsRows ? "settings.gridLayout.periodsAsRows" : "settings.gridLayout.daysAsRows"
    }

    static func detailKey(_ style: GridLayoutStyle) -> String {
        style.effective == .periodsAsRows ? "settings.gridLayout.periodsAsRows.detail" : "settings.gridLayout.daysAsRows.detail"
    }
}

private struct GridLayoutOptionRow: View {
    let style: GridLayoutStyle
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the schematic sits above the text, so words never break (seen in CI at AX-XXXL).
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            GridLayoutSchematic(style: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(GridLayoutStrings.nameKey(style))).font(.body.weight(.semibold))
                Text(LocalizedStringKey(GridLayoutStrings.detailKey(style)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A thumbnail of the layout: a header band over the columns, a label gutter beside the rows, a few lesson cells (ink)
/// among quiet free cells, and one double lesson spanning two periods. Days in rows: 5 rows × 7 period columns;
/// periods in rows: 7 rows × 5 day columns.
private struct GridLayoutSchematic: View {
    let style: GridLayoutStyle
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 64

    var body: some View {
        let daysAsRows = style.effective == .daysAsRows
        let rows = daysAsRows ? 5 : 7
        let columns = daysAsRows ? 7 : 5
        Canvas { context, size in
            let gutter = size.width * 0.14, header = size.height * 0.14, gap: CGFloat = 1
            let cellWidth = (size.width - gutter) / CGFloat(columns)
            let cellHeight = (size.height - header) / CGFloat(rows)
            let label = GraphicsContext.Shading.color(Color.secondary.opacity(0.55))
            let free = GraphicsContext.Shading.color(Color.secondary.opacity(0.14))
            let lesson = GraphicsContext.Shading.color(Color.ink.opacity(0.7))
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x + gap, y: y + gap, width: max(0, w - 2 * gap), height: max(0, h - 2 * gap)),
                     cornerRadius: 1.5)
            }
            for column in 0..<columns {
                context.fill(rect(gutter + CGFloat(column) * cellWidth, 0, cellWidth, header), with: label)
            }
            for row in 0..<rows {
                context.fill(rect(0, header + CGFloat(row) * cellHeight, gutter, cellHeight), with: label)
                for column in 0..<columns {
                    // The double lesson (row 1, period 2–3 / period 2–3, day 1) is drawn once below.
                    let inDouble = daysAsRows ? (row == 1 && (column == 1 || column == 2))
                                              : (column == 1 && (row == 1 || row == 2))
                    if inDouble { continue }
                    let isLesson = (row * 3 + column * 2) % 5 != 0
                    context.fill(rect(gutter + CGFloat(column) * cellWidth, header + CGFloat(row) * cellHeight,
                                      cellWidth, cellHeight), with: isLesson ? lesson : free)
                }
            }
            let double = daysAsRows
                ? rect(gutter + cellWidth, header + cellHeight, 2 * cellWidth, cellHeight)
                : rect(gutter + cellWidth, header + cellHeight, cellWidth, 2 * cellHeight)
            context.fill(double, with: lesson)
        }
        .frame(width: min(width, 96), height: min(width, 96) * 0.7)
        .accessibilityHidden(true)
    }
}
