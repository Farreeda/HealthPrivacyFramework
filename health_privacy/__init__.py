"""
health_privacy
==============
Pure-Python reference implementation of the HealthPrivacyFramework.
Mirrors the Swift package API used in Apple's internal privacy review tooling.
"""

from ._types import (
    HealthMetricType,
    SensitivityTier,
    AgeBucket,
    BiologicalSex,
    LINDDUNThreat,
)

from ._study import (
    StudyDuration,
    ConsentScope,
    ConsentScopeChecker,
    StudyProtocol,
    StudyDesigner,
)

from ._dp import (
    HealthDPConfig,
    EpsilonBudget,
    GaussianMechanism,
    LaplaceMechanism,
    DifferentialPrivacyPlanner,
)

from ._federated import (
    FederatedAggregationPlan,
    FederatedPlanValidator,
)

from ._kanon import (
    Participant,
    KAnonymityChecker,
    ReidentificationRiskEstimator,
)

from ._risk import PrivacyRiskScorer

__all__ = [
    # types
    "HealthMetricType", "SensitivityTier", "AgeBucket", "BiologicalSex", "LINDDUNThreat",
    # study
    "StudyDuration", "ConsentScope", "ConsentScopeChecker",
    "StudyProtocol", "StudyDesigner",
    # dp
    "HealthDPConfig", "EpsilonBudget",
    "GaussianMechanism", "LaplaceMechanism",
    "DifferentialPrivacyPlanner",
    # federated
    "FederatedAggregationPlan", "FederatedPlanValidator",
    # k-anonymity / risk
    "Participant", "KAnonymityChecker", "ReidentificationRiskEstimator",
    # scoring
    "PrivacyRiskScorer",
]
