"""Differential privacy mechanisms, budget tracking, and planner."""
from __future__ import annotations
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Per-feature configuration registry
# ---------------------------------------------------------------------------

@dataclass
class FeatureDPConfig:
    """DP configuration for a single numeric feature."""
    feature: str
    sensitivity_range: Tuple[float, float]   # (min, max) plausible clipped value
    global_sensitivity: float                 # raw L2 sensitivity (full range)
    unit: str = "units"
    default_epsilon_share: float = 1.0        # relative weight when splitting budget


class DPConfigRegistry:
    """
    Registry for per-feature DP configurations.

    Use this to register domain-specific features (medical, financial,
    behavioral, etc.) before running the planner.

    Example
    -------
    >>> registry = DPConfigRegistry()
    >>> registry.register(FeatureDPConfig(
    ...     feature="age",
    ...     sensitivity_range=(18.0, 90.0),
    ...     global_sensitivity=72.0,
    ...     unit="years",
    ... ))
    >>> config = registry.get("age")
    """

    _DEFAULT_CONFIG = FeatureDPConfig(
        feature="unknown",
        sensitivity_range=(0.0, 100.0),
        global_sensitivity=100.0,
    )

    def __init__(self) -> None:
        self._configs: Dict[str, FeatureDPConfig] = {}

    def register(self, config: FeatureDPConfig) -> None:
        """Register a feature configuration, overwriting any existing entry."""
        self._configs[config.feature] = config

    def get(self, feature: str) -> FeatureDPConfig:
        """Return the config for *feature*, or a safe default if not found."""
        return self._configs.get(feature, self._DEFAULT_CONFIG)

    def all_features(self) -> List[str]:
        return list(self._configs.keys())


# ---------------------------------------------------------------------------
# Privacy budget
# ---------------------------------------------------------------------------

@dataclass
class EpsilonBudget:
    """
    Tracks cumulative epsilon spend against a fixed total budget.

    Parameters
    ----------
    total : float
        The maximum allowable epsilon for the session.
    """
    total: float
    _spent: float = field(default=0.0, init=False)

    def spend(self, epsilon: float) -> None:
        """Deduct *epsilon* from the remaining budget."""
        self._spent += epsilon

    @property
    def remaining(self) -> float:
        return self.total - self._spent

    @property
    def is_exhausted(self) -> bool:
        return self._spent > self.total


# ---------------------------------------------------------------------------
# Mechanisms
# ---------------------------------------------------------------------------

class GaussianMechanism:
    """
    Adds calibrated Gaussian noise for (ε, δ)-differential privacy.

    The noise standard deviation is set to:

        σ = sqrt(2 · ln(1.25 / δ)) · Δf / ε

    Parameters
    ----------
    sensitivity : float
        L2 sensitivity of the query (Δf).
    epsilon : float
        Privacy loss parameter ε > 0.
    delta : float
        Failure probability δ ∈ (0, 1). Defaults to 1e-5.
    """

    def __init__(self, sensitivity: float, epsilon: float, delta: float = 1e-5):
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.delta = delta
        self.sigma = self._calibrate()

    def _calibrate(self) -> float:
        if self.epsilon <= 0 or self.delta <= 0:
            return float("inf")
        return math.sqrt(2 * math.log(1.25 / self.delta)) * self.sensitivity / self.epsilon

    @property
    def noise_std(self) -> float:
        """Standard deviation of the noise distribution."""
        return self.sigma

    def __repr__(self) -> str:
        return (
            f"GaussianMechanism(Δ={self.sensitivity:.6f}, ε={self.epsilon:.5f}, "
            f"δ={self.delta:.2e}, σ={self.sigma:.6f})"
        )


