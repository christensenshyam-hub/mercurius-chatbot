import Foundation

// Delete the Gender Box (U3L1, "AI in hiring and employment"; SLATE.md ★4):
// a toy résumé scorer trained on 12 made-up past résumés from a skewed
// history. The student deletes its gender box, the toy is fitted again, and
// "women's" carries the same signal, more strongly than before. Every
// number the card shows is computed here from the authored rows by a real
// fit (`ToyFit`), and `GenderBoxTests` holds each one to the slate's
// (`tools/check_slate_numbers.py`).

/// The card's one control: the gender box kept in the data, or deleted.
public enum GenderBox: String, CaseIterable, Sendable, Hashable {
    case kept
    case deleted

    /// The Mac's ←/→ on the control ("kept | deleted", left to right):
    /// → deletes, ← keeps.
    static func after(_ arrow: InteractiveArrow) -> GenderBox {
        arrow == .next ? .deleted : .kept
    }
}

/// What the toy reads on a résumé: the gender box, and three words.
public enum GenderBoxFeature: Int, CaseIterable, Sendable, Hashable {
    /// The gender box says "woman" (the toy's made-up old records keep a
    /// two-value field; not a recommendation).
    case woman = 0
    /// The word "women's" ("women's chess club", "women's chess club captain").
    case womens = 1
    /// The word "captain".
    case captain = 2
    /// The word "coding" ("coding club").
    case coding = 3
}

/// A club line on a résumé, as drawn. Each carries the toy's words in it.
public enum GenderBoxClub: CaseIterable, Sendable, Hashable {
    case chessCaptain
    case womensChessCaptain
    case womensChess
    case coding

    /// The toy's words this line contains.
    public var features: [GenderBoxFeature] {
        switch self {
        case .chessCaptain: return [.captain]
        case .womensChessCaptain: return [.womens, .captain]
        case .womensChess: return [.womens]
        case .coding: return [.coding]
        }
    }
}

/// What a résumé says, as the toy can read it.
public struct GenderBoxProfile: Equatable, Sendable, Hashable {
    public let woman: Bool
    public let womens: Bool
    public let captain: Bool
    public let coding: Bool

    public init(woman: Bool, womens: Bool, captain: Bool, coding: Bool) {
        self.woman = woman
        self.womens = womens
        self.captain = captain
        self.coding = coding
    }

    /// The row the fit reads: woman, women's, captain, coding (1 or 0).
    public var features: [Double] {
        [woman, womens, captain, coding].map { $0 ? 1 : 0 }
    }

    public func has(_ feature: GenderBoxFeature) -> Bool {
        features[feature.rawValue] == 1
    }

    /// The club lines the résumé shows (none: "No clubs listed"): the
    /// chess line first, then coding.
    public var clubs: [GenderBoxClub] {
        var lines: [GenderBoxClub] = []
        switch (womens, captain) {
        case (true, true): lines.append(.womensChessCaptain)
        case (true, false): lines.append(.womensChess)
        case (false, true): lines.append(.chessCaptain)
        case (false, false): break
        }
        if coding { lines.append(.coding) }
        return lines
    }
}

/// One of the 12 made-up past résumés, and whether that person was hired.
public struct GenderBoxResume: Equatable, Sendable, Identifiable {
    /// 1 to 12, in the slate's order (the men, then the women).
    public let id: Int
    public let profile: GenderBoxProfile
    public let hired: Bool

    public init(_ id: Int, _ woman: Int, _ womens: Int, _ captain: Int, _ coding: Int, hired: Int) {
        self.id = id
        profile = GenderBoxProfile(woman: woman == 1, womens: womens == 1, captain: captain == 1, coding: coding == 1)
        self.hired = hired == 1
    }
}

/// How a weight moves a score, in words (the slate: "words carry the
/// meaning" for 9th graders; colour never does).
public enum GenderBoxEffect: Equatable, Sendable, Hashable {
    case up
    case upALittle
    case down
    case downALittle
}

public enum GenderBoxContent {
    /// SLATE.md: 12 rows as (woman, women's, captain, coding → hired).
    public static let resumes: [GenderBoxResume] = [
        // The men: 6 of 8 hired.
        GenderBoxResume(1, 0, 0, 1, 1, hired: 1),
        GenderBoxResume(2, 0, 0, 1, 0, hired: 1),
        GenderBoxResume(3, 0, 0, 0, 1, hired: 1),
        GenderBoxResume(4, 0, 0, 1, 1, hired: 1),
        GenderBoxResume(5, 0, 0, 0, 0, hired: 0),
        GenderBoxResume(6, 0, 0, 0, 1, hired: 1),
        GenderBoxResume(7, 0, 0, 1, 0, hired: 0),
        GenderBoxResume(8, 0, 0, 0, 0, hired: 1),
        // The women: 1 of 4 hired.
        GenderBoxResume(9, 1, 1, 1, 1, hired: 0),
        GenderBoxResume(10, 1, 0, 1, 1, hired: 1),
        GenderBoxResume(11, 1, 1, 0, 1, hired: 0),
        GenderBoxResume(12, 1, 0, 0, 0, hired: 0),
    ]

