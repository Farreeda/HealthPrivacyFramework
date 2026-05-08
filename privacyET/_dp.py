"""General-purpose differential privacy library with budget tracking and planning."""

from __future__ import annotations
import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple, Callable, Any
from enum import Enum


@dataclass
class SensitivityBounds:
    """Bounds for a private data field after clipping."""
    min_value: float
    max_value: float
    
    @property
    def range(self) -> float:
        """Total range for sensitivity calculation."""
        return self.max_value - self.min_value


@dataclass
class FeatureConfig:
    """Configuration for a feature requiring differential privacy."""
    name: str
    sensitivity_bounds: SensitivityBounds
    unit: str = ""
    budget_weight: float = 1.0  # Relative weight for budget allocation


@dataclass
class QueryPlan:
    """Plan for repeated queries on a feature."""
    feature_name: str
    epsilon_per_query: float
    num_queries: int
    expected_noise_std: float  # Standard deviation of added noise


@dataclass
class PrivacyBudget:
    """Privacy budget tracking with sequential composition."""
    total_epsilon: float
    total_delta: float = 1e-5
    _spent_epsilon: float = field(default=0.0, init=False)
    _spent_delta: float = field(default=0.0, init=False)
    
    def spend(self, epsilon: float, delta: float = 0.0) -> bool:
        """Spend budget, returns True if within budget."""
        if self._spent_epsilon + epsilon > self.total_epsilon + 1e-9:
            return False
        if self._spent_delta + delta > self.total_delta + 1e-9:
            return False
        self._spent_epsilon += epsilon
        self._spent_delta += delta
        return True
    
    @property
    def remaining_epsilon(self) -> float:
        return self.total_epsilon - self._spent_epsilon
    
    @property
    def remaining_delta(self) -> float:
        return self.total_delta - self._spent_delta
    
    @property
    def is_exhausted(self) -> bool:
        return self.remaining_epsilon <= 0 or self.remaining_delta <= 0


# ---------------------------------------------------------------------------
# Privacy mechanisms (domain-agnostic)
# ---------------------------------------------------------------------------

class NoiseMechanism:
    """Base class for privacy mechanisms."""
    pass


class GaussianMechanism(NoiseMechanism):
    """Adds calibrated Gaussian noise for (ε, δ)-DP.
    
    σ = sqrt(2·ln(1.25/δ)) · Δ / ε
    """
    
    def __init__(self, sensitivity: float, epsilon: float, delta: float = 1e-5):
        if epsilon <= 0 or delta <= 0 or sensitivity <= 0:
            raise ValueError("Epsilon, delta, and sensitivity must be positive")
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.delta = delta
        self.sigma = self._calibrate_sigma()
    
    def _calibrate_sigma(self) -> float:
        return (math.sqrt(2 * math.log(1.25 / self.delta)) *
                self.sensitivity / self.epsilon)
    
    def add_noise(self, value: float) -> float:
        """Add Gaussian noise to a value."""
        import random
        return value + random.gauss(0, self.sigma)
    
    @property
    def noise_std(self) -> float:
        return self.sigma
    
    def __repr__(self) -> str:
        return (f"GaussianMechanism(Δ={self.sensitivity:.6f}, ε={self.epsilon:.5f}, "
                f"δ={self.delta:.2e}, σ={self.sigma:.6f})")


class LaplaceMechanism(NoiseMechanism):
    """Adds calibrated Laplace noise for ε-DP.
    
    scale = Δ / ε
    """
    
    def __init__(self, sensitivity: float, epsilon: float):
        if epsilon <= 0 or sensitivity <= 0:
            raise ValueError("Epsilon and sensitivity must be positive")
        self.sensitivity = sensitivity
        self.epsilon = epsilon
        self.scale = sensitivity / epsilon
    
    def add_noise(self, value: float) -> float:
        """Add Laplace noise to a value."""
        import random
        return value + random.laplace(0, self.scale)
    
    @property
    def noise_scale(self) -> float:
        return self.scale
    
    def __repr__(self) -> str:
        return (f"LaplaceMechanism(Δ={self.sensitivity}, ε={self.epsilon:.5f}, "
                f"scale={self.scale:.4f})")


# ---------------------------------------------------------------------------
# Query sensitivity calculators (pluggable)
# ---------------------------------------------------------------------------

class SensitivityCalculator:
    """Abstract base for computing query sensitivity."""
    
    def compute_sensitivity(self, feature_config: FeatureConfig,
                           query_context: Dict[str, Any]) -> float:
        """Compute sensitivity for a specific query type."""
        raise NotImplementedError


class MeanSensitivityCalculator(SensitivityCalculator):
    """Sensitivity for computing mean of values.
    
    Δ_mean = (max - min) / dataset_size
    """
    
    def compute_sensitivity(self, feature_config: FeatureConfig,
                           query_context: Dict[str, Any]) -> float:
        dataset_size = query_context.get('dataset_size', 1)
        return feature_config.sensitivity_bounds.range / dataset_size


