/** Keeps CSM natural keys correct even for Data Loader writes. */
public without sharing class CSMCapacityTriggerHandler {
    public static void prepareKeys(List<CSM_Capacity__c> rows, Boolean isUpdate) {
        // Admin edits must be serialized with ongoing assignment transactions.
        OnboardingAssignmentService.acquireLock();
        for (CSM_Capacity__c config : rows) {
            if (config.CSM_User__c == null) continue; // Validation rule rejects null.
            String canonical = String.valueOf(config.CSM_User__c);
            if (!String.isBlank(config.CSM_User_Key__c)
                    && !config.CSM_User_Key__c.equals(canonical)) {
                config.CSM_User_Key__c.addError('CSM User Key is system-managed.');
                continue;
            }
            config.CSM_User_Key__c = canonical;
        }
    }
}