class LaplaceMechanism:
    """
    Adds calibrated Laplace noise for ε-differential privacy.

    The noise scale is set to:

        b = Δf / ε

    Parameters
    ----------
    sensitivity : float
        L1 sensitivity of the query (Δf).
    epsilon : float
        Privacy loss parameter ε > 0.
    """

    def __init__(self, sensitivity: float, epsilon: float):
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.scale = sensitivity / epsilon if epsilon > 0 else float("inf")

    @property
    def noise_scale(self) -> float:
        """Scale parameter b of the Laplace distribution."""
        return self.scale

    def __repr__(self) -> str:
        return (
            f"LaplaceMechanism(Δ={self.sensitivity}, ε={self.epsilon:.5f}, "
            f"b={self.scale:.4f})"
        )


# ---------------------------------------------------------------------------
# Planner
# ---------------------------------------------------------------------------

@dataclass
class QueryPlan:
    """DP plan for a single feature across all query rounds."""
    feature: str
    epsilon_per_query: float
    num_queries: int
    expected_error_per_query: float   # σ of noise added to the cohort mean


@dataclass
class DPPlan:
    """
    Complete differential-privacy plan for a multi-feature study.

    Attributes
    ----------
    epsilon_budget : float
        The total epsilon budget provided at planning time.
    query_plans : list of QueryPlan
        One entry per feature, detailing per-round epsilon and expected noise.
    delta : float
        The δ used across all Gaussian mechanisms.
    """
    epsilon_budget: float
    query_plans: List[QueryPlan]
    delta: float

    @property
    def total_epsilon_used(self) -> float:
        """Total epsilon consumed via sequential composition."""
        return sum(qp.epsilon_per_query * qp.num_queries for qp in self.query_plans)

    @property
    def is_within_budget(self) -> bool:
        return self.total_epsilon_used <= self.epsilon_budget + 1e-9


class DifferentialPrivacyPlanner:
    """
    Allocates an ε budget across features and query rounds.

    Parameters
    ----------
    registry : DPConfigRegistry
        Holds per-feature sensitivity and weight configurations.

    Noise model
    -----------
    We query the *cohort mean* each round. The L2 sensitivity of the mean
    under add/remove adjacency is:

        Δ_mean = clip_range / cohort_size

    where ``clip_range = sensitivity_range[1] - sensitivity_range[0]``.

    δ is set to ``1 / cohort_size²``, the standard choice that keeps the
    (ε, δ)-DP guarantee meaningful at cohort scale.

    Budget composition: simple sequential composition across rounds, so:

        ε_per_query = ε_allocated_to_feature / num_rounds
    """

    def __init__(self, registry: DPConfigRegistry) -> None:
        self.registry = registry

    def plan(
        self,
        features: List[str],
        epsilon_budget: float,
        cohort_size: int,
        num_rounds: int,
    ) -> DPPlan:
        """
        Build a DP query plan.

        Parameters
        ----------
        features : list of str
            Feature names to include. Each must have a config in the registry,
            or the default fallback config will be used.
        epsilon_budget : float
            Total ε available for the entire study.
        cohort_size : int
            Number of participants; used to calibrate sensitivity and δ.
        num_rounds : int
            Number of query rounds (e.g. weekly snapshots).

        Returns
        -------
        DPPlan
        """
        delta = 1.0 / (cohort_size ** 2)
        configs = [self.registry.get(f) for f in features]
        total_weight = sum(c.default_epsilon_share for c in configs)

        query_plans: List[QueryPlan] = []
        for cfg in configs:
            eps_feature = (cfg.default_epsilon_share / total_weight) * epsilon_budget
            eps_per_query = eps_feature / num_rounds

            clip_range = cfg.sensitivity_range[1] - cfg.sensitivity_range[0]
            mean_sensitivity = clip_range / cohort_size

            mech = GaussianMechanism(
                sensitivity=mean_sensitivity,
                epsilon=eps_per_query,
                delta=delta,
            )
            query_plans.append(QueryPlan(
                feature=cfg.feature,
                epsilon_per_query=eps_per_query,
                num_queries=num_rounds,
                expected_error_per_query=mech.sigma,
            ))

        return DPPlan(
            epsilon_budget=epsilon_budget,
            query_plans=query_plans,
            delta=delta,
        )
