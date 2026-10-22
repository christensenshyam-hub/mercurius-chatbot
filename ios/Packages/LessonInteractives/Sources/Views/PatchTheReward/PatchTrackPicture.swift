import SwiftUI
import DesignSystem

/// Patch the Reward's track, seen from above, on night water (the same
/// night panel in the app's light and dark appearances, like Lesson 1.1's
/// map): the loop's channel with its chequered finish line and gates 1–3
/// (numbered discs on the island side, so the number never sits under the
/// boat), the side lagoon with its 3 star targets, and the boat.
///
/// - Playing (`live`): the boat moves along its planned route, with its
///   wake (lit on the Mac: the card's one motion set piece); a star goes
///   dim for the ticks it is gone.
/// - Still (a run's end, Reduce Motion, VoiceOver): the whole route as a
///   line with arrows, its legs numbered in order (1: the way in, 2: the
///   loop it then repeats), and the boat where the run ended.
///
/// One VoiceOver element: the track in words, then the route.
/// Decoration (light, glows) goes under Increase Contrast and Reduce
/// Transparency; nothing is told by colour alone (stars are star shapes,
/// gates are numbered, the line is chequered and says "finish").
struct PatchTrackPicture: View {
    /// The rule whose run is on the track (nil: the boat waits on the line).
    let rule: PatchRule?
    /// The race clock (60 for a still).
    let tick: Double
    let live: Bool
    /// The Mac: the boat's wake is lit.
    let lit: Bool

    @Environment(\.interactiveTheme) private var theme

    static let aspect: CGFloat = {
        let b = PatchTrack.bounds
        return CGFloat((b.maxX - b.minX) / (b.maxY - b.minY))
    }()

