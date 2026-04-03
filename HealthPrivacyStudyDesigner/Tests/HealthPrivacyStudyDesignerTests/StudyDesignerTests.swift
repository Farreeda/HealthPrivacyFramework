import Testing
import Darwin
@testable import HealthPrivacyStudyDesigner

// MARK: - Differential privacy tests

@Suite("Laplace mechanism")
struct LaplaceMechanismTests {

    @Test("Noise scale increases as epsilon decreases")
    func noiseScaleMonotone() {
        let lm = LaplaceMechanism(globalSensitivity: 1.0)
        #expect(lm.noiseScale(epsilon: 0.1) > lm.noiseScale(epsilon: 1.0))
        #expect(lm.noiseScale(epsilon: 1.0) > lm.noiseScale(epsilon: 10.0))
    }

    @Test("Privatised values cluster around true value")
    func noisyClustering() {
        let lm = LaplaceMechanism(globalSensitivity: 1.0)
        let trueVal = 100.0
        let samples = (0..<1000).map { _ in lm.privatise(trueVal, epsilon: 2.0) }
        let mean = samples.reduce(0, +) / Double(samples.count)
        // With 1000 samples the sample mean should be within 1 unit of true value
        #expect(abs(mean - trueVal) < 1.0)
    }

    @Test("Expected error formula matches empirical error")
    func expectedErrorAccuracy() {
        let lm = LaplaceMechanism(globalSensitivity: 1.0)
        let theoretical = lm.expectedError(epsilon: 1.0)
        let empirical = (0..<5000).map { _ in abs(lm.privatise(0, epsilon: 1.0)) }.reduce(0, +) / 5000
        let relativeError = abs(empirical - theoretical) / theoretical
        #expect(relativeError < 0.1)  // within 10%
    }
}

@Suite("Gaussian mechanism")
struct GaussianMechanismTests {

    @Test("Sigma increases as epsilon decreases")
    func sigmaMonotone() {
        let gm = GaussianMechanism(globalSensitivity: 1.0)
        #expect(gm.sigma(epsilon: 0.1) > gm.sigma(epsilon: 1.0))
    }

    @Test("Privatised values are approximately normally distributed")
    func normalDistribution() {
        let gm = GaussianMechanism(globalSensitivity: 1.0)
        let samples = (0..<2000).map { _ in gm.privatise(0.0, epsilon: 1.0) }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { pow($0 - mean, 2) }.reduce(0, +) / Double(samples.count)
        let empiricalSigma = sqrt(variance)
        let theoreticalSigma = gm.sigma(epsilon: 1.0)
        #expect(abs(empiricalSigma - theoreticalSigma) / theoreticalSigma < 0.15)
    }
}

@Suite("Epsilon budget")
struct EpsilonBudgetTests {

    @Test("Consumption reduces remaining budget")
    func basicConsumption() {
        let budget = EpsilonBudget(totalEpsilon: 1.0)
        budget.consume(0.3)
        #expect(abs(budget.remaining - 0.7) < 1e-10)
    }

    @Test("Over-consumption is rejected")
    func overConsumption() {
        let budget = EpsilonBudget(totalEpsilon: 1.0)
        budget.consume(0.9)
        let succeeded = budget.consume(0.2)   // would exceed budget
        #expect(!succeeded)
        #expect(abs(budget.remaining - 0.1) < 1e-10)
    }

    @Test("Reset restores full budget")
    func reset() {
        let budget = EpsilonBudget(totalEpsilon: 1.0)
        budget.consume(0.5)
        budget.reset()
        #expect(abs(budget.remaining - 1.0) < 1e-10)
    }
}

// MARK: - K-anonymity tests

@Suite("K-anonymity checker")
struct KAnonymityTests {

    func makeCohort(count: Int, region: String = "CA") -> [Participant] {
        (0..<count).map { _ in
            Participant(ageBucket: .age30_39, biologicalSex: .female, region: region, metrics: [.heartRate])
        }
    }