class SumSensitivityCalculator(SensitivityCalculator):
    """Sensitivity for computing sum of values.
    
    Δ_sum = max - min
    """
    
    def compute_sensitivity(self, feature_config: FeatureConfig,
                           query_context: Dict[str, Any]) -> float:
        return feature_config.sensitivity_bounds.range


class CountSensitivityCalculator(SensitivityCalculator):
    """Sensitivity for counting records.
    
    Δ_count = 1 (adding/removing one record changes count by at most 1)
    """
    
    def compute_sensitivity(self, feature_config: FeatureConfig,
                           query_context: Dict[str, Any]) -> float:
        return 1.0


# ---------------------------------------------------------------------------
# Privacy budget planner
# ---------------------------------------------------------------------------

class PrivacyPlanner:
    """Allocates privacy budget across multiple features and query rounds."""
    
    def __init__(self,
                 budget: PrivacyBudget,
                 sensitivity_calculator: Optional[SensitivityCalculator] = None):
        self.budget = budget
        self.sensitivity_calculator = sensitivity_calculator or MeanSensitivityCalculator()
    
    def plan_queries(self,
                    features: List[FeatureConfig],
                    num_query_rounds: int,
                    query_context: Optional[Dict[str, Any]] = None,
                    budget_allocation: str = 'weighted') -> List[QueryPlan]:
        """Create query plans allocating budget across features.
        
        Args:
            features: List of features to query
            num_query_rounds: Number of times each feature will be queried
            query_context: Context for sensitivity (e.g., {'dataset_size': n})
            budget_allocation: 'weighted', 'equal', or 'proportional_to_sensitivity'
        
        Returns:
            List of QueryPlan objects
        """
        query_context = query_context or {}
        
        # Calculate epsilon per feature
        if budget_allocation == 'equal':
            eps_per_feature = self.budget.total_epsilon / len(features)
        elif budget_allocation == 'weighted':
            total_weight = sum(f.budget_weight for f in features)
            eps_per_feature = [
                (f.budget_weight / total_weight) * self.budget.total_epsilon
                for f in features
            ]
        else:
            # Proportional to sensitivity
            sensitivities = [
                self.sensitivity_calculator.compute_sensitivity(f, query_context)
                for f in features
            ]
            total_sens = sum(sensitivities)
            eps_per_feature = [
                (sens / total_sens) * self.budget.total_epsilon
                for sens in sensitivities
            ]
        
        # Create query plans
        plans = []
        for feature, eps_feature in zip(features, eps_per_feature):
            eps_per_query = eps_feature / num_query_rounds
            
            sensitivity = self.sensitivity_calculator.compute_sensitivity(
                feature, query_context
            )
            
            mechanism = GaussianMechanism(
                sensitivity=sensitivity,
                epsilon=eps_per_query,
                delta=self.budget.total_delta / (len(features) * num_query_rounds)
            )
            
            plans.append(QueryPlan(
                feature_name=feature.name,
                epsilon_per_query=eps_per_query,
                num_queries=num_query_rounds,
                expected_noise_std=mechanism.noise_std
            ))
        
        return plans
    
    def create_mechanism(self,
                        feature_config: FeatureConfig,
                        query_context: Dict[str, Any],
                        epsilon_share: float = 1.0) -> NoiseMechanism:
        """Create a noise mechanism for a specific query."""
        sensitivity = self.sensitivity_calculator.compute_sensitivity(
            feature_config, query_context
        )
        epsilon = epsilon_share * self.budget.remaining_epsilon
        
        return GaussianMechanism(
            sensitivity=sensitivity,
            epsilon=epsilon,
            delta=self.budget.total_delta
        )


# ---------------------------------------------------------------------------
# Example usage (now generic)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Example 1: Health metrics (the original use case)
    health_features = [
        FeatureConfig("vo2_max", SensitivityBounds(20.0, 80.0), "mL/kg/min", 1.2),
        FeatureConfig("resting_hr", SensitivityBounds(40.0, 110.0), "bpm", 1.0),
        FeatureConfig("step_count", SensitivityBounds(0.0, 30000.0), "steps", 0.6),
    ]
    
    budget = PrivacyBudget(total_epsilon=10.0, total_delta=1e-5)
    planner = PrivacyPlanner(budget, MeanSensitivityCalculator())
    
    plans = planner.plan_queries(
        features=health_features,
        num_query_rounds=52,  # weekly queries for a year
        query_context={'dataset_size': 1000}  # cohort size
    )
    
    for plan in plans:
        print(f"{plan.feature_name}: ε={plan.epsilon_per_query:.4f}/query, "
              f"σ={plan.expected_noise_std:.3f}")
    
    # Example 2: Financial data (completely different domain)
    financial_features = [
        FeatureConfig("transaction_amount", SensitivityBounds(0.0, 10000.0), "USD", 1.0),
        FeatureConfig("account_balance", SensitivityBounds(-5000.0, 50000.0), "USD", 2.0),
    ]
    
    sum_calculator = SumSensitivityCalculator()
    planner_finance = PrivacyPlanner(budget, sum_calculator)
    
    finance_plans = planner_finance.plan_queries(
        features=financial_features,
        num_query_rounds=12,  # monthly
        query_context={},
        budget_allocation='weighted'
    )
