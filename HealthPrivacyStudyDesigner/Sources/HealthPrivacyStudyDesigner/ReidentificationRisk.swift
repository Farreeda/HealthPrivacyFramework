import Foundation

// MARK: - Re-identification risk estimator

/// Estimates the risk that an anonymised health dataset can be re-identified
/// using combinations of quasi-identifiers and auxiliary information.
///
/// Based on the Dankar & El Emam (2012) risk model and the Latanya Sweeney
/// population uniqueness framework adapted for health wearable data.
public struct ReidentificationRiskEstimator: Sendable {

    public struct RiskReport: Sendable {
        /// Estimated fraction of records that are unique in the US population
        /// given their quasi-identifier combination.
        public let estimatedPopulationUniqueness: Double
        /// Estimated fraction of records that are unique within the released dataset.
        public let datasetUniqueness: Double
        /// Journalist attack risk: probability a motivated adversary with a target in mind
        /// can confirm identity using this dataset.
        public let journalistRisk: Double
        /// Prosecutor attack risk: probability an adversary who already suspects a specific
        /// individual can confirm their presence in the dataset.
        public let prosecutorRisk: Double
        /// Marketer risk: expected fraction of correct re-identifications in a bulk attack.
        public let marketerRisk: Double
        /// Overall risk tier.
        public let riskTier: RiskTier
        public let mitigations: [String]

        public enum RiskTier: String, Sendable {
            case low      = "LOW"       // < 9% journalist risk (HIPAA Expert Determination threshold)
            case moderate = "MODERATE"  // 9–20%
            case high     = "HIGH"      // 20–50%
            case critical = "CRITICAL"  // > 50%
        }
    }

    public init() {}

    /// Estimates re-identification risk for a dataset.
    /// - Parameters:
    ///   - participants: The study cohort (or a sample).
    ///   - auxiliaryDataAvailable: Whether an adversary plausibly has auxiliary data
    ///     (e.g. social media, public records). True for most health research contexts.
    ///   - populationSize: Relevant population size (default: US adult population).
    public func estimate(
        participants: [Participant],
        auxiliaryDataAvailable: Bool = true,
        populationSize: Int = 258_000_000
    ) -> RiskReport {

        let n = Double(participants.count)
        guard n > 0 else {
            return RiskReport(
                estimatedPopulationUniqueness: 1.0,
                datasetUniqueness: 1.0,
                journalistRisk: 1.0,
                prosecutorRisk: 1.0,
                marketerRisk: 1.0,
                riskTier: .critical,
                mitigations: ["Dataset is empty."]
            )
        }

        // Compute equivalence class sizes
        var qiCounts: [String: Int] = [:]
        for p in participants {
            let key = "\(p.ageBucket.rawValue)|\(p.biologicalSex.rawValue)|\(p.region)"
            qiCounts[key, default: 0] += 1
        }

        // Dataset uniqueness: fraction of participants in a class of size 1
        let uniqueInDataset = qiCounts.values.filter { $0 == 1 }.count
        let datasetUniqueness = Double(uniqueInDataset) / n

        // Population uniqueness: estimate using sampling ratio
        let samplingFraction = n / Double(populationSize)
        // Expected number of population-unique records: Poisson approximation
        // P(unique in pop) ≈ exp(-E[class size in population])
        let avgClassSizeInPop = 1.0 / (Double(qiCounts.count) / Double(populationSize))
        let populationUniqueness = exp(-avgClassSizeInPop) * (auxiliaryDataAvailable ? 1.5 : 1.0)
        let clampedPopUniqueness = min(1.0, max(0.0, populationUniqueness))

        // Journalist risk (El Emam model): probability the highest-risk record is re-identified
        let maxRisk = qiCounts.values.map { 1.0 / Double($0) }.max() ?? 1.0
        let journalistRisk = min(1.0, maxRisk * (auxiliaryDataAvailable ? 1.3 : 1.0))

        // Prosecutor risk: conditional on adversary knowing target is in dataset
        let avgRisk = qiCounts.values.map { 1.0 / Double($0) }.reduce(0, +) / Double(qiCounts.count)
        let prosecutorRisk = min(1.0, avgRisk * (auxiliaryDataAvailable ? 1.2 : 1.0))

        // Marketer risk: sampling-fraction-adjusted average
        let marketerRisk = min(1.0, prosecutorRisk * samplingFraction * 1000)

        // Determine tier
        let tier: RiskReport.RiskTier
        switch journalistRisk {
        case ..<0.09: tier = .low
        case 0.09..<0.20: tier = .moderate
        case 0.20..<0.50: tier = .high
        default: tier = .critical
        }

        let mitigations = buildMitigations(
            tier: tier,
            datasetUniqueness: datasetUniqueness,
            populationUniqueness: clampedPopUniqueness,
            qiCounts: qiCounts,
            participants: participants
        )

        return RiskReport(
            estimatedPopulationUniqueness: clampedPopUniqueness,
            datasetUniqueness: datasetUniqueness,
            journalistRisk: journalistRisk,
            prosecutorRisk: prosecutorRisk,
            marketerRisk: marketerRisk,
            riskTier: tier,
            mitigations: mitigations
        )
    }

    // MARK: Private helpers

    private func buildMitigations(
        tier: RiskReport.RiskTier,
        datasetUniqueness: Double,
        populationUniqueness: Double,
        qiCounts: [String: Int],
        participants: [Participant]
    ) -> [String] {
        var m: [String] = []

        if datasetUniqueness > 0.05 {
            m.append(
                "\(String(format: "%.1f", datasetUniqueness * 100))% of records are unique in the dataset. " +
                "Apply k-anonymity suppression (k ≥ 5) before any publication or data release."
            )
        }

        if populationUniqueness > 0.30 {
            m.append(
                "Estimated population uniqueness (\(String(format: "%.1f", populationUniqueness * 100))%) is high. " +
                "Generalise age buckets (5-year → 10-year), use coarser geographic regions, or apply l-diversity to sensitive attributes."
            )
        }

        // Check for quasi-identifier metrics
        let qiMetrics = participants.flatMap(\.metrics).filter(\.isQuasiIdentifier)
        if !qiMetrics.isEmpty {
            let unique = Set(qiMetrics.map(\.rawValue))
            m.append(
                "Dataset includes quasi-identifier health metrics: \(unique.joined(separator: ", ")). " +
                "These can be combined with step counts and location data to uniquely identify individuals. " +
                "Apply local DP noise before aggregation."
            )
        }

        if tier == .critical || tier == .high {
            m.append(
                "Risk level requires Data Governance Board review before any data release. " +
                "Consider synthetic data generation as an alternative to releasing raw-anonymised records."
            )
        }

        return m
    }
}
