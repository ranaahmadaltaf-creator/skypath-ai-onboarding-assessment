/**
 * Stage transitions, historical milestones, and reportable stage visits.
 * BEFORE: validate and stamp parent; AFTER: write child visits in the same transaction.
 */
public without sharing class OnboardingStageService {
    public class StageHistoryException extends Exception {}

    private static final String KICKOFF = 'Kickoff Scheduled';
    private static final String GATHER = 'Gathering Info';
    private static final String IMPL = 'Implementation';
    private static final String QA = 'QA / Review';
    private static final String LIVE = 'Go Live';
    private static final String REVIEW = 'Post-Launch Review';

    private static final Map<String, String> FIRST_FIELDS = new Map<String, String>{
        KICKOFF => 'Kickoff_First_At__c',
        GATHER => 'Gathering_Info_First_At__c',
        IMPL => 'Implementation_First_At__c',
        QA => 'QA_Review_First_At__c',
        LIVE => 'Go_Live_First_At__c',
        REVIEW => 'Post_Launch_Review_First_At__c'
    };

    private static Boolean allowed(String fromStage, String toStage) {
        if (fromStage == KICKOFF) return toStage == GATHER;
        if (fromStage == GATHER) return toStage == IMPL;
        if (fromStage == IMPL) return toStage == QA;
        if (fromStage == QA) return toStage == IMPL || toStage == LIVE;
        if (fromStage == LIVE) return toStage == REVIEW;
        return false; // Post-Launch Review is terminal.
    }

    public static void beforeInsert(List<Onboarding__c> rows) {
        Datetime stamp = System.now();
        for (Onboarding__c row : rows) {
            if (row.Stage__c != KICKOFF) continue; // Handler rejects invalid initial stage.
            Boolean supplied = row.Stage_Entered_At__c != null;
            for (String key : FIRST_FIELDS.values()) {
                if (row.get(key) != null) supplied = true;
            }
            if (supplied) {
                row.addError('Stage timestamps are system-managed; leave them blank on creation.');
                continue;
            }
            row.Kickoff_First_At__c = stamp;
            row.Stage_Entered_At__c = stamp;
        }
    }

    public static void beforeUpdate(
        List<Onboarding__c> rows, Map<Id, Onboarding__c> oldById
    ) {
        Datetime stamp = System.now();
        for (Onboarding__c row : rows) {
            Onboarding__c prior = oldById.get(row.Id);
            Boolean stageChanged = row.Stage__c != prior.Stage__c;
            Boolean invalid = false;
            if (row.Stage_Entered_At__c != prior.Stage_Entered_At__c) {
                row.addError('Stage Entered At is system-managed.');
                invalid = true;
            }
            // No external edit may set, clear, or overwrite a historical milestone.
            for (String fieldName : FIRST_FIELDS.values()) {
                if (row.get(fieldName) != prior.get(fieldName)) {
                    row.addError('First-reached milestones are historical and cannot be edited.');
                    invalid = true;
                    break;
                }
            }
            if (!stageChanged) continue;
            if (!allowed(prior.Stage__c, row.Stage__c)) {
                row.Stage__c.addError('Invalid onboarding stage transition: '
                    + prior.Stage__c + ' -> ' + row.Stage__c);
                continue;
            }
            if (prior.Stage__c == GATHER && String.isBlank(row.Gathering_Notes__c)) {
                row.Gathering_Notes__c.addError('Gathering notes are required before Implementation.');
                continue;
            }
            if (prior.Stage__c == IMPL && String.isBlank(row.Implementation_Notes__c)) {
                row.Implementation_Notes__c.addError('Implementation notes are required before QA.');
                continue;
            }
            if (prior.Stage__c == QA && row.Stage__c == IMPL
                && String.isBlank(row.QA_Failure_Reason__c)) {
                row.QA_Failure_Reason__c.addError('Explain the QA failure before returning to Implementation.');
                continue;
            }
            if (invalid) continue;

            row.Stage_Entered_At__c = stamp;
            String milestone = FIRST_FIELDS.get(row.Stage__c);
            if (prior.get(milestone) == null) row.put(milestone, stamp);
            // After returning to QA, a future rollback must provide a NEW reason.
            if (prior.Stage__c == IMPL && row.Stage__c == QA) row.QA_Failure_Reason__c = null;
        }
    }

    /** Creates an initial open stage visit after ID assignment. */
    public static void afterInsert(List<Onboarding__c> rows) {
        List<Onboarding_Stage_Visit__c> visits = new List<Onboarding_Stage_Visit__c>();
        for (Onboarding__c row : rows) {
            visits.add(new Onboarding_Stage_Visit__c(
                Onboarding__c = row.Id,
                Stage__c = row.Stage__c,
                Entered_At__c = row.Stage_Entered_At__c,
                Visit_Number__c = 1
            ));
        }
        if (!visits.isEmpty()) insert visits;
    }

    /** Closes the open visit and adds the next visit. No queries/DML per record. */
    public static void afterUpdate(
        List<Onboarding__c> rows, Map<Id, Onboarding__c> oldById
    ) {
        Map<Id, Onboarding__c> changed = new Map<Id, Onboarding__c>();
        for (Onboarding__c row : rows) {
            if (row.Stage__c != oldById.get(row.Id).Stage__c) changed.put(row.Id, row);
        }
        if (changed.isEmpty()) return;

        Map<Id, Onboarding_Stage_Visit__c> openByParent =
            new Map<Id, Onboarding_Stage_Visit__c>();
        Map<Id, Integer> maxSequence = new Map<Id, Integer>();
        for (Onboarding_Stage_Visit__c visit : [
            SELECT Id, Onboarding__c, Stage__c, Entered_At__c,
                   Exited_At__c, Visit_Number__c
            FROM Onboarding_Stage_Visit__c
            WHERE Onboarding__c IN :changed.keySet()
        ]) {
            Integer n = visit.Visit_Number__c == null ? 0 : visit.Visit_Number__c.intValue();
            Integer previousMax = maxSequence.containsKey(visit.Onboarding__c)
                ? maxSequence.get(visit.Onboarding__c) : 0;
            if (n > previousMax) maxSequence.put(visit.Onboarding__c, n);
            if (visit.Exited_At__c == null) {
                if (openByParent.containsKey(visit.Onboarding__c)) {
                    throw new StageHistoryException('More than one open stage visit. Repair history first.');
                }
                openByParent.put(visit.Onboarding__c, visit);
            }
        }
        List<Onboarding_Stage_Visit__c> toClose = new List<Onboarding_Stage_Visit__c>();
        List<Onboarding_Stage_Visit__c> toInsert = new List<Onboarding_Stage_Visit__c>();
        for (Onboarding__c row : changed.values()) {
            Onboarding__c prior = oldById.get(row.Id);
            Integer n = maxSequence.containsKey(row.Id) ? maxSequence.get(row.Id) : 0;
            Onboarding_Stage_Visit__c existing = openByParent.get(row.Id);
            if (existing == null) {
                // Backfill the previous interval for records created before Task 3.
                toInsert.add(new Onboarding_Stage_Visit__c(
                    Onboarding__c = row.Id, Stage__c = prior.Stage__c,
                    Entered_At__c = prior.Stage_Entered_At__c == null
                        ? row.Stage_Entered_At__c : prior.Stage_Entered_At__c,
                    Exited_At__c = row.Stage_Entered_At__c,
                    Visit_Number__c = n + 1
                ));
                n++;
            } else {
                if (existing.Stage__c != prior.Stage__c) {
                    throw new StageHistoryException('Open visit stage does not match previous stage.');
                }
                existing.Exited_At__c = row.Stage_Entered_At__c;
                toClose.add(existing);
            }
            toInsert.add(new Onboarding_Stage_Visit__c(
                Onboarding__c = row.Id, Stage__c = row.Stage__c,
                Entered_At__c = row.Stage_Entered_At__c,
                Visit_Number__c = n + 1
            ));
        }
        if (!toClose.isEmpty()) update toClose;
        if (!toInsert.isEmpty()) insert toInsert;
    }
}
