"""Differential privacy mechanisms, budget tracking, and planner."""
from __future__ import annotations
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Per-metric configuration registry
# ---------------------------------------------------------------------------

@dataclass
class MetricDPConfig:
    metric: str
    sensitivity_range: Tuple[float, float]   # (min, max) plausible clipped value
    global_sensitivity: float                 # raw L2 sensitivity (full range)
    unit: str
    default_epsilon_share: float = 1.0       # relative weight when splitting budget


_METRIC_CONFIGS: Dict[str, MetricDPConfig] = {
    "vo2_max": MetricDPConfig(
        metric="vo2_max",
        sensitivity_range=(20.0, 80.0),
        global_sensitivity=60.0,
        unit="mL/kg/min",
        default_epsilon_share=1.2,
    ),
    "resting_heart_rate": MetricDPConfig(
        metric="resting_heart_rate",
        sensitivity_range=(40.0, 110.0),
        global_sensitivity=70.0,
        unit="bpm",
        default_epsilon_share=1.0,
    ),
    "heart_rate_variability": MetricDPConfig(
        metric="heart_rate_variability",
        sensitivity_range=(10.0, 120.0),
        global_sensitivity=110.0,
        unit="ms",
        default_epsilon_share=0.8,
    ),
    "active_energy_burned": MetricDPConfig(
        metric="active_energy_burned",
        sensitivity_range=(0.0, 1500.0),
        global_sensitivity=1500.0,
        unit="kcal",
        default_epsilon_share=0.7,
    ),
    "step_count": MetricDPConfig(
        metric="step_count",
        sensitivity_range=(0.0, 30000.0),
        global_sensitivity=30000.0,
        unit="steps",
        default_epsilon_share=0.6,
    ),
}


def _get_config(metric: str) -> MetricDPConfig:
    return _METRIC_CONFIGS.get(metric, MetricDPConfig(
        metric=metric,
        sensitivity_range=(0.0, 100.0),
        global_sensitivity=100.0,
        unit="units",
        default_epsilon_share=1.0,
    ))


class HealthDPConfig:
    """Static registry for per-metric DP configuration."""

    @staticmethod
    def config(metric: str) -> MetricDPConfig:
        return _get_config(metric)


# ---------------------------------------------------------------------------
# Privacy budget
# ---------------------------------------------------------------------------

@dataclass
class EpsilonBudget:
    total: float
    _spent: float = field(default=0.0, init=False)

    def spend(self, epsilon: float) -> None:
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
    """Adds calibrated Gaussian noise for (ε, δ)-DP.

    σ = sqrt(2 ln(1.25/δ)) · Δf / ε
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
        return self.sigma

    def __repr__(self) -> str:
        return (f"GaussianMechanism(Δ={self.sensitivity:.6f}, ε={self.epsilon:.5f}, "
                f"δ={self.delta:.2e}, σ={self.sigma:.6f})")


class LaplaceMechanism:
    """Adds calibrated Laplace noise for ε-DP.

    b = Δf / ε
    """

    def __init__(self, sensitivity: float, epsilon: float):
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.scale = sensitivity / epsilon if epsilon > 0 else float("inf")

    @property
    def noise_scale(self) -> float:
        return self.scale

    def __repr__(self) -> str:
        return (f"LaplaceMechanism(Δ={self.sensitivity}, ε={self.epsilon:.5f}, "
                f"b={self.scale:.4f})")


# ---------------------------------------------------------------------------
# Planner
# ---------------------------------------------------------------------------

@dataclass
class QueryPlan:
    metric: str
    epsilon_per_query: float
    num_queries: int
    expected_error_per_query: float   # σ of noise added to the cohort mean


@dataclass
class DPPlan:
    epsilon_budget: float
    query_plans: List[QueryPlan]
    delta: float

    @property
    def total_epsilon_used(self) -> float:
        # Sequential composition across all rounds for all metrics
        return sum(qp.epsilon_per_query * qp.num_queries for qp in self.query_plans)

    @property
    def is_within_budget(self) -> bool:
        return self.total_epsilon_used <= self.epsilon_budget + 1e-9


class DifferentialPrivacyPlanner:
    """Allocates the study's ε budget across metrics and query rounds.

    Noise model
    -----------
    We query the *cohort mean* each round. The L2 sensitivity of the mean
    under add/remove adjacency is:

        Δ_mean = clip_range / cohort_size

    where clip_range = sensitivity_range[1] - sensitivity_range[0].

    δ is set to 1 / (cohort_size²), the standard choice that keeps the
    (ε, δ)-DP guarantee meaningful at cohort scale.

    Budget composition: simple sequential across rounds, so
        ε_per_query = ε_allocated_to_metric / num_rounds.
    """

    def plan(self, study) -> DPPlan:
        metrics = study.target_metrics
        budget = study.epsilon_budget
        n = study.target_cohort_size
        rounds = study.duration.total_samples   # = weeks

        # δ = 1/n² is the standard choice for meaningful (ε,δ)-DP at scale n
        delta = 1.0 / (n ** 2)

        configs = [_get_config(m) for m in metrics]
        total_weight = sum(c.default_epsilon_share for c in configs)

        query_plans: List[QueryPlan] = []
        for cfg in configs:
            # Epsilon allocated to this metric (weighted share of total budget)
            eps_metric = (cfg.default_epsilon_share / total_weight) * budget
            # Per-round epsilon via sequential composition
            eps_per_query = eps_metric / rounds

            # Sensitivity of the cohort mean:
            # one participant shifts the mean by at most clip_range / n
            clip_range = cfg.sensitivity_range[1] - cfg.sensitivity_range[0]
            mean_sensitivity = clip_range / n

            mech = GaussianMechanism(
                sensitivity=mean_sensitivity,
                epsilon=eps_per_query,
                delta=delta,
            )
            query_plans.append(QueryPlan(
                metric=cfg.metric,
                epsilon_per_query=eps_per_query,
                num_queries=rounds,
                expected_error_per_query=mech.sigma,
            ))

        return DPPlan(
            epsilon_budget=budget,
            query_plans=query_plans,
            delta=delta,
        )