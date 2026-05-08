"""Core enums and simple value types."""
from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional


class HealthMetricType(str, Enum):
    VO2_MAX = "vo2_max"
    RESTING_HEART_RATE = "resting_heart_rate"
    HEART_RATE_VARIABILITY = "heart_rate_variability"
    ACTIVE_ENERGY_BURNED = "active_energy_burned"
    STEP_COUNT = "step_count"
    SLEEP_DURATION = "sleep_duration"


class SensitivityTier(int, Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3


class AgeBucket(str, Enum):
    AGE_18_29 = "18-29"
    AGE_30_39 = "30-39"
    AGE_40_49 = "40-49"
    AGE_50_59 = "50-59"
    AGE_60_69 = "60-69"
    AGE_70_PLUS = "70+"


class BiologicalSex(str, Enum):
    MALE = "male"
    FEMALE = "female"
    NOT_SPECIFIED = "not_specified"


class LINDDUNThreat(str, Enum):
    LINKING = "Linking"
    IDENTIFYING = "Identifying"
    NON_REPUDIATION = "Non-repudiation"
    DETECTING = "Detecting"
    DATA_DISCLOSURE = "Data disclosure"
    UNAWARENESS = "Unawareness"
    NON_COMPLIANCE = "Non-compliance"
