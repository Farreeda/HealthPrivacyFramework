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
    sensitivity_range: Tuple[float, float]   # (min, max) plausible value
    global_sensitivity: float                 # L1/L2 sensitivity for the query
    unit: str
    default_epsilon_share: float = 1.0       # relative weight when splitting budget


_METRIC_CONFIGS: Dict[str, MetricDPConfig] = {
    "vo2_max": MetricDPConfig(
        metric="vo2_max",
        sensitivity_range=(20.0, 80.0),
        global_sensitivity=5.0,
        unit="mL/kg/min",
        default_epsilon_share=1.2,
    ),
    "resting_heart_rate": MetricDPConfig(
        metric="resting_heart_rate",
        sensitivity_range=(40.0, 110.0),
        global_sensitivity=10.0,
        unit="bpm",
        default_epsilon_share=1.0,
    ),
    "heart_rate_variability": MetricDPConfig(
        metric="heart_rate_variability",
        sensitivity_range=(10.0, 120.0),
        global_sensitivity=15.0,
        unit="ms",
        default_epsilon_share=0.8,
    ),
    "active_energy_burned": MetricDPConfig(
        metric="active_energy_burned",
        sensitivity_range=(0.0, 1500.0),
        global_sensitivity=100.0,
        unit="kcal",
        default_epsilon_share=0.7,
    ),
    "step_count": MetricDPConfig(
        metric="step_count",
        sensitivity_range=(0.0, 30000.0),
        global_sensitivity=2000.0,
        unit="steps",
        default_epsilon_share=0.6,
    ),
}

def _get_config(metric: str) -> MetricDPConfig:
    return _METRIC_CONFIGS.get(metric, MetricDPConfig(
        metric=metric,
        sensitivity_range=(0.0, 100.0),
        global_sensitivity=10.0,
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
    """Adds calibrated Gaussian noise for (ε, δ)-DP."""

    def __init__(self, sensitivity: float, epsilon: float, delta: float = 1e-5):
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.delta = delta
        self.sigma = self._calibrate()

    def _calibrate(self) -> float:
        # Classic Gaussian mechanism: σ = sqrt(2 ln(1.25/δ)) · Δf / ε
        if self.epsilon <= 0 or self.delta <= 0:
            return float("inf")
        return math.sqrt(2 * math.log(1.25 / self.delta)) * self.sensitivity / self.epsilon

    @property
    def noise_std(self) -> float:
        return self.sigma

    def __repr__(self) -> str:
        return (f"GaussianMechanism(Δ={self.sensitivity}, ε={self.epsilon:.5f}, "
                f"δ={self.delta}, σ={self.sigma:.4f})")


class LaplaceMechanism:
    """Adds calibrated Laplace noise for ε-DP."""

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
    expected_error_per_query: float   # ≈ σ for Gaussian


@dataclass
class DPPlan:
    epsilon_budget: float
    query_plans: List[QueryPlan]
    delta: float = 1e-5

    @property
    def total_epsilon_used(self) -> float:
        # Simple composition
        return sum(qp.epsilon_per_query * qp.num_queries for qp in self.query_plans)

    @property
    def is_within_budget(self) -> bool:
        return self.total_epsilon_used <= self.epsilon_budget + 1e-9


class DifferentialPrivacyPlanner:
    """Allocates the study's ε budget across metrics and query rounds."""

    DEFAULT_DELTA = 1e-5

    def plan(self, study) -> DPPlan:
        from ._study import StudyProtocol  # avoid circular at module level

        metrics = study.target_metrics
        budget = study.epsilon_budget
        duration = study.duration
        delta = self.DEFAULT_DELTA

        # Number of query rounds per metric = total_samples
        rounds = duration.total_samples

        # Weighted epsilon split
        configs = [_get_config(m) for m in metrics]
        total_weight = sum(c.default_epsilon_share for c in configs)

        query_plans: List[QueryPlan] = []
        for cfg in configs:
            # Per-query epsilon: weight_share / rounds
            eps_share = (cfg.default_epsilon_share / total_weight) * budget
            eps_per_query = eps_share / rounds

            mech = GaussianMechanism(
                sensitivity=cfg.global_sensitivity,
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
