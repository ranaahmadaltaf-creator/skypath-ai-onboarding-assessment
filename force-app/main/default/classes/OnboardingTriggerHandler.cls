/** Natural key, lifecycle, and assignment routing for Onboarding__c. */
public without sharing class OnboardingTriggerHandler {
    public static void beforeInsert(List<Onboarding__c> rows) {
        for (Onboarding__c item : rows) {
            if (item.Opportunity__c == null) continue; // Required lookup handles this.
            String canonical = String.valueOf(item.Opportunity__c);
            if (!String.isBlank(item.Opportunity_Key__c)
                && !item.Opportunity_Key__c.equals(canonical)) {
                item.Opportunity_Key__c.addError('Opportunity Key is system-managed.');
                continue;
            }
            item.Opportunity_Key__c = canonical;
            if (String.isBlank(item.Stage__c)) item.Stage__c = 'Kickoff Scheduled';
            if (item.Stage__c != 'Kickoff Scheduled') {
                item.Stage__c.addError('A new onboarding must start at Kickoff Scheduled.');
            }
        }
        OnboardingStageService.beforeInsert(rows);
        OnboardingAssignmentService.onBeforeInsert(rows);
    }
    public static void beforeUpdate(
        List<Onboarding__c> rows, Map<Id, Onboarding__c> oldById
    ) {
        for (Onboarding__c item : rows) {
            Onboarding__c oldItem = oldById.get(item.Id);
            if (!item.Opportunity_Key__c.equals(oldItem.Opportunity_Key__c)) {
                item.Opportunity_Key__c.addError('Opportunity Key cannot be manually changed.');
            }
        }
        OnboardingStageService.beforeUpdate(rows, oldById);
        OnboardingAssignmentService.onBeforeUpdate(rows, oldById);
    }
    public static void afterInsert(List<Onboarding__c> rows) {
        OnboardingStageService.afterInsert(rows);
        OnboardingBacklogNotificationService.afterInsert(rows);
    }
    public static void afterUpdate(
        List<Onboarding__c> rows, Map<Id, Onboarding__c> oldById
    ) {
        OnboardingStageService.afterUpdate(rows, oldById);
    }
}
