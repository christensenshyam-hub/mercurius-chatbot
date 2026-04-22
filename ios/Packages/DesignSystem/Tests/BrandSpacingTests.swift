import Testing
import CoreGraphics
@testable import DesignSystem

@Suite("BrandSpacing scale")
struct BrandSpacingTests {

    @Test("Spacing scale is monotonically increasing")
    func scaleIsMonotonic() {
        let values: [CGFloat] = [
            BrandSpacing.xxs,
            BrandSpacing.xs,
            BrandSpacing.sm,
            BrandSpacing.md,
            BrandSpacing.lg,
            BrandSpacing.xl,
            BrandSpacing.xxl,
            BrandSpacing.xxxl,
        ]
        for i in 1..<values.count {
            #expect(values[i] > values[i - 1], "Spacing at index \(i) (\(values[i])) should exceed previous (\(values[i - 1]))")
        }
    }

    @Test("Radius scale is monotonically increasing (pill excepted)")
    func radiusScale() {
        #expect(BrandRadius.sm < BrandRadius.md)
        #expect(BrandRadius.md < BrandRadius.lg)
        #expect(BrandRadius.lg < BrandRadius.xl)
        #expect(BrandRadius.pill > BrandRadius.xl)
    }
}
