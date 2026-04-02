import Foundation

// MARK: - Epsilon budget tracker

/// Tracks the differential privacy epsilon budget across a study's query sequence.
/// Epsilon is consumable — once exhausted, no more private queries can be issued.
public final class EpsilonBudget: @unchecked Sendable {

    public let totalEpsilon: Double
    private var spent: Double = 0.0
    private let lock = NSLock()

    public var remaining: Double {
        lock.lock(); defer { lock.unlock() }
        return max(0, totalEpsilon - spent)
    }

    public var isExhausted: Bool { remaining == 0 }

    public var utilizationFraction: Double {
        lock.lock(); defer { lock.unlock() }
        return min(1.0, spent / totalEpsilon)
    }

    public init(totalEpsilon: Double) {
        precondition(totalEpsilon > 0, "Epsilon must be positive")
        self.totalEpsilon = totalEpsilon
    }

    /// Attempts to consume `epsilon` from the budget.
    /// - Returns: true if the budget had enough remaining.
    @discardableResult
    public func consume(_ epsilon: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard spent + epsilon <= totalEpsilon + 1e-9 else { return false }
        spent += epsilon
        return true
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        spent = 0
    }
}

// MARK: - Noise mechanisms

/// Laplace mechanism for real-valued queries. Provides (ε, 0)-DP.
public struct LaplaceMechanism: Sendable {

    /// Global sensitivity of the query (max change in output for one participant's data changing).
    public let globalSensitivity: Double

    public init(globalSensitivity: Double) {
        self.globalSensitivity = globalSensitivity
    }

    /// Scale parameter b = sensitivity / epsilon.
    public func noiseScale(epsilon: Double) -> Double {
        globalSensitivity / epsilon
    }

    /// Adds Laplace noise to a true value for a given epsilon.
    public func privatise(_ trueValue: Double, epsilon: Double) -> Double {
        let b = noiseScale(epsilon: epsilon)
        return trueValue + sampleLaplace(scale: b)
    }

    private func sampleLaplace(scale: Double) -> Double {
        // Inverse CDF method: X = -b * sign(U) * ln(1 - 2|U - 0.5|), U ~ Uniform(0,1)
        let u = Double.random(in: 0..<1)
        let sign: Double = u < 0.5 ? -1.0 : 1.0
        return -scale * sign * log(1.0 - 2.0 * abs(u - 0.5))
    }

    /// Returns the expected absolute error for this epsilon.
    public func expectedError(epsilon: Double) -> Double {
        noiseScale(epsilon: epsilon)   // E[|Laplace(b)|] = b
    }
}

/// Gaussian mechanism for real-valued queries. Provides (ε, δ)-DP.
public struct GaussianMechanism: Sendable {

    public let globalSensitivity: Double
    public let delta: Double           // typically 1e-5 for health research

    public init(globalSensitivity: Double, delta: Double = 1e-5) {
        self.globalSensitivity = globalSensitivity
        self.delta = delta
    }

    /// Noise standard deviation σ = sqrt(2 ln(1.25/δ)) * Δ / ε
    public func sigma(epsilon: Double) -> Double {
        let c = sqrt(2.0 * log(1.25 / delta))
        return c * globalSensitivity / epsilon
    }

    public func privatise(_ trueValue: Double, epsilon: Double) -> Double {
        trueValue + sampleGaussian(sigma: sigma(epsilon: epsilon))
    }

    private func sampleGaussian(sigma: Double) -> Double {
        // Box-Muller transform
        let u1 = Double.random(in: 0..<1)
        let u2 = Double.random(in: 0..<1)
        return sigma * sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }

    public func expectedError(epsilon: Double) -> Double {
        sigma(epsilon: epsilon) * sqrt(2.0 / .pi)   // E[|N(0,σ)|]
    }
}

// MARK: - Health-specific DP configurations

/// Pre-configured DP settings for common health research queries.
public struct HealthDPConfig: Sendable {

    public struct QueryConfig: Sendable {
        public let metric: HealthMetricType
        public let mechanism: MechanismType
        public let recommendedEpsilonPerQuery: Double
        public let sensitivityRange: ClosedRange<Double>  // physiological plausible range
        public let unit: String

        public enum MechanismType: Sendable { case laplace, gaussian }
    }