    /// The two new test résumés: identical (a woman who codes) except one
    /// line, "women's chess club captain" against "chess club captain".
    public static let testWith = GenderBoxProfile(woman: true, womens: true, captain: true, coding: true)
    public static let testWithout = GenderBoxProfile(woman: true, womens: false, captain: true, coding: true)

    /// The fit's convention (recorded in CONTENT.md): λ = 0.5, intercept
    /// unpenalised, summed log-loss, exact optimum.
    public static let lambda = ToyFit.slateLambda

    public static var examples: [ToyFit.Example] {
        resumes.map { ToyFit.Example($0.profile.features, label: $0.hired) }
    }

    /// The features the toy reads with the gender box `box`.
    public static func features(_ box: GenderBox) -> [GenderBoxFeature] {
        switch box {
        case .kept: return GenderBoxFeature.allCases
        case .deleted: return GenderBoxFeature.allCases.filter { $0 != .woman }
        }
    }

    /// The toy fitted with the gender box kept, and fitted again without it.
    public static let keptFit = ToyFit.fit(examples, keeping: features(.kept).map(\.rawValue), lambda: lambda)
    public static let deletedFit = ToyFit.fit(examples, keeping: features(.deleted).map(\.rawValue), lambda: lambda)

    public static func fit(_ box: GenderBox) -> ToyFit {
        box == .kept ? keptFit : deletedFit
    }

    // MARK: What the card shows

    /// `feature`'s weight with the gender box `box`, to the two decimals
    /// shown; nil when the box is deleted and `feature` is the gender box.
    public static func weight(_ feature: GenderBoxFeature, _ box: GenderBox) -> Double? {
        fit(box).weight(forFeature: feature.rawValue).map(roundedToHundredths)
    }

    /// `profile`'s score out of 100 with the gender box `box`, rounded.
    public static func score(_ profile: GenderBoxProfile, _ box: GenderBox) -> Int {
        Int(fit(box).score(profile.features).rounded())
    }

    /// The two test résumés' scores.
    public static func scores(_ box: GenderBox) -> (with: Int, without: Int) {
        (score(testWith, box), score(testWithout, box))
    }

    /// The gap between them, in points (from the rounded scores shown).
    public static func gap(_ box: GenderBox) -> Int {
        let pair = scores(box)
        return pair.without - pair.with
    }

    // MARK: The past

    public static var men: [GenderBoxResume] { resumes.filter { !$0.profile.woman } }
    public static var women: [GenderBoxResume] { resumes.filter { $0.profile.woman } }
    public static var menHired: Int { men.filter(\.hired).count }
    public static var womenHired: Int { women.filter(\.hired).count }

    // MARK: Drawing

    /// The weight bars' full half-width: the largest weight either fit
    /// shows, rounded up to a tenth (1.53 → 1.6), so both states share one
    /// scale and "women's" visibly grows.
    public static let barMaximum: Double = {
        let all = GenderBox.allCases.flatMap { box in
            GenderBoxFeature.allCases.compactMap { weight($0, box) }
        }
        let largest = all.map { abs($0) }.max() ?? 1
        return (largest * 10).rounded(.up) / 10
    }()

    /// How much of the bar's half `weight` fills (0 to 1).
    public static func barFraction(_ weight: Double) -> Double {
        min(abs(weight) / barMaximum, 1)
    }

    /// Below this size a weight pushes "a little".
    public static let aLittleBelow: Double = 0.5

    public static func effect(_ weight: Double) -> GenderBoxEffect {
        let small = abs(weight) < aLittleBelow
        if weight < 0 { return small ? .downALittle : .down }
        return small ? .upALittle : .up
    }

    /// "−1.21", "+0.33" (a true minus sign, two decimals).
    public static func signed(_ weight: Double) -> String {
        let value = roundedToHundredths(weight)
        let digits = String(format: "%.2f", abs(value))
        if value == 0 { return digits }
        return (value < 0 ? "\u{2212}" : "+") + digits
    }

    /// "minus 1.21", "plus 0.33", for VoiceOver.
    public static func spokenSigned(_ weight: Double) -> String {
        let value = roundedToHundredths(weight)
        let digits = String(format: "%.2f", abs(value))
        if value == 0 { return digits }
        return (value < 0 ? "minus " : "plus ") + digits
    }

    static func roundedToHundredths(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
