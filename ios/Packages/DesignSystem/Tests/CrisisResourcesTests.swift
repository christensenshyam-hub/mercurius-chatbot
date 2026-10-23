import Testing
import Foundation
@testable import DesignSystem

@Suite("Crisis resources")
struct CrisisResourcesTests {

    @Test("988 can be called and texted, 911 called, and 741741 texted with HOME")
    func links() {
        #expect(CrisisResources.call988.absoluteString == "tel:988")
        #expect(CrisisResources.text988.absoluteString == "sms:988")
        #expect(CrisisResources.textHomeTo741741.absoluteString == "sms:741741&body=HOME")
        #expect(CrisisResources.call911.absoluteString == "tel:911")
    }

    @Test("Every link opens the phone or messages app, never the web")
    func schemes() {
        let schemes = [
            CrisisResources.call988, CrisisResources.text988,
            CrisisResources.textHomeTo741741, CrisisResources.call911,
        ].map { $0.scheme }
        #expect(schemes == ["tel", "sms", "sms", "tel"])
    }
}
