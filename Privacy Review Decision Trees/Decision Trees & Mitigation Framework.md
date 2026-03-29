# Health Privacy Review: Decision Trees & Mitigation Framework
Version: 1.0
Audience: Privacy Engineers, Feature Leads, Data Governance Board
Applies to: Health, Wellness, Fitness features + Health Research Studies


flowchart TD
    Start[Start: Feature requires data] --> Q1{Is the data strictly necessary<br>for the core health feature?}
    Q1 -->|No| Stop1[ Do not collect. Re-architect.]
    Q1 -->|Yes| Q2{Can the feature work with<br>less granular data?}
    Q2 -->|Yes| Modify[Modify spec: lower granularity]
    Q2 -->|No| Q3{Is the data derived from<br>a sensitive health category?}
    Q3 -->|Yes, Heart, Reproductive, Mental Health| RedFlag[ High risk – proceed to Tree 2]
    Q3 -->|No, e.g., step counts, exercise minutes| YellowFlag[ Moderate risk – proceed to Tree 2]

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
    
    Encryption -->|No, Apple holds key| HighRisk2[🟠 High risk – require re-encryption]
    Encryption -->|Yes, user-controlled| Access{Who can query this data?}
    
    Access -->|Engineers for debugging| Prohibit[❌ Prohibit – use synthetic data for debugging]
    Access -->|Approved research with IRB| AuditLogs[Maintain auditable query logs]
    
    SetPolicy --> ReAudit[Re-audit in 30 days]
    HighRisk2 --> ReEncrypt[Re-encrypt under user key]





















































