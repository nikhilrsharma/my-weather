import SwiftUI
import CoreText

/// One shared measurement for the entire city list, not one height per label or
/// city. Long/mixed labels and larger text expand every bar equally.
struct WeatherBarMetrics {
    let width: CGFloat
    let height: CGFloat
    let timeWidth: CGFloat
    let labelWidth: CGFloat
    let fontSize: CGFloat
    let gap: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let dotDiameter: CGFloat
    let stacksText: Bool

    init(blocks: [DayWeatherBlock], width: CGFloat, fontSize: CGFloat) {
        self.width = width
        self.fontSize = fontSize
        let scale = fontSize / 11
        // Grow text and bar dimensions with Dynamic Type, not decorative gaps.
        // Keeping these compact leaves room for whole words at accessibility sizes.
        gap = 7
        leadingInset = 8
        trailingInset = 10
        dotDiameter = 9
        let timeFont = CTFontCreateWithName("Verdana-Bold" as CFString, fontSize, nil)
        let labelFont = CTFontCreateWithName("Verdana" as CFString, fontSize, nil)
        let available = max(1, width - leadingInset - trailingInset - dotDiameter - 2 * gap)
        let widestTime = blocks.map { Self.size($0.timeLabel, font: timeFont, width: 10_000).width }.max() ?? 0
        let horizontalTimeWidth = min(max(44 * scale, ceil(widestTime)), available * 0.48)
        let horizontalLabelWidth = max(1, available - horizontalTimeWidth)
        let widestWord = blocks.flatMap { $0.label.split(whereSeparator: { $0.isWhitespace || $0 == "/" }) }
            .map { Self.size(String($0), font: labelFont, width: 10_000).width }.max() ?? 0
        // At very large text sizes, use the full bar for each line before
        // breaking a word or squeezing the time into an unreadable column.
        let shouldStackText = ceil(widestTime) > horizontalTimeWidth || ceil(widestWord) > horizontalLabelWidth
        stacksText = shouldStackText
        let measuredTimeWidth = shouldStackText ? available + gap : horizontalTimeWidth
        let measuredLabelWidth = shouldStackText ? available + gap : horizontalLabelWidth
        timeWidth = measuredTimeWidth
        labelWidth = measuredLabelWidth
        let textGap = gap
        let contentHeight = blocks.map {
            let timeHeight = Self.size($0.timeLabel, font: timeFont, width: measuredTimeWidth).height
            let labelHeight = Self.size($0.label, font: labelFont, width: measuredLabelWidth).height
            return shouldStackText ? timeHeight + textGap + labelHeight : max(timeHeight, labelHeight)
        }.max() ?? 0
        height = max(28 * scale, ceil(contentHeight) + 12 * scale)
    }

    private static func size(_ text: String, font: CTFont, width: CGFloat) -> CGSize {
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
    }

    static func naturalTextWidth(_ strings: [String], fontSize: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName("Verdana" as CFString, fontSize, nil)
        return ceil(strings.map { size($0, font: font, width: 10_000).width }.max() ?? 0)
    }
}

/// Shared by every city. Reserve only the width the weather text needs, then
/// give the remaining row to the timeline. Stack before either column is cramped.
struct CityWeatherSizing {
    static let spacing: CGFloat = 16
    let rowWidth: CGFloat
    let preferredTextWidth: CGFloat
    let minimumTimelineWidth: CGFloat
    let forceStacked: Bool

    var isStacked: Bool {
        forceStacked || rowWidth < preferredTextWidth + minimumTimelineWidth + Self.spacing
    }

    var textWidth: CGFloat { isStacked ? rowWidth : preferredTextWidth }
    var timelineWidth: CGFloat {
        isStacked ? rowWidth : rowWidth - preferredTextWidth - Self.spacing
    }