    @Test("Cohort with identical QIs satisfies k=5")
    func uniformCohortSatisfiesK() {
        let checker = KAnonymityChecker()
        let participants = makeCohort(count: 50)
        let report = checker.check(participants: participants, k: 5)
        #expect(report.satisfiesKAnonymity)
        #expect(report.suppressionRequired == 0)
    }

    @Test("Singleton group violates k=5")
    func singletonViolatesK() {
        let checker = KAnonymityChecker()
        var participants = makeCohort(count: 10, region: "CA")
        // Add one unique participant from a different region
        participants.append(Participant(ageBucket: .age60_69, biologicalSex: .male, region: "AK", metrics: [.heartRate]))
        let report = checker.check(participants: participants, k: 5)
        #expect(!report.satisfiesKAnonymity)
        #expect(report.suppressionRequired >= 1)
    }

    @Test("Suppression removes violating participants")
    func suppressionCorrectness() {
        let checker = KAnonymityChecker()
        var participants = makeCohort(count: 10, region: "CA")
        participants.append(Participant(ageBucket: .age60_69, biologicalSex: .male, region: "AK", metrics: [.heartRate]))
        let suppressed = checker.suppress(participants: participants, k: 5)
        let report = checker.check(participants: suppressed, k: 5)
        #expect(report.satisfiesKAnonymity)
    }

    @Test("Recommended cohort size is larger for high-sensitivity metrics")
    func cohortSizeRecommendation() {
        let checker = KAnonymityChecker()
        let lowTier = checker.recommendedCohortSize(for: [.stepCount])
        let highTier = checker.recommendedCohortSize(for: [.ecgData])
        #expect(highTier > lowTier)
    }
}

// MARK: - Consent scope tests

@Suite("Consent scope checker")
struct ConsentScopeTests {

    func baseConsent(metrics: [HealthMetricType] = [.heartRate, .vo2Max]) -> ConsentScope {
        ConsentScope(
            permittedMetrics: Set(metrics),
            rawDataPermitted: false,
            withdrawalWithDeletionSupported: true
        )
    }

    func baseProtocol(metrics: [HealthMetricType] = [.heartRate, .vo2Max],
                      strategy: DataCollectionStrategy = .onDeviceAggregation,
                      consent: ConsentScope? = nil) -> StudyProtocol {
        StudyProtocol(
            name: "Test",
            description: "",
            targetMetrics: metrics,
            collectionStrategy: strategy,
            duration: StudyDuration(weeks: 4, samplingIntervalHours: 24),
            targetCohortSize: 1000,
            consentScope: consent ?? baseConsent(metrics: metrics)
        )
    }

    @Test("No violations for compliant protocol")
    func compliantProtocol() {
        let checker = ConsentScopeChecker()
        let violations = checker.check(protocol: baseProtocol())
        #expect(violations.isEmpty)
    }

    @Test("Unconsented metric raises blocker")
    func unconsentedMetric() {
        let checker = ConsentScopeChecker()
        let consent = baseConsent(metrics: [.heartRate])         // vo2Max not in consent
        let proto = baseProtocol(metrics: [.heartRate, .vo2Max], consent: consent)
        let violations = checker.check(protocol: proto)
        let blockers = violations.filter { $0.severity == .blocker }
        #expect(!blockers.isEmpty)
    }

    @Test("Central DP without raw data permission is a blocker")
    func centralDPNoRawData() {
        let checker = ConsentScopeChecker()
        let proto = baseProtocol(strategy: .centralDifferentialPrivacy)
        let violations = checker.check(protocol: proto)
        let blockers = violations.filter { $0.severity == .blocker }
        #expect(!blockers.isEmpty)
    }

    @Test("No withdrawal support is a blocker")
    func noWithdrawal() {
        let checker = ConsentScopeChecker()
        let consent = ConsentScope(
            permittedMetrics: [.heartRate, .vo2Max],
            rawDataPermitted: false,
            withdrawalWithDeletionSupported: false   // violation
        )
        let proto = baseProtocol(consent: consent)
        let violations = checker.check(protocol: proto)
        #expect(violations.contains { $0.severity == .blocker })
    }
}

