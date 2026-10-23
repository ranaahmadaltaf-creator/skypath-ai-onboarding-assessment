/** Collects queue-routed newly created onboardings. One asynchronous digest per trigger batch. */
public without sharing class OnboardingBacklogNotificationService {
    private static final String BACKLOG_API_NAME = 'CS_Onboarding_Backlog';

    public static void afterInsert(List<Onboarding__c> rows) {
        if (rows == null || rows.isEmpty()) return;
        List<Group> backlog = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :BACKLOG_API_NAME LIMIT 1
        ];
        if (backlog.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Backlog notifications: backlog queue not found.');
            return;
        }
        List<Id> queuedIds = new List<Id>();
        for (Onboarding__c row : rows) {
            if (row.OwnerId == backlog[0].Id) queuedIds.add(row.Id);
        }
        if (queuedIds.isEmpty()) return;
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // Do not roll back a valid customer onboarding when async capacity is exhausted.
            System.debug(LoggingLevel.ERROR,
                'Backlog notifications: unable to enqueue digest; async job limit reached.');
            return;
        }
        System.enqueueJob(new OnboardingBacklogNotificationJob(queuedIds));
    }
}
