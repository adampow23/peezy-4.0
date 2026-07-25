import Foundation

@main
struct PricingCalibrationRunner {
    static func main() {
        #if DEBUG
        print(PricingCalibrationHarness.report())
        #else
        fatalError("PricingCalibrationHarness is DEBUG-only")
        #endif
    }
}
