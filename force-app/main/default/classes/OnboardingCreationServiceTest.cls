@IsTest
private class OnboardingCreationServiceTest {
    // Queue is deployed metadata and therefore visible without SeeAllData=true.
    private static Id backlogQueueId() {
        List<Group> queues = [
            SELECT Id FROM Group
            WHERE DeveloperName = 'CS_Onboarding_Backlog' AND Type = 'Queue' LIMIT 1
        ];
        System.assertEquals(1, queues.size(), 'Queue metadata must be included in the SFDX project.');
        return queues[0].Id;
    }

    @IsTest
    static void bulk200ClosedWonCreatesExactly200Onboardings() {
        Id queueId = backlogQueueId();
        Account customer = new Account(Name = 'SkyPath Bulk Customer');
        insert customer;
        List<Opportunity> deals = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            deals.add(new Opportunity(
                Name = 'SkyPath Bulk Deal ' + i,
                AccountId = customer.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today(),
                Target_Go_Live__c = Date.today().addDays(40)
            ));
        }
        Test.startTest();
        insert deals;
        Test.stopTest();
        Set<Id> ids = new Map<Id, Opportunity>(deals).keySet();
        List<Onboarding__c> results = [
            SELECT Id, Name, OwnerId, Opportunity__c, Opportunity_Key__c,
                   Stage__c, Kickoff_First_At__c, Target_Go_Live__c
            FROM Onboarding__c WHERE Opportunity__c IN :ids
        ];
        System.assertEquals(200, results.size(), 'A bulk insert must create exactly 200 children.');
        Set<Id> distinctDeals = new Set<Id>();
        for (Onboarding__c item : results) {
            System.assertEquals(queueId, item.OwnerId, 'Until assignment step, all go to backlog.');
            System.assertEquals('Kickoff Scheduled', item.Stage__c);
            System.assertNotEquals(null, item.Kickoff_First_At__c);
            System.assertEquals(Date.today().addDays(40), item.Target_Go_Live__c);
            System.assertEquals(String.valueOf(item.Opportunity__c), item.Opportunity_Key__c);
            System.assert(item.Name.contains('Go Live:'), 'Name must include the launch date.');
            distinctDeals.add(item.Opportunity__c);
        }
        System.assertEquals(200, distinctDeals.size(), 'No duplicate or missing mappings.');
    }

    @IsTest
    static void reopeningAndWinningAgainIsIdempotent() {
        backlogQueueId();
        Account customer = new Account(Name = 'Idempotence Client');
        insert customer;
        Opportunity deal = new Opportunity(
            Name = 'Renewable Deal', AccountId = customer.Id,
            StageName = 'Closed Won', CloseDate = Date.today()
        );
        insert deal;
        deal.StageName = 'Prospecting';
        update deal;
        deal.StageName = 'Closed Won';
        update deal;
        System.assertEquals(1, [
            SELECT COUNT() FROM Onboarding__c WHERE Opportunity__c = :deal.Id
        ]);
    }

    @IsTest
    static void longCustomerNameIsSafelyTruncatedAndFallbackDateIsCorrect() {
        backlogQueueId();
        String longName = '';
        for (Integer i = 0; i < 10; i++) longName += 'VeryLongCustomer';
        Account customer = new Account(Name = longName);
        insert customer;
        Date closed = Date.newInstance(2026, 11, 5);
        Opportunity deal = new Opportunity(
            Name = 'Large Name Deal', AccountId = customer.Id,
            StageName = 'Closed Won', CloseDate = closed
        );
        insert deal;
        Onboarding__c result = [
            SELECT Name, Target_Go_Live__c FROM Onboarding__c
            WHERE Opportunity__c = :deal.Id LIMIT 1
        ];
        System.assert(result.Name.length() <= 80, 'Name must fit the standard 80-char limit.');
        System.assert(result.Name.endsWith(' | Go Live: 2026-12-05'));
        System.assertEquals(closed.addDays(30), result.Target_Go_Live__c);
    }
}