    func fitting(_ width: CGFloat) -> Self {
        Self(rowWidth: max(1, width), preferredTextWidth: preferredTextWidth,
             minimumTimelineWidth: minimumTimelineWidth, forceStacked: forceStacked)
    }
}

/// A lightweight native view: no downloaded images, web content, or extra requests.
struct DayTimelineView: View {
    let timeline: DayTimeline
    let now: Date
    let metrics: WeatherBarMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(timeline.dateLabel) · Local")
                .font(.weatherFootnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
                .accessibilityLabel("Daily weather for \(timeline.dateLabel), times in \(timeline.timezone)")

            ForEach(timeline.blocks) { block in
                Group {
                    if metrics.stacksText {
                        VStack(alignment: .leading, spacing: metrics.gap) {
                            barTime(block)
                            barLabel(block)
                        }
                    } else {
                        HStack(alignment: .center, spacing: metrics.gap) {
                            barTime(block)
                            barLabel(block)
                        }
                    }
                }
                .font(.custom("Verdana", fixedSize: metrics.fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(block.usesDarkText ? Color(red: 0.10, green: 0.09, blue: 0.07) : .white)
                .padding(.leading, metrics.leadingInset)
                .padding(.trailing, metrics.trailingInset + metrics.dotDiameter + metrics.gap)
                .frame(width: metrics.width, height: metrics.height, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: block.colors, startPoint: .leading, endPoint: .trailing))
                }
                .overlay(alignment: .trailing) {
                    if timeline.currentBlockID(at: now) == block.id {
                        Circle()
                            .fill(Color(red: 1, green: 0.23, blue: 0.19))
                            .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
                            .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
                            .padding(.trailing, metrics.trailingInset)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(block.accessibleTimeLabel), \(block.label)\(timeline.currentBlockID(at: now) == block.id ? ", Now" : "")")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func barTime(_ block: DayWeatherBlock) -> some View {
        Text(block.timeLabel)
            .monospacedDigit()
            .fontWeight(.bold)
            .frame(width: metrics.timeWidth, alignment: .leading)
    }

    private func barLabel(_ block: DayWeatherBlock) -> some View {
        Text(block.label)
            .frame(width: metrics.labelWidth, alignment: .leading)
    }
}

private extension DayWeatherBlock {
    var usesDarkText: Bool {
        !categories.isEmpty && categories.allSatisfy { $0 == .sunny || $0 == .partlyCloudy }
    }

    var colors: [Color] {
        let values = categories.flatMap { $0.palette(usesDarkText: usesDarkText) }
        return (values.isEmpty ? [0x424247] : values).map { value in
            Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        }
    }
}

/// Uses the right-hand column when it fits, and stacks for small windows or
/// larger Dynamic Type. Both columns are measured at their actual widths.
struct CityWeatherLayout: Layout {
    let sizing: CityWeatherSizing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fit = sizing.fitting(proposal.width ?? sizing.rowWidth)
        let text = subviews[0].sizeThatFits(.init(width: fit.textWidth, height: nil))
        let timeline = subviews[1].sizeThatFits(.init(width: fit.timelineWidth, height: nil))
        return CGSize(width: fit.rowWidth, height: fit.isStacked
            ? text.height + CityWeatherSizing.spacing + timeline.height : max(text.height, timeline.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fit = sizing.fitting(bounds.width)
        let textSize = subviews[0].sizeThatFits(.init(width: fit.textWidth, height: nil))
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: .init(width: fit.textWidth, height: textSize.height)
        )
        let chartSize = subviews[1].sizeThatFits(.init(width: fit.timelineWidth, height: nil))
        subviews[1].place(
            at: CGPoint(
                x: fit.isStacked ? bounds.minX : bounds.maxX - fit.timelineWidth,
                y: fit.isStacked ? bounds.minY + textSize.height + CityWeatherSizing.spacing : bounds.minY
            ),
            proposal: .init(width: fit.timelineWidth, height: chartSize.height)
        )
    }
}
