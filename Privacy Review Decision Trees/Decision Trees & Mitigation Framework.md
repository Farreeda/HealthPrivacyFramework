# Health Privacy Review: Decision Trees & Mitigation Framework
Version: 1.0
Audience: Privacy Engineers, Feature Leads, Data Governance Board
Applies to: Health, Wellness, Fitness features + Health Research Studies



## Tree 1: Does this data need to be collected at all?

| Step | Question | If YES | If NO |
|------|----------|--------|-------|
| 1 | Is the data strictly necessary for the core health feature? | Go to Step 2 | ✋ Stop. Do not collect. Re-architect. |
| 2 | Can the feature work with less granular data? | Modify spec: lower granularity, then re-evaluate from Step 1 | Go to Step 3 |
| 3 | Is the data derived from a sensitive health category? (Heart, Reproductive, Mental Health) | 🔴 **High risk** → Proceed to Tree 2 | 🟡 Moderate risk → Proceed to Tree 2 |

---

## Tree 2: Which privacy technology should you use?

| Scenario | Technology | Implementation Rule |
|----------|------------|---------------------|
| Feature needs to identify a specific user's data over time | ✅ On-device processing | Never send raw data to servers. Process entirely on device. |
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
| 1 | Informed consent | Explicitly covers every data point being collected | 🚫 Reject study entirely |
| 2 | Data minimization | Study collects no more than the research question requires | 🔧 Trim to minimal set, then return to Step 1 |
| 3 | Re-identification risk | Participants cannot be re-identified from the data | Apply differential privacy + k-anonymity (k ≥ 20) |
| 4 | Query budget | Per-participant query limits defined | Set budget before any data access |
| 5 | Ongoing audit | Data Governance Board review | Required every 90 days |

---

## Tree 4: Production audit – finding privacy bugs in customer data

**Run this checklist against every logging/telemetry system:**

| Check | If YES → Bug Severity | Mitigation |
|-------|----------------------|-------------|
| Are raw sensor logs leaving the device? | 🔴 **CRITICAL** | Stop feature immediately. Escalate to Data Governance Board. |
| Does aggregated data include fine-grained timestamps (< 1 hour)? | 🟠 **High risk** (re-identification possible) | Remove timestamps OR bin to daily granularity. If clinical justification exists, add Laplace noise ±30 min. |
| Does the data include user-resolvable IDs (e.g., UUID that persists across sessions)? | 🔴 **CRITICAL** | Replace with ephemeral session IDs that rotate every 24 hours. |
| Is data being sent to any third-party SDK? | 🔴 **CRITICAL** | Apple does not allow this in health features. Remove immediately. |

---

## Tree 5: Data Governance Board review – stored health data

**For data already on Apple servers:**

| Question | If NO → Action Required |
|----------|-------------------------|
| Is retention period explicitly stated and minimized? | Define policy. Default: 30 days max unless clinical study with approved extension. Re-audit in 30 days. |
| Is data encrypted with user-controlled key (Apple cannot access)? | 🟠 High risk. Re-encrypt under user key. Document timeline. |
| Can engineers query this data for debugging? | ❌ Prohibit. Use synthetic data for debugging instead. |
| Is every query logged and auditable? | Implement query logging before any access is granted. |

---

## Non-negotiable: When to say NO

| Exposure | Action | Rationale |
|----------|--------|-----------|
| Raw GPS while logging a workout | ❌ Reject | Use start/end points only. Full path re-identifies home/work. |
| User-resolvable IDs in analytics | ❌ Reject | Use differential privacy instead. |
| Third-party SDK in health feature | ❌ Reject | Apple policy. No exceptions. |
| Data retention > 90 days without DGB review | ❌ Reject | Requires explicit Data Governance Board approval. |
| Health research without IRB-equivalent review | ❌ Reject | Non-starter. Cannot proceed. |

---

## Presenting to senior leadership (slide structure)

Per job description: *"Communicate privacy risks and potential mitigations to senior leadership"*

