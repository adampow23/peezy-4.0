import Foundation

@main
struct ManHourNormalizerTests {
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

        check(ManHourNormalizer.normalize([]).isEmpty, "empty input normalizes to empty output")

        let single = ManHourNormalizer.normalize([
            MoverQuote(company: "A", crew: 3, hours: 5, perManRate: 50, travelFee: 100)
        ])
        check(single.count == 1, "single quote yields one row")
        check(single[0].totalManHours == 15, "single quote total man-hours is crew × hours")
        check(single[0].repricedTotal == 850, "single quote reprices at its own average")
        check(single[0].lowball == false, "single quote is never flagged lowball")

        // man-hours: A = 3×5 = 15, B = 2×6 = 12, C = 4×6 = 24; avg = 51/3 = 17
        // repriced: A = 17×50+100 = 950, B = 17×60+0 = 1020, C = 17×45+150 = 915
        let trio = ManHourNormalizer.normalize([
            MoverQuote(company: "A", crew: 3, hours: 5, perManRate: 50, travelFee: 100),
            MoverQuote(company: "B", crew: 2, hours: 6, perManRate: 60, travelFee: 0),
            MoverQuote(company: "C", crew: 4, hours: 6, perManRate: 45, travelFee: 150)
        ])
        check(trio.count == 3, "three quotes yield three rows")
        check(trio.map(\.company) == ["A", "B", "C"], "input order is preserved")
        check(trio.map(\.totalManHours) == [15, 12, 24], "total man-hours are 15/12/24")
        check(trio.map(\.repricedTotal) == [950, 1020, 915], "repriced totals use the 17 man-hour fleet average")
        check(trio.map(\.lowball) == [true, true, false], "only quotes under the fleet average flag lowball")

        if failures.isEmpty {
            print("\nManHourNormalizerTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nManHourNormalizerTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }
}
