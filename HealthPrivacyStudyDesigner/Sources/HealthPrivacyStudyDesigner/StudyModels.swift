import Foundation

// MARK: - Health metric types

/// Categories of health data collected in research studies, aligned with HIPAA sensitivity tiers.
public enum HealthMetricType: String, CaseIterable, Codable, Sendable {
    // Tier 1 — low sensitivity, commonly ambient
    case stepCount          = "step_count"
    case activeEnergyBurned = "active_energy_burned"
    case flightsClimbed     = "flights_climbed"
    case standHours         = "stand_hours"
    case exerciseMinutes    = "exercise_minutes"

    // Tier 2 — moderate sensitivity, inferred lifestyle
    case heartRate          = "heart_rate"
    case heartRateVariability = "heart_rate_variability"
    case respiratoryRate    = "respiratory_rate"
    case restingHeartRate   = "resting_heart_rate"
    case vo2Max             = "vo2_max"
    case walkingSpeed       = "walking_speed"

    // Tier 3 — high sensitivity, clinical significance
    case bloodOxygen        = "blood_oxygen"
    case bloodGlucose       = "blood_glucose"
    case bodyTemperature    = "body_temperature"
    case sleepStages        = "sleep_stages"
    case menstrualCycle     = "menstrual_cycle"
    case ecgData            = "ecg_data"
    case irregularRhythm    = "irregular_rhythm_notification"

    // Tier 4 — very high sensitivity, rare / identifiable
    case audioExposure      = "audio_exposure"          // disability signal
    case mobilityMetrics    = "mobility_metrics"         // fall detection
    case symptomLogging     = "symptom_logging"          // self-reported condition

    /// HIPAA sensitivity tier (1 = lowest, 4 = highest).
    public var sensitivityTier: Int {
        switch self {
        case .stepCount, .activeEnergyBurned, .flightsClimbed, .standHours, .exerciseMinutes:
            return 1
        case .heartRate, .heartRateVariability, .respiratoryRate, .restingHeartRate, .vo2Max, .walkingSpeed:
            return 2
        case .bloodOxygen, .bloodGlucose, .bodyTemperature, .sleepStages, .menstrualCycle, .ecgData, .irregularRhythm:
            return 3
        case .audioExposure, .mobilityMetrics, .symptomLogging:
            return 4
        }
    }

    /// Whether this metric can plausibly re-identify a participant when combined with quasi-identifiers.
    public var isQuasiIdentifier: Bool {
        switch self {
        case .walkingSpeed, .sleepStages, .menstrualCycle, .mobilityMetrics, .heartRateVariability:
            return true
        default:
            return false
        }
    }

    /// Minimum recommended noise scale (σ) for Gaussian DP mechanism.
    public var recommendedNoiseScale: Double {
        switch sensitivityTier {
        case 1: return 0.5
        case 2: return 1.5
        case 3: return 4.0
        case 4: return 8.0
        default: return 4.0
        }
    }
}

// MARK: - Participant model

/// Represents a de-identified study participant with quasi-identifier attributes
/// used for k-anonymity analysis.
public struct Participant: Codable, Sendable {
    public let id: UUID
    /// Age bucket (e.g. 20–29). Use ranges, never exact ages.
    public let ageBucket: AgeBucket
    public let biologicalSex: BiologicalSex
    /// Region at the country-subdivision level (no finer granularity).
    public let region: String
    /// BMI tier rather than raw value.
    public let bmiTier: BMITier?
    public let metrics: [HealthMetricType]

    public init(
        id: UUID = UUID(),
        ageBucket: AgeBucket,
        biologicalSex: BiologicalSex,
        region: String,
        bmiTier: BMITier? = nil,
        metrics: [HealthMetricType]
    ) {
        self.id = id
        self.ageBucket = ageBucket
        self.biologicalSex = biologicalSex
        self.region = region
        self.bmiTier = bmiTier
        self.metrics = metrics
    }
}

public enum AgeBucket: String, CaseIterable, Codable, Sendable {
    case under18  = "<18"
    case age18_29 = "18-29"
    case age30_39 = "30-39"
    case age40_49 = "40-49"
    case age50_59 = "50-59"
    case age60_69 = "60-69"
    case age70plus = "70+"
}

public enum BiologicalSex: String, CaseIterable, Codable, Sendable {
    case male          = "male"
    case female        = "female"
    case notSpecified  = "not_specified"
}

public enum BMITier: String, CaseIterable, Codable, Sendable {
    case underweight  = "underweight"      // <18.5
    case normal       = "normal"           // 18.5–24.9
    case overweight   = "overweight"       // 25–29.9
    case obese        = "obese"            // 30+
}

// MARK: - Study protocol

/// Defines the full privacy-preserving study protocol.
public struct StudyProtocol: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let targetMetrics: [HealthMetricType]
    public let collectionStrategy: DataCollectionStrategy
    public let duration: StudyDuration
    public let targetCohortSize: Int
    public let minimumKAnonymity: Int
    public let epsilonBudget: Double            // total DP epsilon for the study
    public let consentScope: ConsentScope
    public let federatedPlan: FederatedAggregationPlan?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        targetMetrics: [HealthMetricType],
        collectionStrategy: DataCollectionStrategy,
        duration: StudyDuration,
        targetCohortSize: Int,
        minimumKAnonymity: Int = 5,
        epsilonBudget: Double = 1.0,
        consentScope: ConsentScope,
        federatedPlan: FederatedAggregationPlan? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.targetMetrics = targetMetrics
        self.collectionStrategy = collectionStrategy
        self.duration = duration
        self.targetCohortSize = targetCohortSize
        self.minimumKAnonymity = minimumKAnonymity
        self.epsilonBudget = epsilonBudget
        self.consentScope = consentScope
        self.federatedPlan = federatedPlan
        self.createdAt = Date()
    }
}

public enum DataCollectionStrategy: String, Codable, Sendable {
    /// All computation on device; only aggregated, noised results leave the device.
    case onDeviceAggregation   = "on_device_aggregation"
    /// Cryptographically secure aggregation across participants before the server sees anything.
    case secureAggregation     = "secure_aggregation"
    /// Central collection with strong server-side DP guarantees.
    case centralDifferentialPrivacy = "central_dp"
    /// Local DP: noise added on device before transmission.
    case localDifferentialPrivacy   = "local_dp"

    public var privacyStrength: PrivacyStrength {
        switch self {
        case .onDeviceAggregation:      return .veryStrong
        case .secureAggregation:        return .strong
        case .localDifferentialPrivacy: return .strong
        case .centralDifferentialPrivacy: return .moderate
        }
    }
}

public enum PrivacyStrength: String, Codable, Sendable {
    case veryStrong = "very_strong"
    case strong     = "strong"
    case moderate   = "moderate"
    case weak       = "weak"
}

public struct StudyDuration: Codable, Sendable {
    public let weeks: Int
    public let samplingIntervalHours: Double   // how often data is sampled

    public init(weeks: Int, samplingIntervalHours: Double) {
        self.weeks = weeks
        self.samplingIntervalHours = samplingIntervalHours
    }

    public var totalSamplesPerParticipant: Int {
        let hours = Double(weeks) * 7 * 24
        return Int(hours / samplingIntervalHours)
    }
}