**Slide 1:** Feature name + one-page data flow diagram  
**Slide 2:** Top 3 privacy exposures (bullets, no jargon)  
**Slide 3:** Recommended mitigation + engineering cost estimate (T-shirt size: S/M/L)  
**Slide 4:** Worst case if we do nothing (simulated press headline)  
**Slide 5:** Clear decision: Proceed with mitigations / Redesign / Kill

## Tree 2: Which privacy technology should you use?
flowchart TD
    Start2[Start: Data must be collected] --> NeedUser{Does the feature need to<br>identify a specific user's data<br>over time?}
    
    NeedUser -->|Yes| OnDevice[On-device processing<br>Never send raw data to servers]
    NeedUser -->|No| QAgg{Does the feature only need<br>population aggregates?}
    
    QAgg -->|Yes| DP[Differential Privacy<br>epsilon ≤ 1.0 for health data]
    QAgg -->|No, needs cross-user matching| PSI[Private Set Intersection<br>without revealing non-matches]
    
    OnDevice --> Retention{Does Apple need to store<br>historical data per user?}
    Retention -->|Yes| Encrypted[End-to-end encrypted +<br>separate user-controlled key]
    Retention -->|No| LocalOnly[Data never leaves device]
    
    DP --> Budget[Enforce per-user privacy budget]
    PSI --> BlindSig[Use blind signatures or<br>cuckoo filters]



Heart rate variability, menstrual cycle, mental health assessments → On-device or E2EE only.

Workout summaries, step counts → Differential privacy if aggregated.

Research studies → Private Set Intersection for enrollment verification without exposing identities.

## Tree 3: Research study data collection approval


flowchart TD
    Study[New health research study] --> Consent{Informed consent<br>explicitly covers this data?}
    Consent -->|No| RejectStudy[ Reject. Cannot collect.]
    Consent -->|Yes| Minimize{Does the study collect more<br>data than the research question requires?}
    
    Minimize -->|Yes| Trim[ Trim to minimal set]
    Minimize -->|No| DeId{Can participants be<br>re-identified from this data?}
    
    DeId -->|Yes| DPStudy[Differential privacy +<br>k-anonymity ≥ 20]
    DeId -->|No| BudgetStudy[Set per-participant<br>query budget]
    
    DPStudy --> Audit[Data Governance Board<br>audit required every 90 days]
    BudgetStudy --> Audit
    Trim --> ReReview[Return to consent step]

##Tree 4: Production audit: Finding privacy bugs in customer data
flowchart TD
    Audit[Start: Audit of live feature] --> Logs{Are raw sensor logs<br>leaving the device?}
    Logs -->|Yes| Critical[CRITICAL BUG – stop feature]
    Logs -->|No| Timestamp{Does aggregated data include<br>fine-grained timestamps?}
    
    Timestamp -->|Yes, < 1 hour granularity| HighRisk[ High risk – re-identification possible]
    Timestamp -->|No, daily or coarser| LowRisk[Acceptable for most health features]
    
    HighRisk --> Justified{Clinical or research<br>justification for fine timestamps?}
    Justified -->|No| RemoveTimestamp[Remove or bin timestamps]
    Justified -->|Yes| AddNoise[Add Laplace noise ±30 min]
    
    Critical --> Escalate[Escalate to Data Governance Board]
    
    
##Tree 5: Data Governance Board review – stored health data

flowchart TD
    Storage[Data already stored on Apple servers] --> Retention{Is retention period<br>explicitly stated & minimized?}
    Retention -->|No| SetPolicy[Define and enforce max 30 days unless clinical study]
    Retention -->|Yes| Encryption{Is data encrypted with<br>user key not accessible to Apple?}
    
    Encryption -->|No, Apple holds key| HighRisk2[ High risk – require re-encryption]
    Encryption -->|Yes, user-controlled| Access{Who can query this data?}
    
    Access -->|Engineers for debugging| Prohibit[ Prohibit – use synthetic data for debugging]
    Access -->|Approved research with IRB| AuditLogs[Maintain auditable query logs]
    
    SetPolicy --> ReAudit[Re-audit in 30 days]
    HighRisk2 --> ReEncrypt[Re-encrypt under user key]





















































