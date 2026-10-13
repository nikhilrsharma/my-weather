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
        let measuredTimeWidth = min(max(44 * scale, ceil(widestTime)), available * 0.48)
        let measuredLabelWidth = max(1, available - measuredTimeWidth)
        timeWidth = measuredTimeWidth
        labelWidth = measuredLabelWidth
        let contentHeight = blocks.map {
            max(Self.size($0.timeLabel, font: timeFont, width: measuredTimeWidth).height,
                Self.size($0.label, font: labelFont, width: measuredLabelWidth).height)
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
                HStack(alignment: .center, spacing: metrics.gap) {
                    Text(block.timeLabel)
                        .monospacedDigit()
                        .fontWeight(.bold)
                        .frame(width: metrics.timeWidth, alignment: .leading)

                    Text(block.label)
                        .frame(width: metrics.labelWidth, alignment: .leading)
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
}

private extension DayWeatherBlock {
    var usesDarkText: Bool {
        !categories.isEmpty && categories.allSatisfy { $0 == .sunny || $0 == .partlyCloudy }
    }

    var colors: [Color] {
        let values = categories.flatMap { category -> [UInt32] in
            switch category {
            case .night: [0x111A32]
            case .dawn: [0x111A32, 0x624573, 0x875520]
            case .sunny: [usesDarkText ? 0xDFA52F : 0x875520]
            case .partlyCloudy:
                usesDarkText ? [0xDFA52F, 0xA9AFBB] : [0x875520, 0x505867]
            case .cloudy: [0x505867]
            case .lowLight: [0x875520, 0x7B4932, 0x624573]
            case .dusk: [0x624573, 0x3C345D, 0x111A32]
            case .fog: [0x505867, 0x445860]
            case .drizzle: [0x505867, 0x355F78]
            case .rain: [0x505867, 0x315C82]
            case .ice: [0x415B72, 0x4D4677]
            case .snow: [0x3B6175, 0x51546E]
            case .storms: [0x4B4266, 0x342746]
            case .nightFog: [0x111A32, 0x3D4954]
            case .nightDrizzle, .nightRain: [0x111A32, 0x264767]
            case .nightIce, .nightSnow: [0x111A32, 0x3E4664]
            case .nightStorms: [0x111A32, 0x342746]
            case .unknown: [0x424247]
            }
        }
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
    let timelineWidth: CGFloat
    let stackVertically: Bool
    private let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let stacked = stackVertically || width < timelineWidth + 120 + spacing
        let text = subviews[0].sizeThatFits(.init(width: stacked ? width : width - timelineWidth - spacing, height: nil))
        let timeline = subviews[1].sizeThatFits(.init(width: min(width, timelineWidth), height: nil))
        return CGSize(width: width, height: stacked ? text.height + spacing + timeline.height : max(text.height, timeline.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let stacked = stackVertically || bounds.width < timelineWidth + 120 + spacing
        let textWidth = stacked ? bounds.width : bounds.width - timelineWidth - spacing
        let textSize = subviews[0].sizeThatFits(.init(width: textWidth, height: nil))
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: .init(width: textWidth, height: textSize.height)
        )
        let chartWidth = min(bounds.width, timelineWidth)
        let chartSize = subviews[1].sizeThatFits(.init(width: chartWidth, height: nil))
        subviews[1].place(
            at: CGPoint(
                x: stacked ? bounds.minX : bounds.maxX - chartWidth,
                y: stacked ? bounds.minY + textSize.height + spacing : bounds.minY
            ),
            proposal: .init(width: chartWidth, height: chartSize.height)
        )
    }
}
