import Foundation
import HealthPrivacyStudyDesigner

// MARK: - Demo: Apple Fitness+ VO2 Max Research Study
//
// This simulates the privacy design process for a study measuring
// cardiorespiratory fitness improvement among Apple Watch users
// participating in a Fitness+ program.

print("╔══════════════════════════════════════════════════════════════╗")
print("║      HealthPrivacy Study Designer — Demo                     ║")
print("║      VO2 Max & HRV Fitness Study                             ║")
print("╚══════════════════════════════════════════════════════════════╝")
print()

// MARK: 1. Define the study protocol

let fedPlan = FederatedAggregationPlan(
    topology: .secureMPC,
    minimumParticipantsPerRound: 500,
    secureAggregationEnabled: true,
    firstPartyServer: true,
    roundFrequency: .weekly,
    serverSideDP: .init(epsilonPerRound: 0.1, clipNorm: 2.0)
)

let consent = ConsentScope(
    permittedMetrics: [.vo2Max, .heartRate, .heartRateVariability, .restingHeartRate, .activeEnergyBurned],
    rawDataPermitted: false,
    healthKitLinkagePermitted: false,
    futureResearchPermitted: true,   // aggregated federated results may inform future studies
    thirdPartyResearchPermitted: false,
    identifiableRetentionDays: 60,
    anonymisedRetentionDays: nil,
    withdrawalWithDeletionSupported: true
)

let studyProtocol = StudyProtocol(
    name: "Fitness+ Cardiorespiratory Improvement Study",
    description: "12-week study measuring VO2 max and HRV changes in Fitness+ participants using Apple Watch Series 9+.",
    targetMetrics: [.vo2Max, .heartRate, .heartRateVariability, .restingHeartRate, .activeEnergyBurned],
    collectionStrategy: .secureAggregation,
    duration: StudyDuration(weeks: 12, samplingIntervalHours: 24.0),
    targetCohortSize: 5000,
    minimumKAnonymity: 5,
    epsilonBudget: 1.0,
    consentScope: consent,
    federatedPlan: fedPlan
)

print("Study: \(studyProtocol.name)")
print("Metrics: \(studyProtocol.targetMetrics.map(\.rawValue).joined(separator: ", "))")
print("Duration: \(studyProtocol.duration.weeks) weeks, \(studyProtocol.duration.totalSamplesPerParticipant) samples/participant")
print("Cohort target: \(studyProtocol.targetCohortSize)")
print()

// MARK: 2. Run full protocol analysis

let designer = StudyDesigner()
let analysis = designer.analyse(protocol: studyProtocol)

print("─── Protocol Analysis ───────────────────────────────────────")
print(analysis.summary)
print()

// MARK: 3. Simulate a cohort and run k-anonymity + re-id risk

print("─── Cohort Simulation ───────────────────────────────────────")

// Generate a synthetic cohort of 200 for demonstration
var participants: [Participant] = []
let regions = ["CA", "TX", "NY", "FL", "WA", "IL", "MA", "CO", "OR", "GA"]
let ageBuckets = AgeBucket.allCases.filter { $0 != .under18 }
let sexes = BiologicalSex.allCases

for _ in 0..<2000 {
    participants.append(Participant(
        ageBucket: ageBuckets.randomElement()!,
        biologicalSex: sexes.randomElement()!,
        region: regions.randomElement()!,
        metrics: [.vo2Max, .heartRate, .heartRateVariability]
    ))
}

let cohortAnalysis = designer.analyseCohort(participants: participants, protocol: studyProtocol)
let kReport = cohortAnalysis.kAnonymityReport
let riskReport = cohortAnalysis.riskReport

