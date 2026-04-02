# HealthPrivacyStudyDesigner

A Python-Swift package for designing privacy-preserving health research studies. Implements differential privacy, k-anonymity, federated aggregation planning, consent scope enforcement, and re-identification risk estimation. Proposes designs, audit tooling, and review checklists collection. Built for systems like Apple’s HealthKit, ResearchKit, and Data Governance Boards.

## Overview

```
HealthPrivacyStudyDesigner
├── StudyDesigner              ← Main API
├── DifferentialPrivacy
│   ├── LaplaceMechanism       ← (ε,0)-DP for counts/histograms
│   ├── GaussianMechanism      ← (ε,δ)-DP for continuous health metrics
│   ├── EpsilonBudget          ← Thread-safe budget tracker
│   ├── HealthDPConfig         ← Per-metric DP recommendations
│   └── DifferentialPrivacyPlanner
├── KAnonymity
│   └── KAnonymityChecker      ← Equivalence class analysis + suppression
├── ConsentScope
│   └── ConsentScopeChecker    ← Protocol-vs-consent compliance
├── FederatedPlan
│   ├── FederatedAggregationPlan
│   └── FederatedPlanValidator
├── ReidentificationRisk
│   └── ReidentificationRiskEstimator  ← Journalist/prosecutor/marketer risk
└── Models
    ├── StudyProtocol
    ├── HealthMetricType       ← 21 metrics, tiered by HIPAA sensitivity
    ├── Participant
    └── ConsentScope
```
## Quick start

```swift
import HealthPrivacyStudyDesigner

// 1. Define consent scope
let consent = ConsentScope(
    permittedMetrics: [.heartRate, .heartRateVariability, .vo2Max],
    rawDataPermitted: false,
    withdrawalWithDeletionSupported: true,
    identifiableRetentionDays: 60
)

// 2. Define federated aggregation plan
let fedPlan = FederatedAggregationPlan(
    topology: .secureMPC,
    minimumParticipantsPerRound: 500,
    secureAggregationEnabled: true,
    firstPartyServer: true,
    roundFrequency: .weekly
)

// 3. Define the study protocol
let study = StudyProtocol(
    name: "Cardiorespiratory Fitness Study",
    description: "12-week study of VO2 max in Fitness+ participants.",
    targetMetrics: [.heartRate, .heartRateVariability, .vo2Max],
    collectionStrategy: .secureAggregation,
    duration: StudyDuration(weeks: 12, samplingIntervalHours: 24),
    targetCohortSize: 5000,
    minimumKAnonymity: 5,
    epsilonBudget: 1.0,
    consentScope: consent,
    federatedPlan: fedPlan
)

// 4. Analyse privacy readiness
let designer = StudyDesigner()
let analysis = designer.analyse(protocol: study)

print(analysis.overallReadiness)   // READY_TO_LAUNCH / NEEDS_REVISION / BLOCKED
print(analysis.summary)
```

## Differential privacy

```swift
// Privatise a VO2 max reading with Gaussian DP
let mechanism = GaussianMechanism(globalSensitivity: 60.0)
let privateVO2 = mechanism.privatise(52.4, epsilon: 0.3)
// Expected error: ±mechanism.expectedError(epsilon: 0.3)

// Track epsilon budget across a study
let budget = EpsilonBudget(totalEpsilon: 1.0)
budget.consume(0.3)    // returns true
print(budget.remaining)  // 0.7

// Get per-metric DP recommendations
let cfg = HealthDPConfig.config(for: .heartRate)
// cfg.recommendedEpsilonPerQuery: 0.3
// cfg.mechanism: .gaussian
// cfg.sensitivityRange: 40...200 bpm
```

## K-anonymity

```swift
let checker = KAnonymityChecker()
let report = checker.check(participants: cohort, k: 5)

print(report.satisfiesKAnonymity)    // Bool
print(report.minimumClassSize)       // smallest equivalence class
print(report.suppressionRequired)    // participants to drop for compliance

// Remove violating participants
let safeCohort = checker.suppress(participants: cohort, k: 5)
```

## Consent scope enforcement

```swift
let checker = ConsentScopeChecker()
let violations = checker.check(protocol: study)

for violation in violations {
    print("[\(violation.severity.rawValue)] \(violation.description)")
    print("Fix: \(violation.recommendation)")
}
// Severity levels: BLOCKER, WARNING, ADVISORY
```

## Re-identification risk

```swift
let estimator = ReidentificationRiskEstimator()
let risk = estimator.estimate(participants: cohort)

print(risk.journalistRisk)   // < 0.09 = LOW (HIPAA Expert Determination threshold)
print(risk.riskTier)         // LOW / MODERATE / HIGH / CRITICAL
print(risk.mitigations)      // Actionable recommendations
```

## Metric sensitivity tiers

| Tier | Metrics | Recommended ε/query |
|------|---------|---------------------|
| 1 — Low | Steps, active energy, stand hours | 0.5 |
| 2 — Moderate | Heart rate, HRV, VO2 max, respiratory rate | 0.2–0.3 |
| 3 — High | Blood oxygen, glucose, sleep stages, ECG | 0.05–0.15 |
| 4 — Very high | Mobility, symptom logging, audio exposure | 0.05 |

## Design principles

**Data minimisation by default.** `HealthMetricType` encodes sensitivity tiers; the planner refuses to over-allocate epsilon to low-value metrics.

**Consent is a hard gate.** `ConsentScopeChecker` produces `BLOCKER`-severity violations that must be resolved before a study can proceed — not merely advisory warnings.

**k-anonymity before any release.** The checker and suppression helper enforce this as a pre-publication step, consistent with HIPAA Safe Harbor and Apple Research IRB requirements.

**Federated-first.** The `FederatedAggregationPlan` and validator nudge designs toward on-device and secure MPC topologies, reflecting Apple's privacy-by-default architecture.

## Running the demo

```bash
swift run hpsd-demo
```

## Tests

```bash
swift test
```

## License

MIT
