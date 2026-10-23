/** Sends one Salesforce bell notification to the configured Public Group per batch.
 *  Resolves Group and Notification Type dynamically to keep IDs environment-independent.
 */
public without sharing class OnboardingBacklogNotificationJob implements Queueable {
    private static final String BACKLOG_API_NAME = 'CS_Onboarding_Backlog';
    private static final String MANAGER_GROUP_API_NAME = 'CS_Onboarding_Managers';
    private static final String NOTIFICATION_TYPE_API_NAME = 'CS_Onboarding_Backlog_Alert';
    private List<Id> pendingIds;

    public OnboardingBacklogNotificationJob(List<Id> ids) {
        pendingIds = ids == null ? new List<Id>() : ids;
    }

    @TestVisible private static String alertTitle(Integer count) {
        return count == 1 ? 'New onboarding in backlog' :
            String.valueOf(count) + ' onboardings in backlog';
    }
    @TestVisible private static String alertBody(Integer count, String firstName) {
        if (count == 1) return firstName + ' needs a CSM assignment. All CSMs are at capacity.';
        return String.valueOf(count) +
            ' new onboardings need CSM assignments. Open one to review the backlog.';
    }

    public void execute(QueueableContext context) {
        if (pendingIds.isEmpty()) return;
        List<Group> queueRows = [
            SELECT Id FROM Group WHERE Type = 'Queue'
            AND DeveloperName = :BACKLOG_API_NAME LIMIT 1
        ];
        if (queueRows.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Backlog notification skipped: queue missing.');
            return;
        }
        // Recheck current owner. An onboarding might have been reassigned since the job was queued.
        Id backlogQueueId = queueRows[0].Id;
        List<Onboarding__c> rows = [
            SELECT Id, Name FROM Onboarding__c
            WHERE Id IN :pendingIds AND OwnerId = :backlogQueueId
            ORDER BY CreatedDate ASC, Id ASC
        ];
        if (rows.isEmpty()) return;
        List<Group> groups = [
            SELECT Id FROM Group WHERE Type = 'Regular'
            AND DeveloperName = :MANAGER_GROUP_API_NAME LIMIT 1
        ];
        if (groups.isEmpty()) {
            System.debug(LoggingLevel.ERROR,
                'Backlog notification not delivered: CS_Onboarding_Managers group missing.');
            return;
        }
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE_API_NAME LIMIT 1
        ];
        if (types.isEmpty()) {
            System.debug(LoggingLevel.ERROR,
                'Backlog notification not delivered: Custom Notification Type missing.');
            return;
        }
        String title = alertTitle(rows.size());
        String body = alertBody(rows.size(), rows[0].Name);
        // Always build the notification, including in tests. The previous early
        // Test.isRunningTest() return left the actual message construction untested.
        // Suppress only delivery from unit tests to avoid notifications to real users.
        try {
            Messaging.CustomNotification message = new Messaging.CustomNotification();
            message.setNotificationTypeId(types[0].Id);
            message.setTitle(title);
            message.setBody(body);
            message.setTargetId(rows[0].Id);
            if (!Test.isRunningTest()) {
                // A Public Group ID is a supported notification recipient.
                message.send(new Set<String>{String.valueOf(groups[0].Id)});
            }
        } catch (Exception ex) {
            // Fail tests when message construction breaks, rather than silently
            // hiding the error behind the production delivery safety net.
            if (Test.isRunningTest()) throw ex;
            // A notification failure must not roll back the already-committed onboarding.
            System.debug(LoggingLevel.ERROR,
                'Backlog notification failed: ' + ex.getMessage());
        }
    }
}
