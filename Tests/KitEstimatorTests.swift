import Foundation

@main
struct KitEstimatorTests {
    static func main() {
        var failures: [String] = []
        var checksRun = 0

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checksRun += 1
            if condition() {
                print("PASS  \(name)")
            } else {
                failures.append(name)
                print("FAIL  \(name)")
            }
        }

        let kit = KitEstimator.estimate(items: [
            KitInventoryItem(
                name: "Books", category: "books", roomName: "Living Room",
                quantity: 1, cubicFeet: 15
            ),
            KitInventoryItem(
                name: "Hanging shirts", category: "clothing", roomName: "Primary Bedroom",
                quantity: 21, cubicFeet: 0.25
            ),
            KitInventoryItem(
                name: "Mattress", category: "furniture", roomName: "Primary Bedroom",
                tier: "furniture", sizeEstimate: "large", quantity: 2, cubicFeet: 30
            ),
            KitInventoryItem(
                name: "Dinner plates", category: "kitchen", roomName: "Kitchen",
                quantity: 1, cubicFeet: 3, isFragile: true
            ),
            KitInventoryItem(
                name: "Blankets", category: "linens", roomName: "Guest Room",
                sizeEstimate: "large", quantity: 1, cubicFeet: 9
            )
        ])

        // 15cf / 1.5 = 10 raw small boxes; 12% headroom = 11.2, rounded up = 12.
        // Kitchen plates add 2 raw small boxes; total raw 12 * 1.12 = 13.44 => 14.
        check(kit.small == 14, "small boxes receive exact 12% headroom before rounding")
        check(kit.large == 3, "large item mix selects large-box capacity with headroom")
        check(kit.medium > 0, "default clothing cube contributes medium boxes")
        check(kit.wardrobe == 2, "21 hanging items require two wardrobe boxes")
        check(kit.mattressBags == 2, "two beds map to two mattress bags without doubling")
        check(kit.dishPack == 1, "kitchen presence adds one dish pack")
        check(kit.tape == Int(ceil(Double(kit.small + kit.medium + kit.large) / 10.0)), "tape derives from headed box total")
        check(kit.paper > 0 && kit.wrap > 0, "paper and wrap derive from headed/fragile demand")
        check(kit.totalPriceCents > 0, "central price constants produce one positive total")

        let noBeds = KitEstimator.estimate(items: [
            KitInventoryItem(name: "Bedside table", tier: "furniture", cubicFeet: 12)
        ])
        check(noBeds.mattressBags == 0, "bedside furniture is not miscounted as a bed")

        if failures.isEmpty {
            print("\nKitEstimatorTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nKitEstimatorTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }
}