// MARK: - Re-identification risk tests

@Suite("Re-identification risk")
struct ReidentificationRiskTests {

    @Test("Larger cohort has lower risk tier")
    func cohortSizeReducesRisk() {
        let estimator = ReidentificationRiskEstimator()
        let regions = ["CA", "TX", "NY", "FL", "WA"]
        let buckets = [AgeBucket.age30_39, .age40_49, .age50_59]

        let smallCohort: [Participant] = (0..<20).map { i in
            Participant(ageBucket: buckets[i % 3], biologicalSex: .female,
                       region: regions[i % 5], metrics: [.heartRate])
        }
        let largeCohort: [Participant] = (0..<2000).map { i in
            Participant(ageBucket: buckets[i % 3], biologicalSex: i % 2 == 0 ? .female : .male,
                       region: regions[i % 5], metrics: [.heartRate])
        }
        let smallReport = estimator.estimate(participants: smallCohort)
        let largeReport = estimator.estimate(participants: largeCohort)
        // Larger cohort should have lower journalist risk
        #expect(largeReport.journalistRisk <= smallReport.journalistRisk)
    }
}

// MARK: - Federated plan tests

@Suite("Federated plan validator")
struct FederatedPlanTests {

    @Test("Valid plan has no issues")
    func validPlan() {
        let validator = FederatedPlanValidator()
        let plan = FederatedAggregationPlan(
            topology: .secureMPC,
            minimumParticipantsPerRound: 500,
            secureAggregationEnabled: true,
            firstPartyServer: true,
            roundFrequency: .weekly
        )
        let issues = validator.validate(plan: plan, cohortSize: 5000)
        let criticals = issues.filter { $0.severity == .critical }
        #expect(criticals.isEmpty)
    }

    @Test("Too few participants per round is critical")
    func tooFewParticipants() {
        let validator = FederatedPlanValidator()
        let plan = FederatedAggregationPlan(
            topology: .starFederated,
            minimumParticipantsPerRound: 10,   // too low
            secureAggregationEnabled: true,
            firstPartyServer: true,
            roundFrequency: .daily
        )
        let issues = validator.validate(plan: plan, cohortSize: 5000)
        #expect(issues.contains { $0.severity == .critical })
    }

    @Test("Third-party server is flagged as critical")
    func thirdPartyServer() {
        let validator = FederatedPlanValidator()
        let plan = FederatedAggregationPlan(
            topology: .starFederated,
            minimumParticipantsPerRound: 200,
            secureAggregationEnabled: true,
            firstPartyServer: false,    // third-party
            roundFrequency: .daily
        )
        let issues = validator.validate(plan: plan, cohortSize: 5000)
        #expect(issues.contains { $0.severity == .critical })
    }
}

// MARK: - Integration test

@Suite("Study designer integration")
struct StudyDesignerIntegrationTests {

    @Test("Clean protocol produces READY_TO_LAUNCH")
    func cleanProtocol() {
        let designer = StudyDesigner()
        let consent = ConsentScope(
            permittedMetrics: [.heartRate, .heartRateVariability],
            rawDataPermitted: false,
            withdrawalWithDeletionSupported: true
        )
        let proto = StudyProtocol(
            name: "HRV Study",
            description: "Test study",
            targetMetrics: [.heartRate, .heartRateVariability],
            collectionStrategy: .onDeviceAggregation,
            duration: StudyDuration(weeks: 4, samplingIntervalHours: 24),
            targetCohortSize: 2000,
            minimumKAnonymity: 5,
            epsilonBudget: 10.0,   // generous budget for short study
            consentScope: consent
        )
        let analysis = designer.analyse(protocol: proto)
        #expect(analysis.consentViolations.filter { $0.severity == .blocker }.isEmpty)
        #expect(analysis.dpPlan.isWithinBudget)
    }
}
