"""LINDDUN-based privacy risk scoring."""
from __future__ import annotations
from dataclasses import dataclass
from typing import List


@dataclass
class PrivacyRiskScore:
    threat_category: str
    score: float          # 0–25
    tier: str             # LOW / MEDIUM / HIGH / CRITICAL
    notes: str


class PrivacyRiskScorer:
    """Scores a list of (likelihood, impact) threat tuples."""

    TIERS = [(20, "CRITICAL"), (12, "HIGH"), (6, "MEDIUM"), (0, "LOW")]

    def _tier(self, score: float) -> str:
        for threshold, label in self.TIERS:
            if score >= threshold:
                return label
        return "LOW"

    def score(self, threats) -> List[PrivacyRiskScore]:
        results = []
        for row in threats:
            category, _, likelihood, impact, mitigation, _ = row
            raw = likelihood * impact
            tier = self._tier(raw)
            results.append(PrivacyRiskScore(
                threat_category=category,
                score=float(raw),
                tier=tier,
                notes=mitigation,
            ))
        return results
