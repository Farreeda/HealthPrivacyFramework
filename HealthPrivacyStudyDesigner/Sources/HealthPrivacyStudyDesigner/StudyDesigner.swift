import Foundation

// MARK: - Shared issue protocol

/// Lets `ConsentViolation` and `ValidationIssue` be treated uniformly
/// when computing overall study readiness.
public protocol PrivacyIssue: Sendable {
    var isBlocker: Bool { get }
    var isWarning: Bool { get }
}

extension ConsentScopeChecker.ConsentViolation: PrivacyIssue {
    public var isBlocker: Bool { severity == .blocker }
    public var isWarning: Bool { severity == .warning }
}

extension FederatedPlanValidator.ValidationIssue: PrivacyIssue {
    public var isBlocker: Bool { severity == .critical }
    public var isWarning: Bool { severity == .warning }
}

// MARK: - Study designer (main entry point)

/// Top-level API for the HealthPrivacy research study designer.
/// Composes all subsystems into a single analysis pass.
public struct StudyDesigner: Sendable {

    private let kAnonymityChecker = KAnonymityChecker()
    private let dpPlanner = DifferentialPrivacyPlanner()
    private let consentChecker = ConsentScopeChecker()
    private let riskEstimator = ReidentificationRiskEstimator()
    private let federatedValidator = FederatedPlanValidator()

    public init() {}

    // MARK: - Full study analysis

    public struct StudyAnalysis: Sendable {
        public let studyProtocol: StudyProtocol
        public let dpPlan: DifferentialPrivacyPlanner.StudyDPPlan
        public let consentViolations: [ConsentScopeChecker.ConsentViolation]
        public let federatedIssues: [FederatedPlanValidator.ValidationIssue]
        public let overallReadiness: ReadinessLevel
        public let summary: String

        public enum ReadinessLevel: String, Sendable {
            case readyToLaunch    = "READY_TO_LAUNCH"
            case needsRevision    = "NEEDS_REVISION"
            case blocked          = "BLOCKED"
        }
    }

    /// Analyses a study protocol and returns a comprehensive privacy readiness report.
    public func analyse(protocol studyProtocol: StudyProtocol) -> StudyAnalysis {
        let dpPlan = dpPlanner.plan(for: studyProtocol)
        let consentViolations = consentChecker.check(protocol: studyProtocol)
        var federatedIssues: [FederatedPlanValidator.ValidationIssue] = []

        if let fedPlan = studyProtocol.federatedPlan {
            federatedIssues = federatedValidator.validate(
                plan: fedPlan,
                cohortSize: studyProtocol.targetCohortSize
            )
        }

        // Both types now conform to PrivacyIssue — concatenation compiles fine
        let allIssues: [any PrivacyIssue] = consentViolations + federatedIssues

        let readiness: StudyAnalysis.ReadinessLevel
        if allIssues.contains(where: \.isBlocker) || !dpPlan.isWithinBudget {
            readiness = .blocked
        } else if allIssues.contains(where: \.isWarning) || !dpPlan.recommendations.isEmpty {
            readiness = .needsRevision
        } else {
            readiness = .readyToLaunch
        }

        let summary = buildSummary(
            studyProtocol: studyProtocol,
            dpPlan: dpPlan,
            consentViolations: consentViolations,
            federatedIssues: federatedIssues,
            readiness: readiness
        )

        return StudyAnalysis(
            studyProtocol: studyProtocol,
            dpPlan: dpPlan,
            consentViolations: consentViolations,
            federatedIssues: federatedIssues,
            overallReadiness: readiness,
            summary: summary
        )
    }

    /// Analyses a cohort of participants against a study protocol.
    public func analyseCohort(
        participants: [Participant],
        protocol studyProtocol: StudyProtocol
    ) -> CohortAnalysis {
        let kReport = kAnonymityChecker.check(
            participants: participants,
            k: studyProtocol.minimumKAnonymity
        )
        let riskReport = riskEstimator.estimate(participants: participants)
        let suppressed = kAnonymityChecker.suppress(
            participants: participants,
            k: studyProtocol.minimumKAnonymity
        )
        return CohortAnalysis(
            originalSize: participants.count,
            postSuppressionSize: suppressed.count,
            kAnonymityReport: kReport,
            riskReport: riskReport
        )
    }

    // MARK: - Private

    private func buildSummary(
        studyProtocol: StudyProtocol,
        dpPlan: DifferentialPrivacyPlanner.StudyDPPlan,
        consentViolations: [ConsentScopeChecker.ConsentViolation],
        federatedIssues: [FederatedPlanValidator.ValidationIssue],
        readiness: StudyAnalysis.ReadinessLevel
    ) -> String {
        var lines: [String] = []
        lines.append("=== HealthPrivacy Study Analysis: \(studyProtocol.name) ===")
        lines.append("Status: \(readiness.rawValue)")
        lines.append("")
        lines.append("Metrics: \(studyProtocol.targetMetrics.map(\.rawValue).joined(separator: ", "))")
        lines.append("Strategy: \(studyProtocol.collectionStrategy.rawValue)")
        lines.append("Duration: \(studyProtocol.duration.weeks)w, sampling every \(studyProtocol.duration.samplingIntervalHours)h")
        lines.append("Cohort target: \(studyProtocol.targetCohortSize) participants")
        lines.append("Epsilon budget: \(studyProtocol.epsilonBudget) (used: \(String(format: "%.4f", dpPlan.totalEpsilonUsed)))")
        lines.append("")

        if dpPlan.isWithinBudget {
            lines.append("[DP] Budget: within budget")
        } else {
            lines.append("[DP] Budget: EXCEEDED by \(String(format: "%.4f", dpPlan.totalEpsilonUsed - dpPlan.epsilonBudget))")
        }

        if consentViolations.isEmpty {
            lines.append("[Consent] No violations")
        } else {
            lines.append("[Consent] \(consentViolations.count) issue(s):")
            for v in consentViolations {
                lines.append("  [\(v.severity.rawValue)] \(v.description)")
            }
        }

        if federatedIssues.isEmpty {
            lines.append("[Federated] No issues")
        } else {
            lines.append("[Federated] \(federatedIssues.count) issue(s):")
            for i in federatedIssues {
                lines.append("  [\(i.severity.rawValue)] \(i.description)")
            }
        }

        if !dpPlan.recommendations.isEmpty {
            lines.append("")
            lines.append("[DP Recommendations]")
            for r in dpPlan.recommendations { lines.append("  - \(r)") }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Cohort analysis

public struct CohortAnalysis: Sendable {
    public let originalSize: Int
    public let postSuppressionSize: Int
    public let kAnonymityReport: KAnonymityChecker.KAnonymityReport
    public let riskReport: ReidentificationRiskEstimator.RiskReport

    public var suppressionRate: Double {
        guard originalSize > 0 else { return 0 }
        return Double(originalSize - postSuppressionSize) / Double(originalSize)
    }
}