    var body: some View {
        let sky = NightSkyCard(increasedContrast: theme.increasedContrast, reduceTransparency: theme.reduceTransparency)
        let shape = RoundedRectangle(cornerRadius: theme.platform == .phone ? BrandRadius.lg : 14, style: .continuous)
        let run = rule.map(PatchTheRewardContent.run)
        let frame = run?.frame(at: tick)
        ZStack {
            if theme.lit {
                LinearGradient(colors: [sky.skyTop, sky.skyBottom], startPoint: .top, endPoint: .bottom)
                NightStarField(count: 24, brightness: 0.45)
            } else {
                sky.skyTop
            }
            Canvas { context, size in
                let map = TrackMap(size: size)
                drawWater(&context, map, sky)
                drawFinishLine(&context, map, sky)
                drawGates(&context, map, sky)
                // A still shows the track as set (every star there); a run
                // shows the stars it has hit going dim.
                drawStars(&context, map, sky, up: live ? frame?.starsUp : nil)
                if let run, let frame {
                    if live {
                        drawWake(&context, map, sky, frame)
                    } else {
                        drawRoute(&context, map, sky, run)
                    }
                    drawBoat(&context, map, sky, x: frame.x, y: frame.y, heading: frame.heading)
                } else {
                    let start = PatchTrack.waypoints[PatchTrack.start]
                    drawBoat(&context, map, sky, x: start.x, y: start.y, heading: -Double.pi / 2)
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.increasedContrast ? sky.hairline : sky.lumenWash(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PatchTheRewardCopy.pictureAccessibility(rule, playing: live))
        .accessibilityAddTraits(.isImage)
    }

    // MARK: Mapping metres to points

    struct TrackMap {
        let scale: CGFloat
        let originX: CGFloat
        let originY: CGFloat
        /// Glyphs grow a little on a wide picture (the Mac's).
        let glyph: CGFloat

        init(size: CGSize) {
            let b = PatchTrack.bounds
            scale = min(size.width / CGFloat(b.maxX - b.minX), size.height / CGFloat(b.maxY - b.minY))
            originX = CGFloat(b.minX)
            originY = CGFloat(b.minY)
            glyph = min(max(size.width / 360, 0.9), 1.35)
        }

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: (CGFloat(x) - originX) * scale, y: (CGFloat(y) - originY) * scale)
        }

        func point(_ waypoint: Int) -> CGPoint {
            let w = PatchTrack.waypoints[waypoint]
            return point(w.x, w.y)
        }

        func length(_ metres: Double) -> CGFloat { CGFloat(metres) * scale }
    }

    // MARK: Water

    private func waterColour(_ sky: NightSkyCard) -> Color { sky.raised }
    private func edgeColour(_ sky: NightSkyCard) -> Color {
        theme.increasedContrast ? sky.skyInk2 : sky.lumenWash(0.42)
    }

    /// The loop's centre line: two half-circles joined by straights.
    private func loopPath(_ map: TrackMap) -> Path {
        let west = PatchTrack.loopWestCentre, east = PatchTrack.loopEastCentre
        let r = map.length(PatchTrack.loopRadius)
        var path = Path()
        path.addArc(center: map.point(west.x, west.y), radius: r, startAngle: .degrees(90), endAngle: .degrees(270),
                    clockwise: false)
        path.addLine(to: map.point(east.x, east.y - PatchTrack.loopRadius))
        path.addArc(center: map.point(east.x, east.y), radius: r, startAngle: .degrees(270), endAngle: .degrees(90),
                    clockwise: false)
        path.closeSubpath()
        return path
    }

    private func lagoonPath(_ map: TrackMap) -> Path {
        let c = PatchTrack.lagoonCentre, r = PatchTrack.lagoonRadii
        let origin = map.point(c.x - r.x, c.y - r.y)
        return Path(ellipseIn: CGRect(x: origin.x, y: origin.y, width: map.length(r.x * 2), height: map.length(r.y * 2)))
    }

    private func mouthPath(_ map: TrackMap) -> Path {
        var path = Path()
        path.move(to: map.point(PatchTrack.lagoonTurnOff))
        path.addLine(to: map.point(PatchTrack.mouth))
        path.addLine(to: map.point(PatchTrack.lagoonTurnOff + 1))
        return path
    }

    private func drawWater(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard) {
        let channel = map.length(PatchTrack.channelWidth)
        let edge = edgeColour(sky)
        let water = waterColour(sky)
        // Edges first (a little wider), then the water over them: the
        // water is opaque, so only a rim of edge shows.
        context.stroke(loopPath(map), with: .color(edge), style: StrokeStyle(lineWidth: channel + 2, lineJoin: .round))
        context.stroke(mouthPath(map), with: .color(edge), style: StrokeStyle(lineWidth: channel + 2, lineCap: .round,
                                                                               lineJoin: .round))
        context.fill(Path(ellipseIn: lagoonPath(map).boundingRect.insetBy(dx: -1, dy: -1)), with: .color(edge))
        context.fill(lagoonPath(map), with: .color(water))
        context.stroke(loopPath(map), with: .color(water), style: StrokeStyle(lineWidth: channel, lineJoin: .round))
        context.stroke(mouthPath(map), with: .color(water), style: StrokeStyle(lineWidth: channel, lineCap: .round,
                                                                                lineJoin: .round))
    }

    // MARK: The finish line and the gates

    private func drawFinishLine(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard) {
        let centre = map.point(PatchTrack.finishLine.x, PatchTrack.finishLine.y)
        let width = map.length(PatchTrack.channelWidth) + 2
        let square = max(2.5, (width / 6).rounded(.down))
        let columns = Int((width / square).rounded(.down))
        let left = centre.x - CGFloat(columns) * square / 2
        for row in 0..<2 {
            for column in 0..<columns {
                let light = (row + column) % 2 == 0
                let rect = CGRect(x: left + CGFloat(column) * square, y: centre.y - square + CGFloat(row) * square,
                                  width: square, height: square)
                context.fill(Path(rect), with: .color(light ? sky.skyInk : sky.skyBottom))
            }
        }
        // "finish", on the island beside the line.
        let label = context.resolve(Text(PatchTheRewardCopy.finishMark)
            .font(.system(size: 11 * map.glyph, weight: .semibold, design: .rounded))
            .foregroundStyle(sky.skyInk))
        let x = centre.x + map.length(PatchTrack.channelWidth / 2) + 4
        context.draw(label, at: CGPoint(x: x, y: centre.y), anchor: .leading)
    }

    private func drawGates(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard) {
        let half = map.length(PatchTrack.channelWidth / 2) + 1
        let disc = 17 * map.glyph
        for (waypoint, number) in PatchTrack.gates.sorted(by: { $0.value < $1.value }) {
            let p = map.point(waypoint)
            // The gate: a bar across the channel (the loop's straights run
            // left-right, so it's vertical).
            var bar = Path()
            bar.move(to: CGPoint(x: p.x, y: p.y - half))
            bar.addLine(to: CGPoint(x: p.x, y: p.y + half))
            context.stroke(bar, with: .color(sky.skyLink), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 2]))
            // Its number, on the island side.
            let inward: CGFloat = PatchTrack.waypoints[waypoint].y < PatchTrack.loopWestCentre.y ? 1 : -1
            let centre = CGPoint(x: p.x, y: p.y + inward * (half + disc / 2 + 2))
            let rect = CGRect(x: centre.x - disc / 2, y: centre.y - disc / 2, width: disc, height: disc)
            context.fill(Path(ellipseIn: rect), with: .color(sky.prominent))
            if theme.increasedContrast {
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1)
            }
            let text = context.resolve(Text("\(number)")
                .font(.system(size: 11 * map.glyph, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white))
            context.draw(text, at: centre, anchor: .center)
        }
    }

    // MARK: Stars

    private func drawStars(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard, up: [Bool]?) {
        let radius = 8 * map.glyph
        for (index, waypoint) in PatchTrack.stars.enumerated() {
            let p = map.point(waypoint)
            let star = Self.starPath(centre: p, radius: radius)
            let isUp = up?[index] ?? true
            if isUp {
                if theme.lit {
                    var glow = context
                    glow.addFilter(.blur(radius: 4))
                    glow.fill(star, with: .color(sky.lumen.opacity(0.8)))
                }
                context.fill(star, with: .color(sky.skyInk))
            } else {
                // Gone for a few ticks: an outline where it comes back.
                context.stroke(star, with: .color(sky.skyInk2.opacity(theme.increasedContrast ? 1 : 0.55)),
                               style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
    }

    static func starPath(centre: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for index in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let r = index % 2 == 0 ? radius : radius * 0.45
            let point = CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: The route (still) and the wake (playing)

    private func drawRoute(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard, _ run: PatchRun) {
        let legs = run.legs.drawn
        for (number, leg) in legs.enumerated() {
            let pairs = Array(zip(leg, leg.dropFirst()))
            var path = Path()
            var arrows: [(CGPoint, CGFloat)] = []
            for (from, to) in pairs {
                // A stretch the leg also runs backwards (the line) is drawn
                // as two lanes, one each way.
                let both = pairs.contains { $0.0 == to && $0.1 == from }
                let offset: CGFloat = both ? 2.5 : 0
                let a = map.point(from), b = map.point(to)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let shift = CGPoint(x: -sin(angle) * offset, y: cos(angle) * offset)
                let start = CGPoint(x: a.x + shift.x, y: a.y + shift.y)
                let end = CGPoint(x: b.x + shift.x, y: b.y + shift.y)
                path.move(to: start)
                path.addLine(to: end)
                arrows.append((CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), angle))
            }
            context.stroke(path, with: .color(sky.skyLink),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // An arrow on every few stretches (each one on a short leg).
            let every = pairs.count <= 4 ? 1 : 3
            for (index, arrow) in arrows.enumerated() where index % every == every / 2 {
                context.fill(Self.arrowHead(at: arrow.0, angle: arrow.1, size: 5 * map.glyph), with: .color(sky.skyLink))
            }
            // A stretch run both ways (rule A, over the line) is shorter
            // than the boat, which ends the run on it: a double-headed
            // arrow beside it says "back and forth here".
            if let shuttle = pairs.first(where: { pair in pairs.contains { $0.0 == pair.1 && $0.1 == pair.0 } }) {
                drawShuttle(&context, map, sky, from: shuttle.0, to: shuttle.1)
            }
            // With a way in and a loop, the legs are numbered in order, by
            // each leg's first stretch: 1 on the way in (on the island
            // side, above the line's "finish"), 2 on the loop (outside it).
            guard legs.count > 1, !arrows.isEmpty else { continue }
            let anchor = arrows[0]
            let distance = 9 * map.glyph + 4
            let normal = CGPoint(x: -sin(anchor.1) * distance, y: cos(anchor.1) * distance)
            let one = CGPoint(x: anchor.0.x + normal.x, y: anchor.0.y + normal.y)
            let other = CGPoint(x: anchor.0.x - normal.x, y: anchor.0.y - normal.y)
            let points = leg.map { map.point($0) }
            let centroid = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                   y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            let middle = CGPoint(x: map.length(PatchTrack.bounds.maxX - PatchTrack.bounds.minX) / 2,
                                 y: map.length(PatchTrack.bounds.maxY - PatchTrack.bounds.minY) / 2)
            func gap(_ p: CGPoint, _ q: CGPoint) -> CGFloat { hypot(p.x - q.x, p.y - q.y) }
            let isLoop = leg.first == leg.last
            let place = isLoop
                ? (gap(one, centroid) >= gap(other, centroid) ? one : other)
                : (gap(one, middle) <= gap(other, middle) ? one : other)
            drawBadge(&context, map, sky, number + 1, near: place)
        }
    }

    private func drawBadge(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard, _ number: Int,
                           near point: CGPoint) {
        // A rounded square (the gates are discs), white with dark words.
        let size = 15 * map.glyph
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(sky.skyInk))
        let text = context.resolve(Text("\(number)")
            .font(.system(size: 10 * map.glyph, weight: .heavy, design: .rounded))
            .foregroundStyle(sky.skyBottom))
        context.draw(text, at: point, anchor: .center)
    }

    /// A double-headed arrow along the stretch `from`–`to`, a little longer
    /// than it, beside it on the side away from the loop's middle (the
    /// boat's hull, where the run ends, covers the stretch itself).
    private func drawShuttle(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard, from: Int,
                             to: Int) {
        let a = map.point(from), b = map.point(to)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let middle = map.point((PatchTrack.loopWestCentre.x + PatchTrack.loopEastCentre.x) / 2,
                               PatchTrack.loopWestCentre.y)
        var normal = CGPoint(x: -sin(angle), y: cos(angle))
        if normal.x * (middle.x - mid.x) + normal.y * (middle.y - mid.y) > 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }
        // Clear of the hull (half its beam) by a small gap.
        let distance = 4 * map.glyph + 3
        let centre = CGPoint(x: mid.x + normal.x * distance, y: mid.y + normal.y * distance)
        let half = max(hypot(b.x - a.x, b.y - a.y) * 0.8, 9 * map.glyph + 4)
        let along = CGPoint(x: cos(angle) * half, y: sin(angle) * half)
        let start = CGPoint(x: centre.x - along.x, y: centre.y - along.y)
        let end = CGPoint(x: centre.x + along.x, y: centre.y + along.y)
        var shaft = Path()
        shaft.move(to: start)
        shaft.addLine(to: end)
        context.stroke(shaft, with: .color(sky.skyLink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        let size = 5 * map.glyph
        context.fill(Self.arrowHead(at: end, angle: angle, size: size), with: .color(sky.skyLink))
        context.fill(Self.arrowHead(at: start, angle: angle + CGFloat.pi, size: size), with: .color(sky.skyLink))
    }

    static func arrowHead(at point: CGPoint, angle: CGFloat, size: CGFloat) -> Path {
        var path = Path()
        let tip = CGPoint(x: point.x + cos(angle) * size, y: point.y + sin(angle) * size)
        let back = angle + CGFloat.pi
        let left = CGPoint(x: point.x + cos(back + 0.6) * size, y: point.y + sin(back + 0.6) * size)
        let right = CGPoint(x: point.x + cos(back - 0.6) * size, y: point.y + sin(back - 0.6) * size)
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    private func drawWake(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard, _ frame: PatchFrame) {
        let points = frame.wake.map { map.point($0.x, $0.y) }
        guard points.count >= 2 else { return }
        var path = Path()
        path.addLines(points)
        if lit && theme.lit {
            var glow = context
            glow.addFilter(.blur(radius: 5))
            glow.stroke(path, with: .color(sky.lumen.opacity(0.9)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        // Older stretches fainter.
        for index in 1..<points.count {
            var piece = Path()
            piece.move(to: points[index - 1])
            piece.addLine(to: points[index])
            let alpha = 0.25 + 0.75 * Double(index) / Double(points.count - 1)
            context.stroke(piece, with: .color(sky.skyLink.opacity(theme.increasedContrast ? 1 : alpha)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    // MARK: The boat

    private func drawBoat(_ context: inout GraphicsContext, _ map: TrackMap, _ sky: NightSkyCard,
                          x: Double, y: Double, heading: Double) {
        let p = map.point(x, y)
        let length = 18 * map.glyph
        let beam = 8 * map.glyph
        var hull = Path()
        hull.move(to: CGPoint(x: length / 2, y: 0))
        hull.addQuadCurve(to: CGPoint(x: -length / 2, y: beam / 2), control: CGPoint(x: length / 6, y: beam / 2))
        hull.addLine(to: CGPoint(x: -length / 2, y: -beam / 2))
        hull.addQuadCurve(to: CGPoint(x: length / 2, y: 0), control: CGPoint(x: length / 6, y: -beam / 2))
        hull.closeSubpath()
        var boat = context
        boat.translateBy(x: p.x, y: p.y)
        boat.rotate(by: .radians(heading))
        if lit && theme.lit {
            var glow = boat
            glow.addFilter(.blur(radius: 4))
            glow.fill(hull, with: .color(sky.lumen))
        }
        // White, so it reads on the night water; its outline is the lit
        // pill's indigo.
        boat.fill(hull, with: .color(sky.skyInk))
        boat.stroke(hull, with: .color(sky.prominent), lineWidth: 1.5)
        // A dot at the bow: which way it points, without colour.
        let bow = Path(ellipseIn: CGRect(x: length / 2 - 6 * map.glyph, y: -1.5 * map.glyph, width: 3 * map.glyph,
                                         height: 3 * map.glyph))
        boat.fill(bow, with: .color(sky.prominent))
    }
}
