# SkyPath AI — Customer Onboarding Automation

Salesforce developer assessment | RevInfinity

## Overview

SkyPath AI automates customer onboarding when an Opportunity becomes **Closed Won**. It creates a single linked onboarding record, guides users through six ordered stages, assigns work to eligible Customer Success Managers (CSMs) subject to configured capacity, and routes overflow to a backlog queue. The solution includes a Lightning Web Component (LWC), history for stage visits, reports, a dashboard, permissions, and Apex tests.

## Core capabilities

1. **Idempotent onboarding creation:** A Closed Won Opportunity produces one linked `Onboarding__c` record rather than duplicates. The display name follows `Account | Go Live: YYYY-MM-DD`.
2. **Six-stage workflow:** Kickoff Scheduled → Gathering Info → Implementation → QA / Review → Go Live → Post-Launch Review. Stage transitions enforce required notes and prevent skipping. QA rollback requires a reason.
3. **Stage timing and auditability:** First-reached timestamps are preserved. `Onboarding_Stage_Visit__c` tracks each visit, including a repeat visit, with entry/exit timestamps and elapsed-time data.
4. **Capacity-aware CSM assignment:** An eligible active CSM with the lightest load is chosen up to their `Max_Capacity__c`. An assignment-lock singleton serializes competing assignment transactions. Overflow is owned by the `CS_Onboarding_Backlog` queue.
5. **Backlog notifications:** An asynchronous custom notification uses the `CS_Onboarding_Backlog_Alert` notification type and the `CS_Onboarding_Managers` public group.
6. **User experience:** The `onboardingStageTracker` LWC is used on the `Revinfinity_Onboarding_Tracker` Lightning record page.
7. **Reporting and access control:** Reports for active CSM workload, backlog, stage distribution and average stage duration; dashboard; dedicated CSM and Manager Permission Sets and manager-only reassignment authorization.

## Repository structure

The Salesforce DX project contains source under `force-app/main/default/`, with metadata for custom objects/fields, triggers and Apex classes, Lightning components, permissions, reports, dashboards, group/queue and notification configuration. Local scripts, where provided, live under `scripts/apex/`.

## Prerequisites

- Salesforce Developer Edition / scratch or sandbox org with suitable Salesforce features enabled.
- Salesforce CLI (`sf`), access to the target org and an appropriate Salesforce license for each user.
- A deployment user with metadata-deployment permissions.
- Salesforce DX project cloned locally.

## Deploy

```powershell
sf org login web --alias SkyPathTarget
sf project deploy start --source-dir force-app/main/default --target-org SkyPathTarget `
  --test-level RunSpecifiedTests `
  --tests CSMCapacityTriggerHandlerTest `
  --tests OnboardingAssignmentServiceTest `
  --tests OnboardingBacklogNotificationServiceTest `
  --tests OnboardingCreationServiceTest `
  --tests OnboardingStageServiceTest `
  --tests OnboardingTriggerHandlerTest `
  --wait 30
```

**Important:** Org-dependent runtime records and memberships are **not** created merely by deploying source metadata. Do the setup below before verifying live assignment. A clean Developer Edition deployment was verified with 69/69 metadata components and a 25/25 targeted regression run. Subsequently, all six SkyPath test classes passed in the same fresh org: **29 tests reported, zero failures, 90% org-wide coverage** (run `707g800000qgokT`). The command above names the six SkyPath test classes for a new target org; always verify that org’s own deployment and test results. To run the whole local test inventory instead, replace `RunSpecifiedTests` and the `--tests` flags with `--test-level RunLocalTests` and verify the actual result. An existing org may contain unrelated failing Apex tests.

## First-time setup

1. Assign `SkyPath_Onboarding_Manager` to at least one administrator/manager and `SkyPath_Onboarding_CSM` to participating CSM users. Example:

   ```powershell
   sf org assign permset --name SkyPath_Onboarding_Manager --on-behalf-of manager@example.com --target-org SkyPathTarget
   ```

2. Initialize the **singleton assignment lock** via the portable, committed `scripts/bootstrap.apex` (provided in this submission, with **no org-specific IDs**):

   ```powershell
   sf apex run --file scripts/bootstrap.apex --target-org SkyPathTarget
   ```

   The initialization method is idempotent. The lock object is `Onboarding_Assignment_Lock__c`.

3. Create `CSM_Capacity__c` records for each eligible user. Set `CSM_User__c`, matching `CSM_User_Key__c`, `Is_Active__c=true`, and a positive `Max_Capacity__c` appropriate for the demo.
4. Add real manager users to the `CS_Onboarding_Managers` public group. Confirm the `CS_Onboarding_Backlog` queue and custom notification type are present. Queue/group membership is environment-specific.
5. In Lightning App Builder, confirm `Revinfinity_Onboarding_Tracker` is activated and assigned to the intended app / user context; activation may require org-specific configuration.
6. Confirm report/dashboard folder access for the target audience.

