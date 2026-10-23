import Foundation
import Observation
import DesignSystem
import SettingsFeature

/// Which course the learner is following, and the Basics reading size.
/// Device-local, like the theme: nothing here reaches the server, and a
/// reset ("Start Over") leaves it alone.
///
/// The track only decides where the app opens (Home's next lesson, the
/// path's switch, the Mac's sidebar order). It never locks anything: both
/// courses stay open, each with its own progress.
///
/// Storage (strings in the `PreferenceStore`):
/// - `storageKey` — the track's raw value. Absent until the learner picks
///   one, which reads as the Deep dive, so installs from before Basics open
///   exactly where they did.
/// - `"<storageKey>.readingSize"` — the Basics reading size.
/// - `"<storageKey>.readingSizeOffered"` — "1" once the one-time "Want the
///   words bigger?" offer was answered or closed.
@MainActor
@Observable
public final class CurriculumTrackStore {
    /// The course Home and the path open on.
    public private(set) var track: CurriculumTrack
    /// The learner picked a track (onboarding's cards or the switch).
    public private(set) var hasChosen: Bool
    /// The reading size on Basics screens (a floor; see `ReadingSize`).
    public private(set) var basicsReadingSize: ReadingSize
    /// The one-time text-size offer was answered or closed.
    public private(set) var readingSizeOfferHandled: Bool

    private let preferences: PreferenceStore
    private let storageKey: String
    private var readingSizeKey: String { storageKey + ".readingSize" }
    private var offeredKey: String { storageKey + ".readingSizeOffered" }

    public init(
        preferences: PreferenceStore = UserDefaultsPreferenceStore(),
        storageKey: String = "com.mayoailiteracy.mercurius.curriculumTrack"
    ) {
        self.preferences = preferences
        self.storageKey = storageKey
        let stored = preferences.string(for: storageKey).flatMap(CurriculumTrack.init(rawValue:))
        self.track = stored ?? .deepDive
        self.hasChosen = stored != nil
        self.basicsReadingSize = preferences.string(for: storageKey + ".readingSize")
            .flatMap(ReadingSize.init(rawValue:)) ?? .standard
        self.readingSizeOfferHandled = preferences.string(for: storageKey + ".readingSizeOffered") == "1"
    }

    /// Follow `track` from now on.
    public func choose(_ track: CurriculumTrack) {
        self.track = track
        hasChosen = true
        preferences.set(track.rawValue, for: storageKey)
    }

    /// Whether the one-time "Want the words bigger?" offer shows: on Basics
    /// screens until the learner answers or closes it.
    public var offersReadingSize: Bool {
        track == .basics && !readingSizeOfferHandled
    }

    /// Set the Basics reading size. Answers the one-time offer too.
    public func setBasicsReadingSize(_ size: ReadingSize) {
        basicsReadingSize = size
        preferences.set(size.rawValue, for: readingSizeKey)
        markReadingSizeOfferHandled()
    }

    /// Close the one-time offer without changing the size.
    public func markReadingSizeOfferHandled() {
        guard !readingSizeOfferHandled else { return }
        readingSizeOfferHandled = true
        preferences.set("1", for: offeredKey)
    }
}
