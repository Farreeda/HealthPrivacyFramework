import Foundation

// MARK: - Consent scope

/// Defines the precise boundaries of what a participant consents to.
/// Apple's Research app uses scoped consent — this models that pattern.
public struct ConsentScope: Codable, Sendable {

    // MARK: Data use permissions

    /// Which health metrics the participant consents to share.
    public let permittedMetrics: Set<HealthMetricType>

    /// Whether raw samples may leave the device, or only aggregates.
    public let rawDataPermitted: Bool

    /// Whether the participant allows linkage to their other Apple Health data
    /// beyond the explicitly collected metrics.
    public let healthKitLinkagePermitted: Bool

    /// Whether participant data may contribute to future studies under this consent.
    public let futureResearchPermitted: Bool

    /// Whether participant data can be shared with academic partners (IRB-approved).
    public let thirdPartyResearchPermitted: Bool

    // MARK: Retention

    /// How long identifiable data (before anonymisation) may be retained.
    public let identifiableRetentionDays: Int

    /// How long anonymised/aggregated results may be retained.
    public let anonymisedRetentionDays: Int?    // nil = indefinite, standard for published research

    // MARK: Withdrawal

    /// Whether the participant may withdraw and have their data deleted.
    public let withdrawalWithDeletionSupported: Bool

    // MARK: Derived checks

    /// True if this consent is appropriately narrow for a high-sensitivity study
    /// (no raw data off device, no third-party sharing, reasonable retention).
    public var isConservative: Bool {
        !rawDataPermitted
        && !thirdPartyResearchPermitted
        && identifiableRetentionDays <= 90
    }

    public init(
        permittedMetrics: Set<HealthMetricType>,
        rawDataPermitted: Bool,
        healthKitLinkagePermitted: Bool = false,
        futureResearchPermitted: Bool = false,
        thirdPartyResearchPermitted: Bool = false,
        identifiableRetentionDays: Int = 30,
        anonymisedRetentionDays: Int? = nil,
        withdrawalWithDeletionSupported: Bool = true
    ) {
        self.permittedMetrics = permittedMetrics
        self.rawDataPermitted = rawDataPermitted
        self.healthKitLinkagePermitted = healthKitLinkagePermitted
        self.futureResearchPermitted = futureResearchPermitted
        self.thirdPartyResearchPermitted = thirdPartyResearchPermitted
        self.identifiableRetentionDays = identifiableRetentionDays
        self.anonymisedRetentionDays = anonymisedRetentionDays
        self.withdrawalWithDeletionSupported = withdrawalWithDeletionSupported
    }
}

// MARK: - Consent scope checker

/// Validates that a study protocol operates within the bounds of participant consent.
public struct ConsentScopeChecker: Sendable {

    public init() {}

    public struct ConsentViolation: Sendable {
        public let severity: Severity
        public let description: String
        public let recommendation: String

        public enum Severity: String, Sendable {
            case blocker    = "BLOCKER"     // study cannot proceed
            case warning    = "WARNING"     // should address before launch
            case advisory   = "ADVISORY"    // best-practice gap
        }
    }

    /// Checks a study protocol against the declared consent scope.
    /// Returns an array of violations (empty = fully compliant).
    public func check(protocol studyProtocol: StudyProtocol) -> [ConsentViolation] {
        var violations: [ConsentViolation] = []
        let consent = studyProtocol.consentScope

        // 1. Metric coverage — every collected metric must be in scope
        let unconsented = studyProtocol.targetMetrics.filter {
            !consent.permittedMetrics.contains($0)
        }
        if !unconsented.isEmpty {
            let list = unconsented.map(\.rawValue).joined(separator: ", ")
            violations.append(.init(
                severity: .blocker,
                description: "Metrics not covered by consent: \(list)",
                recommendation: "Either add these metrics to the consent form or remove them from the study."
            ))
        }

        // 2. Raw data off device requires explicit consent
        if studyProtocol.collectionStrategy == .centralDifferentialPrivacy && !consent.rawDataPermitted {
            violations.append(.init(
                severity: .blocker,
                description: "Central DP strategy transmits raw samples before noising, but rawDataPermitted = false.",
                recommendation: "Switch to local DP or on-device aggregation, or update consent to permit raw data transmission."
            ))
        }

        // 3. Third-party data in federated plan needs explicit consent
        if studyProtocol.federatedPlan != nil && !consent.futureResearchPermitted {
            violations.append(.init(
                severity: .warning,
                description: "Federated aggregation plan is defined, but consent does not cover future research use of aggregated results.",
                recommendation: "Add future research permission to consent, or scope the federated plan to this study only."
            ))
        }

        // 4. High-sensitivity metrics require conservative consent
        let highSensitivityMetrics = studyProtocol.targetMetrics.filter { $0.sensitivityTier >= 3 }
        if !highSensitivityMetrics.isEmpty && !consent.isConservative {
            violations.append(.init(
                severity: .warning,
                description: "Study collects tier-3/4 metrics (\(highSensitivityMetrics.map(\.rawValue).joined(separator: ", "))) but consent is not conservative (raw data permitted or third-party sharing enabled).",
                recommendation: "For high-sensitivity health metrics, restrict consent to on-device or aggregates-only and disable third-party sharing."
            ))
        }

        // 5. Identifiable retention sanity check
        if consent.identifiableRetentionDays > 180 {
            violations.append(.init(
                severity: .advisory,
                description: "Identifiable data retention is \(consent.identifiableRetentionDays) days, which exceeds the recommended 180-day maximum.",
                recommendation: "Reduce identifiable retention to the minimum necessary for study completion, typically 30–90 days."
            ))
        }

        // 6. Withdrawal + deletion must be supported for Apple Research compliance
        if !consent.withdrawalWithDeletionSupported {
            violations.append(.init(
                severity: .blocker,
                description: "withdrawalWithDeletionSupported = false. Apple Research requires participants to be able to withdraw and have their data deleted.",
                recommendation: "Implement a withdrawal flow that deletes all identifiable participant data within 30 days of request."
            ))
        }

        return violations
    }
}
