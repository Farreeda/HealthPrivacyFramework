import Foundation

// MARK: - Federated aggregation plan

/// Describes how a study aggregates data across participants without a central server
/// ever seeing individual-level data. Mirrors Apple's on-device and Private Federated
/// Learning patterns used in Health and Siri features.
public struct FederatedAggregationPlan: Codable, Sendable {

    public enum AggregationTopology: String, Codable, Sendable {
        /// All participants send noised updates to a single aggregation server.
        case starFederated       = "star_federated"
        /// Secure multi-party computation: server sees only the sum, never individual contributions.
        case secureMPC           = "secure_mpc"
        /// On-device only: aggregation happens entirely in the Secure Enclave; nothing leaves the device.
        case onDeviceEnclave     = "on_device_enclave"
        /// Hierarchical: regional aggregators combine results before central aggregation.
        case hierarchical        = "hierarchical"
    }

    public let topology: AggregationTopology
    /// Minimum number of participants whose updates must be included in each aggregation round
    /// before the result is released. Prevents singling out individuals via the aggregate.
    public let minimumParticipantsPerRound: Int
    /// Whether Secure Aggregation (cryptographic) is used to hide individual updates from the server.
    public let secureAggregationEnabled: Bool
    /// Whether the aggregation server is operated by Apple (true) or a third party (false).
    public let firstPartyServer: Bool
    /// How often aggregation rounds occur.
    public let roundFrequency: RoundFrequency
    /// DP noise added at the aggregation layer (server-side, in addition to any client-side noise).
    public let serverSideDP: ServerSideDPConfig?

    public init(
        topology: AggregationTopology,
        minimumParticipantsPerRound: Int = 100,
        secureAggregationEnabled: Bool = true,
        firstPartyServer: Bool = true,
        roundFrequency: RoundFrequency = .daily,
        serverSideDP: ServerSideDPConfig? = nil
    ) {
        self.topology = topology
        self.minimumParticipantsPerRound = minimumParticipantsPerRound
        self.secureAggregationEnabled = secureAggregationEnabled
        self.firstPartyServer = firstPartyServer
        self.roundFrequency = roundFrequency
        self.serverSideDP = serverSideDP
    }

    public enum RoundFrequency: String, Codable, Sendable {
        case hourly  = "hourly"
        case daily   = "daily"
        case weekly  = "weekly"
    }

    public struct ServerSideDPConfig: Codable, Sendable {
        /// Epsilon consumed per aggregation round at the server.
        public let epsilonPerRound: Double
        /// Clip norm bound for participant updates (prevents large outliers dominating the aggregate).
        public let clipNorm: Double

        public init(epsilonPerRound: Double, clipNorm: Double) {
            self.epsilonPerRound = epsilonPerRound
            self.clipNorm = clipNorm
        }
    }

    /// Privacy strength of this federated plan, independent of the per-metric DP.
    public var privacyStrength: PrivacyStrength {
        switch topology {
        case .onDeviceEnclave:          return .veryStrong
        case .secureMPC where secureAggregationEnabled: return .veryStrong
        case .starFederated where secureAggregationEnabled: return .strong
        case .hierarchical where secureAggregationEnabled: return .strong
        default:                        return .moderate
        }
    }
}

// MARK: - Federated plan validator

public struct FederatedPlanValidator: Sendable {

    public struct ValidationIssue: Sendable {
        public let severity: Severity
        public let description: String
        public let recommendation: String

        public enum Severity: String, Sendable {
            case critical = "CRITICAL"
            case warning  = "WARNING"
            case info     = "INFO"
        }
    }

    public init() {}

    public func validate(plan: FederatedAggregationPlan, cohortSize: Int) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // 1. Minimum participants per round must be meaningful
        if plan.minimumParticipantsPerRound < 50 {
            issues.append(.init(
                severity: .critical,
                description: "minimumParticipantsPerRound (\(plan.minimumParticipantsPerRound)) is below 50. Aggregates over very small groups can leak individual signals.",
                recommendation: "Set minimumParticipantsPerRound ≥ 100 for health data. Apple's Private Federated Learning uses ≥ 1000 for production features."
            ))
        }

        // 2. Round participation must be plausible given cohort size
        let expectedParticipationRate = 0.3  // conservative: 30% of participants active per round
        let expectedActivePerRound = Int(Double(cohortSize) * expectedParticipationRate)
        if expectedActivePerRound < plan.minimumParticipantsPerRound {
            issues.append(.init(
                severity: .warning,
                description: "Expected active participants per round (\(expectedActivePerRound)) may be below minimumParticipantsPerRound (\(plan.minimumParticipantsPerRound)) at \(Int(expectedParticipationRate * 100))% participation rate.",
                recommendation: "Increase cohort size to at least \(plan.minimumParticipantsPerRound * 4) to maintain round validity at realistic participation rates."
            ))
        }

        // 3. Third-party server + sensitive data is a risk
        if !plan.firstPartyServer && plan.topology != .onDeviceEnclave {
            issues.append(.init(
                severity: .critical,
                description: "Aggregation server is third-party operated. Health data aggregates, even with DP, represent sensitive data in transit.",
                recommendation: "Use Apple-operated aggregation infrastructure. If third-party is required, mandate contractual DPA, audit rights, and ISO 27001 certification."
            ))
        }

        // 4. Star topology without secure aggregation is weak
        if plan.topology == .starFederated && !plan.secureAggregationEnabled {
            issues.append(.init(
                severity: .warning,
                description: "Star-federated topology without Secure Aggregation means the server observes individual participant updates.",
                recommendation: "Enable Secure Aggregation (e.g. Google's SecAgg protocol or Apple's equivalent) so the server only ever sees the aggregate."
            ))
        }

        // 5. Hourly rounds with small cohorts are risky
        if plan.roundFrequency == .hourly && cohortSize < 10000 {
            issues.append(.init(
                severity: .warning,
                description: "Hourly aggregation rounds with a cohort of \(cohortSize) may produce rounds with very few active participants, weakening privacy guarantees.",
                recommendation: "For cohorts under 10k, prefer daily or weekly aggregation rounds to ensure each round has sufficient participants."
            ))
        }

        return issues
    }
}
