@IsTest
private class OnboardingTriggerHandlerTest {
    private static Opportunity createOpenDeal() {
        Account customer = new Account(Name = 'Onboarding Handler Test Customer');
        insert customer;
        Opportunity deal = new Opportunity(
            Name = 'Test Open Deal',
            AccountId = customer.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert deal;
        return deal;
    }

    private static Onboarding__c newOnboarding(Id opportunityId) {
        return new Onboarding__c(
            Name = 'Handler Test | Go Live: 2026-11-30',
            Opportunity__c = opportunityId,
            Stage__c = 'Kickoff Scheduled',
            Target_Go_Live__c = Date.newInstance(2026, 11, 30),
            OwnerId = [SELECT Id FROM Group WHERE Type = 'Queue'
                AND DeveloperName = 'CS_Onboarding_Backlog' LIMIT 1].Id
        );
    }

    @IsTest
    static void manualOnboardingInsertInitializesKeyAndTimestamps() {
        Opportunity deal = createOpenDeal();
        Onboarding__c onboarding = newOnboarding(deal.Id);
        insert onboarding;

        Onboarding__c actual = [
            SELECT Opportunity_Key__c, Stage__c,
                Kickoff_First_At__c, Stage_Entered_At__c
            FROM Onboarding__c WHERE Id = :onboarding.Id
        ];
        System.assertEquals(String.valueOf(deal.Id), actual.Opportunity_Key__c,
            'Before-insert handler must derive the unique Opportunity key.');
        System.assertEquals('Kickoff Scheduled', actual.Stage__c);
        System.assertNotEquals(null, actual.Kickoff_First_At__c,
            'Initial stage first-reached timestamp is required.');
        System.assertNotEquals(null, actual.Stage_Entered_At__c,
            'Initial visit timestamp is required.');
    }

    @IsTest
    static void rejectsInvalidKeyAndInvalidInitialStage() {
        Opportunity deal = createOpenDeal();

        Onboarding__c wrongKey = newOnboarding(deal.Id);
        wrongKey.Opportunity_Key__c = 'MANUAL_KEY';
        Database.SaveResult wrongKeyResult = Database.insert(wrongKey, false);
        System.assertEquals(false, wrongKeyResult.isSuccess(),
            'A mismatched Opportunity key must fail before-insert validation.');

        Onboarding__c skippedStage = newOnboarding(deal.Id);
        skippedStage.Stage__c = 'Implementation';
        Database.SaveResult skippedStageResult = Database.insert(skippedStage, false);
        System.assertEquals(false, skippedStageResult.isSuccess(),
            'An onboarding cannot start at Implementation.');
    }

    @IsTest
    static void validUpdateWorksButKeyTamperingFails() {
        Opportunity deal = createOpenDeal();
        Onboarding__c onboarding = newOnboarding(deal.Id);
        insert onboarding;

        Onboarding__c changed = new Onboarding__c(
            Id = onboarding.Id,
            Gathering_Notes__c = 'Customer provided implementation contacts.'
        );
        update changed;
        System.assertEquals('Customer provided implementation contacts.', [
            SELECT Gathering_Notes__c FROM Onboarding__c WHERE Id = :onboarding.Id
        ].Gathering_Notes__c);

        Onboarding__c tampered = new Onboarding__c(
            Id = onboarding.Id,
            Opportunity_Key__c = 'MANUAL_CHANGE'
        );
        Database.SaveResult tamperResult = Database.update(tampered, false);
        System.assertEquals(false, tamperResult.isSuccess(),
            'The before-update handler must reject edits to the Opportunity key.');
        System.assertEquals(String.valueOf(deal.Id), [
            SELECT Opportunity_Key__c FROM Onboarding__c WHERE Id = :onboarding.Id
        ].Opportunity_Key__c);
    }
}
