import Foundation

// MARK: - K-anonymity checker

/// Verifies that no participant in a cohort can be singled out from fewer than k others
/// who share the same quasi-identifier values.
///
/// K-anonymity is a baseline requirement for health research publication.
/// Apple's ResearchKit studies typically require k ≥ 5.
public struct KAnonymityChecker: Sendable {

    public struct EquivalenceClass: Sendable {
        /// The quasi-identifier tuple that defines this class.
        public let ageBucket: AgeBucket
        public let biologicalSex: BiologicalSex
        public let region: String
        public let bmiTier: BMITier?
        /// Number of participants sharing this combination.
        public let count: Int
        /// Whether this class meets the minimum k.
        public let satisfiesK: Bool
    }

    public struct KAnonymityReport: Sendable {
        public let k: Int                                   // target k
        public let cohortSize: Int
        public let equivalenceClasses: [EquivalenceClass]
        public let violatingClasses: [EquivalenceClass]     // count < k
        public let minimumClassSize: Int
        public let satisfiesKAnonymity: Bool
        public let suppressionRequired: Int                 // participants to suppress for compliance
        public let recommendations: [String]
    }

    public init() {}

    /// Checks k-anonymity for a cohort of participants.
    /// - Parameters:
    ///   - participants: The study cohort.
    ///   - k: Minimum equivalence class size (default 5, Apple Research minimum).
    ///   - includeBMI: Whether BMI tier is included as a quasi-identifier.
    ///     Only include if BMI is explicitly collected — adding unnecessary QIs increases suppression.
    public func check(
        participants: [Participant],
        k: Int = 5,
        includeBMI: Bool = false
    ) -> KAnonymityReport {
        // Group participants by quasi-identifier tuple
        var groups: [String: (EquivalenceClass, count: Int)] = [:]

        for participant in participants {
            let key = quasiIdentifierKey(participant, includeBMI: includeBMI)
            if let existing = groups[key] {
                groups[key] = (existing.0, existing.count + 1)
            } else {
                groups[key] = (
                    EquivalenceClass(
                        ageBucket: participant.ageBucket,
                        biologicalSex: participant.biologicalSex,
                        region: participant.region,
                        bmiTier: includeBMI ? participant.bmiTier : nil,
                        count: 0,       // will be replaced
                        satisfiesK: false
                    ),
                    1
                )
            }
        }

        // Build finalised equivalence classes
        let classes = groups.values.map { (base, count) in
            EquivalenceClass(
                ageBucket: base.ageBucket,
                biologicalSex: base.biologicalSex,
                region: base.region,
                bmiTier: base.bmiTier,
                count: count,
                satisfiesK: count >= k
            )
        }.sorted { $0.count < $1.count }

        let violating = classes.filter { !$0.satisfiesK }
        let minSize = classes.map(\.count).min() ?? 0
        let suppression = violating.reduce(0) { $0 + $1.count }
        let satisfies = violating.isEmpty

        var recommendations: [String] = []

        if !satisfies {
            recommendations.append(
                "\(violating.count) equivalence class(es) have fewer than \(k) members. " +
                "Suppressing these \(suppression) participants achieves k-anonymity but reduces cohort by \(String(format: "%.1f", Double(suppression) / Double(participants.count) * 100))%."
            )
        }

        if includeBMI && violating.count > classes.count / 3 {
            recommendations.append(
                "BMI tier is causing significant fragmentation (\(violating.count)/\(classes.count) classes violate k-anonymity). " +
                "Consider removing BMI as a quasi-identifier or generalising to a 2-tier classification."
            )
        }

        let smallRegions = classes.filter { $0.region.count > 0 && $0.count < k * 2 }
        if !smallRegions.isEmpty {
            let regionList = Set(smallRegions.map(\.region)).joined(separator: ", ")
            recommendations.append(
                "Regions with sparse representation: \(regionList). " +
                "Consider generalising to a coarser geography (e.g. country level) or merging with neighbouring regions."
            )
        }

        return KAnonymityReport(
            k: k,
            cohortSize: participants.count,
            equivalenceClasses: classes,
            violatingClasses: violating,
            minimumClassSize: minSize,
            satisfiesKAnonymity: satisfies,
            suppressionRequired: suppression,
            recommendations: recommendations
        )
    }

    /// Recommends a minimum cohort size to achieve k-anonymity for a given metric set
    /// with a target suppression rate below `maxSuppressionFraction`.
    public func recommendedCohortSize(
        for metrics: [HealthMetricType],
        k: Int = 5,
        maxSuppressionFraction: Double = 0.05
    ) -> Int {
        // Heuristic: estimate the number of distinct QI combinations
        // AgeBucket (7) × BiologicalSex (3) × Region (estimate ~50 for US state level) = 1050
        // Each class needs at least k members; with 5% suppression headroom, target 1.2×k per class
        let estimatedClasses = 7 * 3 * 50  // conservative estimate
        let baseRequired = estimatedClasses * k
        let withHeadroom = Int(Double(baseRequired) / (1.0 - maxSuppressionFraction))
        // High-sensitivity metrics may need larger cohorts for publication ethics
        let sensitivityMultiplier = metrics.contains(where: { $0.sensitivityTier >= 3 }) ? 1.5 : 1.0
        return Int(Double(withHeadroom) * sensitivityMultiplier)
    }

    // MARK: Private helpers

    private func quasiIdentifierKey(_ p: Participant, includeBMI: Bool) -> String {
        var parts = [p.ageBucket.rawValue, p.biologicalSex.rawValue, p.region]
        if includeBMI, let bmi = p.bmiTier { parts.append(bmi.rawValue) }
        return parts.joined(separator: "|")
    }
}

// MARK: - Suppression helper

public extension KAnonymityChecker {
    /// Returns participants with violating equivalence classes removed (suppressed).
    func suppress(participants: [Participant], k: Int = 5, includeBMI: Bool = false) -> [Participant] {
        // Compute violating QI keys
        var counts: [String: Int] = [:]
        for p in participants {
            let key = quasiIdentifierKey(p, includeBMI: includeBMI)
            counts[key, default: 0] += 1
        }
        let violatingKeys = Set(counts.filter { $0.value < k }.keys)
        return participants.filter {
            !violatingKeys.contains(quasiIdentifierKey($0, includeBMI: includeBMI))
        }
    }
}
