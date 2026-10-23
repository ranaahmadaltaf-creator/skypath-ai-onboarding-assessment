/**
 * Creates one onboarding per Closed Won Opportunity, including after re-open/re-close.
 * In Task 2B, all records are deliberately routed to the backlog queue. Task 2C
 * replaces queue-first routing with capacity-aware CSM assignment.
 *
 * A failed child insert marks its source deal with addError(), so a successful
 * Closed Won commit cannot be left without its onboarding.
 */
public without sharing class OnboardingCreationService {
    private static final String BACKLOG_QUEUE = 'CS_Onboarding_Backlog';

    public static void createMissingFor(List<Opportunity> deals) {
        if (deals == null || deals.isEmpty()) return;

        Map<Id, Opportunity> byId = new Map<Id, Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity deal : deals) {
            if (deal.Id == null) continue;
            byId.put(deal.Id, deal);
            if (deal.AccountId != null) accountIds.add(deal.AccountId);
        }
        if (byId.isEmpty()) return;

        Set<Id> existing = new Set<Id>();
        for (Onboarding__c onboard : [
            SELECT Opportunity__c FROM Onboarding__c
            WHERE Opportunity__c IN :byId.keySet()
        ]) {
            existing.add(onboard.Opportunity__c);
        }
        if (existing.size() == byId.size()) return;

        // Obtain queue ownership only when missing onboardings actually need creation.
        List<Group> groups = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :BACKLOG_QUEUE LIMIT 1
        ];
        if (groups.isEmpty()) {
            markMissingAsFailed(byId, existing,
                'The CS Onboarding Backlog queue is missing. Contact your Salesforce administrator.');
            return;
        }
        Id queueId = groups[0].Id;
        List<QueueSobject> supported = [
            SELECT Id FROM QueueSobject
            WHERE QueueId = :queueId AND SobjectType = 'Onboarding__c' LIMIT 1
        ];
        if (supported.isEmpty()) {
            markMissingAsFailed(byId, existing,
                'The CS Onboarding Backlog queue does not support Onboarding records.');
            return;
        }

        Map<Id, String> accountNames = new Map<Id, String>();
        if (!accountIds.isEmpty()) {
            for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :accountIds]) {
                accountNames.put(acc.Id, acc.Name);
            }
        }

        List<Onboarding__c> newOnboardings = new List<Onboarding__c>();
        List<Opportunity> sourceDeals = new List<Opportunity>();
        for (Opportunity deal : byId.values()) {
            if (existing.contains(deal.Id)) continue;
            Date launch = deal.Target_Go_Live__c != null
                ? deal.Target_Go_Live__c : deal.CloseDate.addDays(30);
            String accountName = accountNames.containsKey(deal.AccountId)
                ? accountNames.get(deal.AccountId) : deal.Name;
            newOnboardings.add(new Onboarding__c(
                Name = OnboardingNameService.build(accountName, launch),
                Opportunity__c = deal.Id,
                Opportunity_Key__c = String.valueOf(deal.Id),
                Stage__c = 'Kickoff Scheduled',
                Target_Go_Live__c = launch,
                OwnerId = queueId
            ));
            sourceDeals.add(deal);
        }
        if (newOnboardings.isEmpty()) return;

        Database.SaveResult[] results = Database.insert(newOnboardings, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) continue;
            List<String> errors = new List<String>();
            for (Database.Error e : results[i].getErrors()) {
                errors.add(e.getMessage());
            }
            sourceDeals[i].addError('Onboarding creation failed: ' + String.join(errors, '; '));
        }
    }

    private static void markMissingAsFailed(
        Map<Id, Opportunity> byId, Set<Id> existing, String message
    ) {
        for (Id dealId : byId.keySet()) {
            if (!existing.contains(dealId)) byId.get(dealId).addError(message);
        }
    }
}
