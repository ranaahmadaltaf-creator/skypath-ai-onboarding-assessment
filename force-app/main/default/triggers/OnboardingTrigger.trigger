trigger OnboardingTrigger on Onboarding__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) OnboardingTriggerHandler.beforeInsert(Trigger.new);
        if (Trigger.isUpdate) OnboardingTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else {
        if (Trigger.isInsert) OnboardingTriggerHandler.afterInsert(Trigger.new);
        if (Trigger.isUpdate) OnboardingTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