print("Cohort size: \(cohortAnalysis.originalSize)")
print("k-anonymity (k=\(kReport.k)): \(kReport.satisfiesKAnonymity ? "SATISFIED" : "VIOLATED")")
print("Equivalence classes: \(kReport.equivalenceClasses.count)")
print("Min class size: \(kReport.minimumClassSize)")
if kReport.suppressionRequired > 0 {
    print("Suppression required: \(kReport.suppressionRequired) participants (\(String(format: "%.1f", cohortAnalysis.suppressionRate * 100))%)")
}
print("Post-suppression size: \(cohortAnalysis.postSuppressionSize)")
print()
print("Re-identification risk:")
print("  Journalist risk:  \(String(format: "%.1f", riskReport.journalistRisk * 100))%  [\(riskReport.riskTier.rawValue)]")
print("  Prosecutor risk:  \(String(format: "%.1f", riskReport.prosecutorRisk * 100))%")
print("  Marketer risk:    \(String(format: "%.1f", riskReport.marketerRisk * 100))%")
print("  Population unique: \(String(format: "%.1f", riskReport.estimatedPopulationUniqueness * 100))%")
if !riskReport.mitigations.isEmpty {
    print()
    print("Risk mitigations:")
    for m in riskReport.mitigations { print("  · \(m)") }
}
print()

// MARK: 4. Demonstrate DP noise on a VO2 max reading

print("─── Differential Privacy Demo ───────────────────────────────")

let cfg = HealthDPConfig.config(for: .vo2Max)
// Sensitivity of the cohort mean: one participant shifts it by at most range/n
let vo2Range = 60.0          // physiological range 20–80 mL/kg/min
let cohortN = 5000.0
let cohortDelta = 1.0 / (cohortN * cohortN)   // 4e-8
let gaussian = GaussianMechanism(globalSensitivity: vo2Range / cohortN, delta: cohortDelta)
let epsilonPerQuery = 1.0 / 5.0 / 12.0   // budget/metrics/rounds = 0.0167
let trueVO2 = 52.4   // mL/kg/min

print("True VO2 max: \(trueVO2) mL/kg/min")
print("Cohort mean sensitivity Δ: \(String(format: "%.4f", vo2Range / cohortN)) mL/kg/min")
print("Noise σ (ε=\(String(format: "%.4f", epsilonPerQuery))): \(String(format: "%.4f", gaussian.sigma(epsilon: epsilonPerQuery)))")
print("Expected error on cohort mean: ±\(String(format: "%.4f", gaussian.expectedError(epsilon: epsilonPerQuery))) mL/kg/min")
print()
print("5 private cohort-mean readings with ε=\(String(format: "%.4f", epsilonPerQuery)):")
let trueCohortMean = trueVO2
for i in 1...5 {
    let privatised = trueCohortMean + gaussian.privatise(0.0, epsilon: epsilonPerQuery)
    print("  Reading \(i): \(String(format: "%.4f", privatised)) mL/kg/min  (error: \(String(format: "%+.4f", privatised - trueCohortMean)))")
}
print()

// MARK: 5. DP budget summary

print("─── DP Budget Summary ───────────────────────────────────────")
let dpPlan = analysis.dpPlan
print("Total epsilon budget: \(dpPlan.epsilonBudget)")
print("Epsilon used: \(String(format: "%.4f", dpPlan.totalEpsilonUsed))")
print("Within budget: \(dpPlan.isWithinBudget ? "YES" : "NO")")
print()
for qp in dpPlan.queryPlans {
    print("  \(qp.metric.rawValue):")
    print("    mechanism: \(qp.mechanism), ε/query: \(String(format: "%.4f", qp.epsilonPerQuery))")
    print("    queries: \(qp.numberOfQueries), total ε: \(String(format: "%.4f", qp.totalEpsilonForMetric))")
    print("    expected error/query: ±\(String(format: "%.3f", qp.expectedErrorPerQuery))")
}
print()

// MARK: 6. Consent checker

print("─── Consent Scope Check ─────────────────────────────────────")
let violations = analysis.consentViolations
if violations.isEmpty {
    print("No consent violations. Study is within declared scope.")
} else {
    for v in violations {
        print("[\(v.severity.rawValue)] \(v.description)")
        print("  → \(v.recommendation)")
    }
}
print()

print("╔══════════════════════════════════════════════════════════════╗")
print("║  Overall readiness: \(analysis.overallReadiness.rawValue)")
print("╚══════════════════════════════════════════════════════════════╝")
