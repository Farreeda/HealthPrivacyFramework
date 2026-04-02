"""Study protocol, consent, and study designer."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional


# ---------------------------------------------------------------------------
# Study building blocks
# ---------------------------------------------------------------------------

@dataclass
class StudyDuration:
    weeks: int
    sampling_interval_hours: int = 24

    @property
    def total_samples(self) -> int:
        """Number of aggregation rounds = one per week of the study."""
        return self.weeks


@dataclass
class ConsentScope:
    permitted_metrics: List[str] = field(default_factory=list)
    raw_data_permitted: bool = False
    withdrawal_with_deletion_supported: bool = True
    identifiable_retention_days: int = 90
    healthkit_linkage_permitted: bool = False
    future_research_permitted: bool = False
    third_party_research_permitted: bool = False

    @property
    def is_conservative(self) -> bool:
        return (
            not self.raw_data_permitted
            and not self.healthkit_linkage_permitted
            and not self.future_research_permitted
            and not self.third_party_research_permitted
            and self.withdrawal_with_deletion_supported
            and self.identifiable_retention_days <= 90
        )


@dataclass
class StudyProtocol:
    name: str
    description: str
    target_metrics: List[str]
    collection_strategy: str
    duration: StudyDuration
    target_cohort_size: int
    minimum_k_anonymity: int
    epsilon_budget: float
    consent_scope: ConsentScope


# ---------------------------------------------------------------------------
# Consent scope checker
# ---------------------------------------------------------------------------

@dataclass
class ConsentViolation:
    severity: str
    description: str
    recommendation: str


class ConsentScopeChecker:
    def check(self, study: StudyProtocol) -> List[ConsentViolation]:
        violations: List[ConsentViolation] = []
        cs = study.consent_scope
        permitted = set(cs.permitted_metrics)

        for metric in study.target_metrics:
            if metric not in permitted:
                violations.append(ConsentViolation(
                    severity="CRITICAL",
                    description=f"Metric '{metric}' collected but not listed in consent scope.",
                    recommendation=f"Add '{metric}' to ConsentScope.permitted_metrics or remove from study."
                ))

        if cs.raw_data_permitted and study.collection_strategy == "secure_aggregation":
            violations.append(ConsentViolation(
                severity="WARNING",
                description="Consent permits raw data off-device but collection_strategy is secure_aggregation.",
                recommendation="Either disable raw_data_permitted or document the discrepancy."
            ))

        if not cs.withdrawal_with_deletion_supported:
            violations.append(ConsentViolation(
                severity="WARNING",
                description="Withdrawal-with-deletion not supported.",
                recommendation="Support participant data deletion on withdrawal (GDPR Art 17)."
            ))

        if cs.identifiable_retention_days > 180:
            violations.append(ConsentViolation(
                severity="WARNING",
                description=f"Identifiable data retained for {cs.identifiable_retention_days} days.",
                recommendation="Reduce identifiable retention to ≤180 days."
            ))

        return violations


# ---------------------------------------------------------------------------
# Study designer / analysis
# ---------------------------------------------------------------------------

@dataclass
class StudyAnalysis:
    summary: str


class StudyDesigner:
    def analyse(self, study: StudyProtocol) -> StudyAnalysis:
        lines = []
        lines.append(f"Study:  {study.name}")
        lines.append(f"{'─' * 60}")
        lines.append(f"Duration:          {study.duration.weeks} weeks  "
                     f"(sampling every {study.duration.sampling_interval_hours}h)")
        lines.append(f"Cohort target:     {study.target_cohort_size:,} participants")
        lines.append(f"Metrics:           {', '.join(study.target_metrics)}")
        lines.append(f"Collection:        {study.collection_strategy}")
        lines.append(f"Min k-anonymity:   k={study.minimum_k_anonymity}")
        lines.append(f"ε budget:          {study.epsilon_budget:.3f}")
        lines.append(f"")
        lines.append(f"Consent profile:   {'conservative ✓' if study.consent_scope.is_conservative else 'permissive ⚠'}")
        lines.append(f"  Raw data off-device:  {study.consent_scope.raw_data_permitted}")
        lines.append(f"  Retention (days):     {study.consent_scope.identifiable_retention_days}")
        lines.append(f"  Withdrawal+deletion:  {study.consent_scope.withdrawal_with_deletion_supported}")
        lines.append(f"")

        # Rough feasibility
        total_queries = study.duration.total_samples * len(study.target_metrics)
        eps_per_query = study.epsilon_budget / max(total_queries, 1)
        lines.append(f"Total query rounds: {total_queries}")
        lines.append(f"ε per query:        {eps_per_query:.6f}")

        if eps_per_query < 0.001:
            lines.append(f"⚠ Very tight per-query budget — noise will be high.")
        else:
            lines.append(f"✓ Per-query budget is workable.")

        return StudyAnalysis(summary="\n".join(lines))