    /// Returns a recommended DP configuration for a given health metric.
    public static func config(for metric: HealthMetricType) -> QueryConfig {
        switch metric {
        case .stepCount:
            return QueryConfig(metric: metric, mechanism: .laplace,
                               recommendedEpsilonPerQuery: 0.5,
                               sensitivityRange: 0...30000, unit: "steps/day")
        case .heartRate:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.3,
                               sensitivityRange: 40...200, unit: "bpm")
        case .heartRateVariability:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.2,
                               sensitivityRange: 10...150, unit: "ms RMSSD")
        case .vo2Max:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.3,
                               sensitivityRange: 20...80, unit: "mL/kg/min")
        case .sleepStages:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.15,
                               sensitivityRange: 0...480, unit: "minutes per stage")
        case .bloodOxygen:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.1,
                               sensitivityRange: 90...100, unit: "%SpO2")
        case .bloodGlucose:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.08,
                               sensitivityRange: 70...400, unit: "mg/dL")
        case .ecgData:
            return QueryConfig(metric: metric, mechanism: .gaussian,
                               recommendedEpsilonPerQuery: 0.05,
                               sensitivityRange: 0...1, unit: "mV waveform aggregate")
        default:
            return QueryConfig(metric: metric, mechanism: .laplace,
                               recommendedEpsilonPerQuery: 0.25,
                               sensitivityRange: 0...1000, unit: "raw units")
        }
    }
}

// MARK: - Study-level DP planner

public struct DifferentialPrivacyPlanner: Sendable {

    public struct QueryPlan: Sendable {
        public let metric: HealthMetricType
        public let numberOfQueries: Int          // over the study duration
        public let epsilonPerQuery: Double
        public let totalEpsilonForMetric: Double
        public let mechanism: HealthDPConfig.QueryConfig.MechanismType
        public let expectedErrorPerQuery: Double
    }

    public struct StudyDPPlan: Sendable {
        public let queryPlans: [QueryPlan]
        public let totalEpsilonUsed: Double
        public let epsilonBudget: Double
        public let isWithinBudget: Bool
        public let recommendations: [String]
    }

    public init() {}

    /// Allocates the epsilon budget across metrics and queries for a study protocol.
    public func plan(for studyProtocol: StudyProtocol) -> StudyDPPlan {
        let metrics = studyProtocol.targetMetrics
        let totalSamples = studyProtocol.duration.totalSamplesPerParticipant
        let budgetPerMetric = studyProtocol.epsilonBudget / Double(metrics.count)

        var queryPlans: [QueryPlan] = []
        var recommendations: [String] = []

        for metric in metrics {
            let cfg = HealthDPConfig.config(for: metric)
            let numQueries = totalSamples   // one query per sample interval per metric
            let epsilonPerQuery = min(cfg.recommendedEpsilonPerQuery, budgetPerMetric / Double(numQueries))
            let totalForMetric = epsilonPerQuery * Double(numQueries)

            // Calculate expected error for the chosen mechanism
            let expectedError: Double
            switch cfg.mechanism {
            case .laplace:
                let lm = LaplaceMechanism(globalSensitivity: cfg.sensitivityRange.upperBound - cfg.sensitivityRange.lowerBound)
                expectedError = lm.expectedError(epsilon: epsilonPerQuery)
            case .gaussian:
                let gm = GaussianMechanism(globalSensitivity: cfg.sensitivityRange.upperBound - cfg.sensitivityRange.lowerBound)
                expectedError = gm.expectedError(epsilon: epsilonPerQuery)
            }

            queryPlans.append(QueryPlan(
                metric: metric,
                numberOfQueries: numQueries,
                epsilonPerQuery: epsilonPerQuery,
                totalEpsilonForMetric: totalForMetric,
                mechanism: cfg.mechanism,
                expectedErrorPerQuery: expectedError
            ))

            // Flag metrics where noise will likely overwhelm signal
            let signalRange = cfg.sensitivityRange.upperBound - cfg.sensitivityRange.lowerBound
            if expectedError > signalRange * 0.25 {
                recommendations.append(
                    "\(metric.rawValue): expected error (±\(String(format: "%.1f", expectedError)) \(cfg.unit)) is >25% of physiological range. " +
                    "Consider increasing epsilon allocation or reducing sampling frequency."
                )
            }
        }

        let totalEpsilon = queryPlans.reduce(0) { $0 + $1.totalEpsilonForMetric }

        if totalEpsilon > studyProtocol.epsilonBudget {
            recommendations.insert(
                "Total epsilon (\(String(format: "%.3f", totalEpsilon))) exceeds budget (\(studyProtocol.epsilonBudget)). " +
                "Reduce sampling frequency, reduce number of metrics, or increase budget.",
                at: 0
            )
        }

        return StudyDPPlan(
            queryPlans: queryPlans,
            totalEpsilonUsed: totalEpsilon,
            epsilonBudget: studyProtocol.epsilonBudget,
            isWithinBudget: totalEpsilon <= studyProtocol.epsilonBudget + 1e-9,
            recommendations: recommendations
        )
    }
}