## Smoke-test walkthrough

1. Create an Account and an Opportunity at `Closed Won`.
2. Verify **exactly one** `Onboarding__c` exists for the Opportunity; check owner, initial stage and Target Go Live.
3. Move the stage forward using the LWC, demonstrate required notes and visit-history timestamps, and demonstrate QA rollback with reason.
4. Set a test CSM's maximum capacity to 2. Create three Closed Won Opportunities. Verify two assigned onboarding records and one `CS_Onboarding_Backlog` record; check manager notification.
5. Open reports and dashboard. Demonstrate role-appropriate permissions.

Example SOQL to inspect an onboarding:

```sql
SELECT Id, Name, Opportunity__c, OwnerId, Owner.Name, Stage__c, Target_Go_Live__c
FROM Onboarding__c
WHERE Opportunity__c = 'REPLACE_WITH_OPPORTUNITY_ID'
```

## Validation evidence (fresh Developer Edition)

- Fresh org source deployment: **69/69 metadata components succeeded**.
- Fresh-org deployment regression: **25/25 targeted tests passed**.
- Complete six-class SkyPath regression: **29 tests reported, 29 passed, 0 failures; 90% org-wide Apex coverage** (run `707g800000qgokT`). CLI listed 28 named test methods plus the test setup method; use the Salesforce summary count as reported.
- Onboarding creation: **one onboarding** linked to a newly created Closed Won Opportunity, initially at `Kickoff Scheduled`, with an eligible CSM owner.
- Capacity overflow test: a maximum-capacity-2 CSM owned **two** onboarding records; the **third** was owned by the backlog queue.
- Assignment singleton verified: exactly **one** lock record after repeated initialization.

The results above describe observed checks, not a claim that every UI/report/notification scenario was freshly re-tested in the second org. Additional checks can be performed through the walkthrough.

## Full SkyPath test-suite verification

To reproduce validation, run all six SkyPath test classes and compare the actual Salesforce summary. Source-level method counts are not equivalent to tests executed in an org.

```powershell
sf apex run test `
  --class-names CSMCapacityTriggerHandlerTest `
  --class-names OnboardingAssignmentServiceTest `
  --class-names OnboardingBacklogNotificationServiceTest `
  --class-names OnboardingCreationServiceTest `
  --class-names OnboardingStageServiceTest `
  --class-names OnboardingTriggerHandlerTest `
  --target-org SkyPathTarget `
  --wait 20 --result-format human --code-coverage
```

**Verified in SkyPathFresh:** six-class suite **Passed**; Salesforce summary reports **29 tests, 100% pass, zero failures, 90% org-wide code coverage**. Run ID: `707g800000qgokT`. The result pertains to this validation org; rerun for independent target deployments.

## Repository hygiene

Do not commit `.sf/`, `.sfdx/`, local backups, `mdapi-check/`, or local anonymous Apex smoke-test scripts containing real record IDs. Only the portable ID-free setup script `scripts/bootstrap.apex` is needed for the fresh-org instructions. Before `git add`/push, inspect `git status --short` and run a text search for org-specific Salesforce IDs in tracked source and docs.

## Design decisions and trade-offs

- **Serialize assignment only where needed:** a single locked row protects the read/choose/update decision across concurrent transactions. That favors correctness over maximum assignment throughput.
- **Audit every visit:** per-visit rows preserve a return to an earlier stage instead of overwriting history. Separate first-reached timestamps remain unchanged.
- **Asynchronous notification:** decouples non-critical manager communication from core Opportunity processing.
- **Permission separation:** managers can perform privileged assignment actions; CSMs receive only their operational capabilities.

See `docs/SkyPath_Technical_Design.pdf` (and editable `.md`) for data-model decisions, Apex versus Flow reasoning, 200-record assignment, the explicit assumptions log, business-hours stretch option and second-product scaling.

## Demo

The submission walkthrough should show the business workflow, Apex/test architecture, concurrency/capacity behavior, LWC stages, history, reports and dashboard, security, and fresh-org deployment evidence. Add a video link here before final submission.

**Demo recording:** _Add final recording URL here_

## Submission checklist

- [x] Core functionality implemented
- [x] Fresh-org deployment verified
- [x] 25 targeted SkyPath Apex tests passed (previous deployment run)
- [x] All six SkyPath test classes passed in the fresh org; 29 reported, 90% org-wide coverage
- [x] Closed Won/onboarding and backlog overflow verified in fresh org
- [x] README and design documents prepared locally (verify GitHub push)
- [ ] Repository URL verified
- [ ] Walkthrough recording URL added
- [ ] Final email sent
