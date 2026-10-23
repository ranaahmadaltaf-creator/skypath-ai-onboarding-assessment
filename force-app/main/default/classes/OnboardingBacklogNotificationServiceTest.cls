@IsTest
private class OnboardingBacklogNotificationServiceTest {
    private static List<Opportunity> makeWon(Integer amount) {
        Account account = new Account(Name = 'Notification Routing Test');
        insert account;
        List<Opportunity> deals = new List<Opportunity>();
        for (Integer i = 0; i < amount; i++) {
            deals.add(new Opportunity(
                Name = 'Notify Test ' + i,
                AccountId = account.Id,
                StageName = 'Closed Won',
                CloseDate = Date.today()
            ));
        }
        return deals;
    }

    @IsTest static void bulk200BacklogEnqueuesOneDigest() {
        List<Opportunity> deals = makeWon(200);
        Test.startTest();
        insert deals;
        System.assertEquals(1, Limits.getQueueableJobs(),
            'Exactly one digest job must be enqueued for 200 backlog records.');
        Test.stopTest();
        Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();
        Id backlogId = [SELECT Id FROM Group WHERE Type = 'Queue'
            AND DeveloperName = 'CS_Onboarding_Backlog' LIMIT 1].Id;
        System.assertEquals(200, [SELECT COUNT() FROM Onboarding__c
            WHERE Opportunity__c IN :dealIds AND OwnerId = :backlogId]);
    }

    @IsTest static void noBacklogDoesNotEnqueue() {
        insert new CSM_Capacity__c(CSM_User__c = UserInfo.getUserId(),
            Max_Capacity__c = 3, Is_Active__c = true);
        List<Opportunity> deals = makeWon(2);
        Test.startTest();
        insert deals;
        System.assertEquals(0, Limits.getQueueableJobs(),
            'No backlog should mean no manager alert.');
        Test.stopTest();
    }

    @IsTest static void partialBatchEnqueuesOneDigest() {
        insert new CSM_Capacity__c(CSM_User__c = UserInfo.getUserId(),
            Max_Capacity__c = 2, Is_Active__c = true);
        List<Opportunity> deals = makeWon(3);
        Test.startTest();
        insert deals;
        System.assertEquals(1, Limits.getQueueableJobs(),
            'Only one notification job should cover the backlog subset.');
        Test.stopTest();
    }

    @IsTest static void digestTextIsClearAndBounded() {
        System.assertEquals('New onboarding in backlog',
            OnboardingBacklogNotificationJob.alertTitle(1));
        System.assertEquals('200 onboardings in backlog',
            OnboardingBacklogNotificationJob.alertTitle(200));
        System.assert(
            OnboardingBacklogNotificationJob.alertBody(1, 'Customer A').contains('Customer A')
        );
        System.assert(
            OnboardingBacklogNotificationJob.alertBody(200, 'Customer A').contains('200')
        );
        System.assert(OnboardingBacklogNotificationJob.alertTitle(200).length() <= 250);
        System.assert(OnboardingBacklogNotificationJob.alertBody(200, 'Customer A').length() <= 750);
    }


    // An empty or null digest must be a safe no-op. This exercises the
    // constructor's null normalization and the early-return guard.
    @IsTest static void notificationJobHandlesNullAndEmptyIds() {
        Test.startTest();
        OnboardingBacklogNotificationJob nullInput =
            new OnboardingBacklogNotificationJob(null);
        nullInput.execute(null);
        OnboardingBacklogNotificationJob emptyInput =
            new OnboardingBacklogNotificationJob(new List<Id>());
        emptyInput.execute(null);
        Test.stopTest();
    }

    // The async job must be safe when its pending IDs no longer refer to
    // queue-owned onboardings. An unrelated Account ID simulates this no-match path.
    @IsTest static void notificationJobSkipsIdsWithNoMatchingOnboardings() {
        Account unrelated = new Account(Name = 'Notification job no-match test');
        insert unrelated;

        Test.startTest();
        OnboardingBacklogNotificationJob job =
            new OnboardingBacklogNotificationJob(new List<Id>{ unrelated.Id });
        job.execute(null);
        Test.stopTest();
    }
}
