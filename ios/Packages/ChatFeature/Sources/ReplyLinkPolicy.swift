import Foundation

/// Which links inside a tutor reply may leave the app. A reply is model
/// output, so a link in it is only as trustworthy as the model's next token:
/// only `https` URLs with a host are handed to the system. `http`, `mailto`,
/// `tel`, `sms`, `javascript`, custom schemes such as `mercurius://`, and
/// scheme-less strings are all discarded — as is any URL with userinfo
/// (`https://khanacademy.org@evil.example` shows one host and opens another).
public enum ReplyLinkPolicy {
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return false }
        guard url.user(percentEncoded: false) == nil, url.password(percentEncoded: false) == nil else {
            return false
        }
        return true
    }
}
