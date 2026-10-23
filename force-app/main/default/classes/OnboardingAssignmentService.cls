/**
 * Capacity-aware CSM routing. Serializes workload-affecting writes through ONE
 * global lock row. Counts are intentionally re-read AFTER the lock is acquired.
 *
 * System-mode data access is deliberate: end users should not need visibility
 * to CSM configuration or to the mutex record for this internal service.
 */
public without sharing class OnboardingAssignmentService {
    private static final String GLOBAL_KEY = 'GLOBAL';
    private static final String BACKLOG_NAME = 'CS_Onboarding_Backlog';
    private static Boolean hasLock = false;

    /** Locks (and lazily creates) the single shared synchronization row. */
    public static void acquireLock() {
        if (hasLock) return;
        List<Onboarding_Assignment_Lock__c> locks = [
            SELECT Id FROM Onboarding_Assignment_Lock__c
            WHERE Lock_Key__c = :GLOBAL_KEY LIMIT 1 FOR UPDATE
        ];
        if (locks.isEmpty()) {
            try {
                insert new Onboarding_Assignment_Lock__c(Lock_Key__c = GLOBAL_KEY);
            } catch (DmlException ex) {
                // A simultaneous bootstrap may have won the UNIQUE-key insert.
                // Re-query under FOR UPDATE. If no row can be acquired, fail closed.
                locks = [
                    SELECT Id FROM Onboarding_Assignment_Lock__c
                    WHERE Lock_Key__c = :GLOBAL_KEY LIMIT 1 FOR UPDATE
                ];
                if (locks.isEmpty()) throw ex;
            }
            locks = [
                SELECT Id FROM Onboarding_Assignment_Lock__c
                WHERE Lock_Key__c = :GLOBAL_KEY LIMIT 1 FOR UPDATE
            ];
        }
        if (locks.isEmpty()) {
            throw new AssignmentException('GLOBAL assignment lock missing. Assignment stopped.');
        }
        hasLock = true;
    }

    public class AssignmentException extends Exception {}

    private class Roster {
        Id queueId;
        Map<Id, Integer> capacities = new Map<Id, Integer>();
        Map<Id, Integer> loads = new Map<Id, Integer>();
        List<Id> orderedUsers = new List<Id>();
    }

    private static Roster loadRoster() {
        Roster r = new Roster();
        List<Group> q = [
            SELECT Id FROM Group WHERE Type = 'Queue'
            AND DeveloperName = :BACKLOG_NAME LIMIT 1
        ];
        if (!q.isEmpty()) r.queueId = q[0].Id;
        for (CSM_Capacity__c cfg : [
            SELECT CSM_User__c, Max_Capacity__c
            FROM CSM_Capacity__c
            WHERE Is_Active__c = true AND CSM_User__c != null
            AND CSM_User__r.IsActive = true
            ORDER BY CSM_User__c ASC
        ]) {
            Integer limitCount = cfg.Max_Capacity__c == null
                ? 0 : cfg.Max_Capacity__c.intValue();
            r.capacities.put(cfg.CSM_User__c, limitCount);
            r.loads.put(cfg.CSM_User__c, 0);
            r.orderedUsers.add(cfg.CSM_User__c);
        }
        if (!r.orderedUsers.isEmpty()) {
            Set<Id> eligibleIds = r.capacities.keySet();
            for (AggregateResult row : [
                SELECT OwnerId csmOwner, COUNT(Id) quantity
                FROM Onboarding__c
                WHERE Stage__c != 'Post-Launch Review'
                AND OwnerId IN :eligibleIds
                GROUP BY OwnerId
            ]) {
                r.loads.put((Id) row.get('csmOwner'), (Integer) row.get('quantity'));
            }
        }
        return r;
    }

    private static Boolean isActive(String stageName) {
        return stageName != 'Post-Launch Review';
    }

    private static Id leastLoaded(Roster r) {
        Id best;
        for (Id userId : r.orderedUsers) {
            if (r.loads.get(userId) >= r.capacities.get(userId)) continue;
            if (best == null || r.loads.get(userId) < r.loads.get(best)) best = userId;
        }
        return best;
    }

    /** Inserts auto-route queue-owned/unspecified records; validate explicit CSM owners. */
    public static void onBeforeInsert(List<Onboarding__c> records) {
        if (records.isEmpty()) return;
        acquireLock();
        Roster r = loadRoster();
        for (Onboarding__c row : records) {
            if (row.hasErrors()) continue; // Invalid insert rows cannot consume capacity.
            if (r.queueId == null) {
                row.addError('CS Onboarding Backlog queue is missing.');
                continue;
            }
            Id owner = row.OwnerId;
            if (owner == null || owner == r.queueId) {
                Id selected = leastLoaded(r);
                row.OwnerId = selected == null ? r.queueId : selected;
                if (selected != null && isActive(row.Stage__c)) {
                    r.loads.put(selected, r.loads.get(selected) + 1);
                    row.Assigned_At__c = System.now();
                }
            } else if (r.capacities.containsKey(owner)) {
                if (isActive(row.Stage__c)) {
                    if (r.loads.get(owner) >= r.capacities.get(owner)) {
                        row.OwnerId.addError('This CSM is at maximum active-onboarding capacity.');
                    } else {
                        r.loads.put(owner, r.loads.get(owner) + 1);
                        row.Assigned_At__c = System.now();
                    }
                }
            } else {
                row.OwnerId.addError('Owner must be an eligible CSM or the onboarding backlog queue.');
            }
        }
    }

    /**
     * Validates the whole update batch using the NET load change, not record order.
     * Also serializes changes into/out of terminal Post-Launch Review.
     */
    public static void onBeforeUpdate(
        List<Onboarding__c> records, Map<Id, Onboarding__c> oldById
    ) {
        Boolean canReassign = FeatureManagement.checkPermission('SkyPath_Manage_Onboarding_Assignment');
        Boolean workloadChanging = false;
        for (Onboarding__c row : records) {
            if (row.hasErrors()) continue; // Invalid stage cannot falsely free capacity.
            Onboarding__c old = oldById.get(row.Id);
            if (row.OwnerId != old.OwnerId && !canReassign) {
                row.OwnerId.addError('Only authorized managers can reassign onboarding ownership.');
                continue;
            }
            if (row.OwnerId != old.OwnerId
                || isActive(row.Stage__c) != isActive(old.Stage__c)) {
                workloadChanging = true;
                break;
            }
        }
        if (!workloadChanging) return;
        acquireLock();
        Roster r = loadRoster();
        Map<Id, Integer> delta = new Map<Id, Integer>();
        Map<Id, List<Onboarding__c>> incoming = new Map<Id, List<Onboarding__c>>();
        for (Onboarding__c row : records) {
            if (row.hasErrors()) continue;
            Onboarding__c old = oldById.get(row.Id);
            Boolean wasActive = isActive(old.Stage__c);
            Boolean isNowActive = isActive(row.Stage__c);
            Boolean ownerChanged = row.OwnerId != old.OwnerId;
            if (!ownerChanged && wasActive == isNowActive) continue;
            if (r.queueId == null) {
                row.addError('CS Onboarding Backlog queue is missing.');
                continue;
            }
            if (row.OwnerId != r.queueId && !r.capacities.containsKey(row.OwnerId)) {
                row.OwnerId.addError('Owner must be an eligible CSM or the onboarding backlog queue.');
                continue;
            }
            if (wasActive && r.capacities.containsKey(old.OwnerId)) {
                increment(delta, old.OwnerId, -1);
            }
            if (isNowActive && r.capacities.containsKey(row.OwnerId)) {
                increment(delta, row.OwnerId, 1);
                if (!incoming.containsKey(row.OwnerId))
                    incoming.put(row.OwnerId, new List<Onboarding__c>());
                incoming.get(row.OwnerId).add(row);
            }
            if (ownerChanged && row.OwnerId != r.queueId) row.Assigned_At__c = System.now();
        }
        for (Id userId : incoming.keySet()) {
            Integer projected = r.loads.get(userId) +
                (delta.containsKey(userId) ? delta.get(userId) : 0);
            if (projected > r.capacities.get(userId)) {
                for (Onboarding__c affected : incoming.get(userId)) {
                    affected.OwnerId.addError(
                        'Reassignment would exceed this CSM\'s active-onboarding capacity.'
                    );
                }
            }
        }
    }

    private static void increment(Map<Id, Integer> amounts, Id idValue, Integer difference) {
        amounts.put(idValue, (amounts.containsKey(idValue) ? amounts.get(idValue) : 0) + difference);
    }
}
