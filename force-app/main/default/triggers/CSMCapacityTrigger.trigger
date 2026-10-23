trigger CSMCapacityTrigger on CSM_Capacity__c (before insert, before update) {
    if (Trigger.isBefore) {
        CSMCapacityTriggerHandler.prepareKeys(Trigger.new, Trigger.isUpdate);
    }
}
