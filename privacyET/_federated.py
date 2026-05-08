"""Federated learning / aggregation plan and validator."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Dict, List, Optional


TOPOLOGY_STRENGTH = {
    "secure_mpc": "very_high",
    "secure_aggregation": "high",
    "federated_averaging": "medium",
    "central": "low",
}


@dataclass
class FederatedAggregationPlan:
    topology: str = "secure_aggregation"
    minimum_participants_per_round: int = 100
    secure_aggregation_enabled: bool = True
    first_party_server: bool = True
    round_frequency: str = "weekly"
    server_side_dp: Optional[Dict] = None

    @property
    def privacy_strength(self) -> str:
        return TOPOLOGY_STRENGTH.get(self.topology, "unknown")


@dataclass
class ValidationIssue:
    severity: str   # CRITICAL | WARNING | INFO
    code: str
    message: str


class FederatedPlanValidator:
    MIN_PARTICIPANTS_THRESHOLD = 50
    RECOMMENDED_PARTICIPANTS = 100

    def validate(
        self,
        plan: FederatedAggregationPlan,
        cohort_size: int = 0,
    ) -> List[ValidationIssue]:
        issues: List[ValidationIssue] = []

        # Check topology
        if plan.topology == "central":
            issues.append(ValidationIssue(
                severity="CRITICAL",
                code="TOPOLOGY_CENTRAL",
                message="Central topology sends raw data to server. Use secure_aggregation or secure_mpc.",
            ))

        # Participant floor
        if plan.minimum_participants_per_round < self.MIN_PARTICIPANTS_THRESHOLD:
            issues.append(ValidationIssue(
                severity="CRITICAL",
                code="MIN_PARTICIPANTS_LOW",
                message=(f"minimum_participants_per_round={plan.minimum_participants_per_round} "
                         f"is below hard floor of {self.MIN_PARTICIPANTS_THRESHOLD}."),
            ))
        elif plan.minimum_participants_per_round < self.RECOMMENDED_PARTICIPANTS:
            issues.append(ValidationIssue(
                severity="WARNING",
                code="MIN_PARTICIPANTS_RECOMMENDED",
                message=(f"minimum_participants_per_round={plan.minimum_participants_per_round} "
                         f"is below recommended {self.RECOMMENDED_PARTICIPANTS}."),
            ))

        # Secure aggregation
        if not plan.secure_aggregation_enabled:
            issues.append(ValidationIssue(
                severity="WARNING",
                code="SECURE_AGG_DISABLED",
                message="Secure aggregation is disabled. Individual updates visible to server.",
            ))

        # Third-party server
        if not plan.first_party_server:
            issues.append(ValidationIssue(
                severity="WARNING",
                code="THIRD_PARTY_SERVER",
                message="Third-party aggregation server requires a BAA / DPA.",
            ))

        # Server-side DP
        if plan.server_side_dp:
            eps = plan.server_side_dp.get("epsilon_per_round", None)
            if eps is not None and eps > 1.0:
                issues.append(ValidationIssue(
                    severity="WARNING",
                    code="SERVER_DP_HIGH_EPSILON",
                    message=f"server_side_dp epsilon_per_round={eps} is high (>1.0).",
                ))

        # Cohort feasibility
        if cohort_size > 0:
            rounds_per_year = {"daily": 365, "weekly": 52, "monthly": 12}.get(
                plan.round_frequency, 52
            )
            expected_per_round = cohort_size / rounds_per_year
            if expected_per_round < plan.minimum_participants_per_round:
                issues.append(ValidationIssue(
                    severity="WARNING",
                    code="COHORT_TOO_SMALL_FOR_FREQUENCY",
                    message=(
                        f"Cohort of {cohort_size} at '{plan.round_frequency}' frequency gives "
                        f"~{expected_per_round:.0f} participants/round, below "
                        f"minimum_participants_per_round={plan.minimum_participants_per_round}."
                    ),
                ))

        return issues
