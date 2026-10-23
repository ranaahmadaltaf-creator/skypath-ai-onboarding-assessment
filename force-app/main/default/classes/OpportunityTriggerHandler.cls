/** Keeps the Opportunity trigger logic-free so future actions can be composed. */
public without sharing class OpportunityTriggerHandler {
    public static void afterSave(List<Opportunity> newRecords) {
        List<Opportunity> wonDeals = new List<Opportunity>();
        for (Opportunity deal : newRecords) {
            if (deal.StageName == 'Closed Won') {
                wonDeals.add(deal);
            }
        }
        if (!wonDeals.isEmpty()) {
            OnboardingCreationService.createMissingFor(wonDeals);
        }
    }
}
