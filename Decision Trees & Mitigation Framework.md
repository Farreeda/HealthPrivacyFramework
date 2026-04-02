# Health Privacy Review: Decision Trees & Mitigation Framework
Version: 1.0
Audience: Privacy Engineers, Feature Leads, Data Governance Board
Applies to: Health, Wellness, Fitness features + Health Research Studies



## Tree 1: Does this data need to be collected at all?

| Step | Question | If YES | If NO |
|------|----------|--------|-------|
| 1 | Is the data strictly necessary for the core health feature? | Go to Step 2 |  Stop. Do not collect. Re-architect. |
| 2 | Can the feature work with less granular data? | Modify spec: lower granularity, then re-evaluate from Step 1 | Go to Step 3 |
| 3 | Is the data derived from a sensitive health category? (Heart, Reproductive, Mental Health) |  **High risk** → Proceed to Tree 2 |  Moderate risk → Proceed to Tree 2 |

---

## Tree 2: Which privacy technology should you use?

| Scenario | Technology | Implementation Rule |
|----------|------------|---------------------|
| Feature needs to identify a specific user's data over time |  On-device processing | Never send raw data to servers. Process entirely on device. |
| Feature needs population aggregates only | Differential Privacy | ε (epsilon) ≤ 1.0 for health data. Enforce per-user budget. |
| Feature needs cross-user matching without revealing non-matches | Private Set Intersection (PSI) | Use blind signatures or cuckoo filters. Never reveal non-intersecting data. |
| Apple must store historical data per user | End-to-end encryption | User-controlled key. Apple should not hold the decryption key. |
| No need for server-side storage | Local-only | Data never leaves the device. Period. |

**Apple health-specific defaults:**
- **Heart rate variability, menstrual cycle, mental health** → On-device or E2EE only
- **Workout summaries, step counts** → Differential privacy if aggregated
- **Research studies** → Private Set Intersection for enrollment verification

---

## Tree 3: Research study data collection approval

| Step | Gate | Pass Condition | Fail Action |
|------|------|----------------|--------------|
| 1 | Informed consent | Explicitly covers every data point being collected |  Reject study entirely |
| 2 | Data minimization | Study collects no more than the research question requires |  Trim to minimal set, then return to Step 1 |
| 3 | Re-identification risk | Participants cannot be re-identified from the data | Apply differential privacy + k-anonymity (k ≥ 20) |
| 4 | Query budget | Per-participant query limits defined | Set budget before any data access |
| 5 | Ongoing audit | Data Governance Board review | Required every 90 days |

---

## Tree 4: Production audit – finding privacy bugs in customer data

**Run this checklist against every logging/telemetry system:**

| Check | If YES → Bug Severity | Mitigation |
|-------|----------------------|-------------|
| Are raw sensor logs leaving the device? |  **CRITICAL** | Stop feature immediately. Escalate to Data Governance Board. |
| Does aggregated data include fine-grained timestamps (< 1 hour)? |  **High risk** (re-identification possible) | Remove timestamps OR bin to daily granularity. If clinical justification exists, add Laplace noise ±30 min. |
| Does the data include user-resolvable IDs (e.g., UUID that persists across sessions)? |  **CRITICAL** | Replace with ephemeral session IDs that rotate every 24 hours. |
| Is data being sent to any third-party SDK? |  **CRITICAL** | Apple does not allow this in health features. Remove immediately. |

---

## Tree 5: Data Governance Board review – stored health data

**For data already on Apple servers:**

| Question | If NO → Action Required |
|----------|-------------------------|
| Is retention period explicitly stated and minimized? | Define policy. Default: 30 days max unless clinical study with approved extension. Re-audit in 30 days. |
| Is data encrypted with user-controlled key (Apple cannot access)? |  High risk. Re-encrypt under user key. Document timeline. |
| Can engineers query this data for debugging? |  Prohibit. Use synthetic data for debugging instead. |
| Is every query logged and auditable? | Implement query logging before any access is granted. |

---

## Immediate termination

| Exposure | Action | Rationale |
|----------|--------|-----------|
| Raw GPS while logging a workout |  Reject | Use start/end points only. Full path re-identifies home/work. |
| User-resolvable IDs in analytics |  Reject | Use differential privacy instead. |
| Third-party SDK in health feature |  Reject | Apple policy. No exceptions. |
| Data retention > 90 days without DGB review |  Reject | Requires explicit Data Governance Board approval. |
| Health research without IRB-equivalent review |  Reject | Non-starter. Cannot proceed. |


