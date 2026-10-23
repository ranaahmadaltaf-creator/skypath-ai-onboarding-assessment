@IsTest
private class OnboardingStageServiceTest {
    private static Id backlog() {
        return [SELECT Id FROM Group WHERE Type = 'Queue'
                AND DeveloperName = 'CS_Onboarding_Backlog' LIMIT 1].Id;
    }
    private static Opportunity createOpenDeal(String suffix) {
        Account customer = new Account(Name = 'Stage Test ' + suffix);
        insert customer;
        Opportunity deal = new Opportunity(
            Name = 'Stage Test Deal ' + suffix,
            AccountId = customer.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert deal;
        return deal;
    }
    private static Onboarding__c startOne(String suffix) {
        Opportunity deal = createOpenDeal(suffix);
        Onboarding__c ob = new Onboarding__c(
            Name = 'Stage Test Onboarding ' + suffix,
            Opportunity__c = deal.Id, Stage__c = 'Kickoff Scheduled',
            OwnerId = backlog(), Target_Go_Live__c = Date.today().addDays(30)
        );
        insert ob;
        return ob;
    }
    private static void move(Id onboardingId, String stage, String gatherNotes,
                             String implNotes, String failureReason) {
        Onboarding__c updateRow = new Onboarding__c(Id = onboardingId, Stage__c = stage);
        if (gatherNotes != null) updateRow.Gathering_Notes__c = gatherNotes;
        if (implNotes != null) updateRow.Implementation_Notes__c = implNotes;
        if (failureReason != null) updateRow.QA_Failure_Reason__c = failureReason;
        update updateRow;
    }
    @IsTest
    static void initialVisitAndTimestampsCreated() {
        Onboarding__c ob = startOne('Initial');
        Onboarding__c actual = [
            SELECT Kickoff_First_At__c, Stage_Entered_At__c
            FROM Onboarding__c WHERE Id = :ob.Id
        ];
        System.assertNotEquals(null, actual.Kickoff_First_At__c);
        System.assertEquals(actual.Kickoff_First_At__c, actual.Stage_Entered_At__c);
        List<Onboarding_Stage_Visit__c> visits = [
            SELECT Stage__c, Entered_At__c, Exited_At__c, Visit_Number__c
            FROM Onboarding_Stage_Visit__c WHERE Onboarding__c = :ob.Id
        ];
        System.assertEquals(1, visits.size());
        System.assertEquals('Kickoff Scheduled', visits[0].Stage__c);
        System.assertEquals(null, visits[0].Exited_At__c);
        System.assertEquals(actual.Stage_Entered_At__c, visits[0].Entered_At__c);
        System.assertEquals(Decimal.valueOf('1'), visits[0].Visit_Number__c);
    }
    @IsTest
    static void rejectsSkipAndRequiresBothTypesOfNotes() {
        Onboarding__c ob = startOne('Rules');
        Database.SaveResult skipped = Database.update(new Onboarding__c(
            Id = ob.Id, Stage__c = 'Implementation'
        ), false);
        System.assertEquals(false, skipped.isSuccess(), 'Skipping must be rejected.');
        move(ob.Id, 'Gathering Info', null, null, null);
        Database.SaveResult noGatherNotes = Database.update(new Onboarding__c(
            Id = ob.Id, Stage__c = 'Implementation'
        ), false);
        System.assertEquals(false, noGatherNotes.isSuccess());
        move(ob.Id, 'Implementation', 'Requirements received', null, null);
        Database.SaveResult noImplNotes = Database.update(new Onboarding__c(
            Id = ob.Id, Stage__c = 'QA / Review'
        ), false);
        System.assertEquals(false, noImplNotes.isSuccess());
        move(ob.Id, 'QA / Review', null, 'Configured and tested', null);
        System.assertEquals('QA / Review', [
            SELECT Stage__c FROM Onboarding__c WHERE Id = :ob.Id
        ].Stage__c);
        System.assertEquals(4, [
            SELECT COUNT() FROM Onboarding_Stage_Visit__c WHERE Onboarding__c = :ob.Id
        ]);
    }
    @IsTest
    static void qaReworkCreatesRepeatedVisitsAndPreservesMilestones() {
        Onboarding__c ob = startOne('Rework');
        move(ob.Id, 'Gathering Info', null, null, null);
        move(ob.Id, 'Implementation', 'Gathered information', null, null);
        move(ob.Id, 'QA / Review', null, 'First implementation complete', null);
        Onboarding__c beforeRollback = [
            SELECT Implementation_First_At__c, QA_Review_First_At__c
            FROM Onboarding__c WHERE Id = :ob.Id
        ];
        Database.SaveResult noReason = Database.update(new Onboarding__c(
            Id = ob.Id, Stage__c = 'Implementation'
        ), false);
        System.assertEquals(false, noReason.isSuccess());
        move(ob.Id, 'Implementation', null, null, 'QA found an integration mismatch');
        move(ob.Id, 'QA / Review', null, 'Rework and retest complete', null);
        Onboarding__c afterRework = [
            SELECT Implementation_First_At__c, QA_Review_First_At__c,
                   QA_Failure_Reason__c, Stage__c
            FROM Onboarding__c WHERE Id = :ob.Id
        ];
        System.assertEquals(beforeRollback.Implementation_First_At__c,
                            afterRework.Implementation_First_At__c);
        System.assertEquals(beforeRollback.QA_Review_First_At__c,
                            afterRework.QA_Review_First_At__c);
        System.assertEquals(null, afterRework.QA_Failure_Reason__c,
            'Old QA failure reason must be cleared on return to QA.');
        move(ob.Id, 'Go Live', null, null, null);
        move(ob.Id, 'Post-Launch Review', null, null, null);
        Database.SaveResult terminal = Database.update(new Onboarding__c(
            Id = ob.Id, Stage__c = 'Go Live'
        ), false);
        System.assertEquals(false, terminal.isSuccess(), 'Post-Launch must be terminal.');

        List<Onboarding_Stage_Visit__c> visits = [
            SELECT Stage__c, Entered_At__c, Exited_At__c, Visit_Number__c,
                   Duration_Hours__c
            FROM Onboarding_Stage_Visit__c WHERE Onboarding__c = :ob.Id
            ORDER BY Visit_Number__c ASC
        ];
        System.assertEquals(8, visits.size());
        System.assertEquals('Implementation', visits[2].Stage__c);
        System.assertEquals('Implementation', visits[4].Stage__c);
        System.assertEquals('QA / Review', visits[3].Stage__c);
        System.assertEquals('QA / Review', visits[5].Stage__c);
        for (Integer i = 0; i < visits.size(); i++) {
            System.assertEquals(Decimal.valueOf(String.valueOf(i + 1)),
                                visits[i].Visit_Number__c);
            System.assertNotEquals(null, visits[i].Entered_At__c);
            if (i < visits.size() - 1) {
                System.assertNotEquals(null, visits[i].Exited_At__c);
                System.assert(visits[i].Duration_Hours__c >= 0);
            } else {
                System.assertEquals(null, visits[i].Exited_At__c);
            }
        }
    }
    @IsTest
    static void historicalTimestampsCannotBeEditedOrPrefilled() {
        Onboarding__c ob = startOne('Immutable');
        Database.SaveResult forged = Database.update(new Onboarding__c(
            Id = ob.Id, Kickoff_First_At__c = System.now().addDays(-7)
        ), false);
        System.assertEquals(false, forged.isSuccess());
        Database.SaveResult forgedStage = Database.update(new Onboarding__c(
            Id = ob.Id, Stage_Entered_At__c = System.now().addDays(-1)
        ), false);
        System.assertEquals(false, forgedStage.isSuccess());
        Database.SaveResult forgedFuture = Database.update(new Onboarding__c(
            Id = ob.Id, Go_Live_First_At__c = System.now()
        ), false);
        System.assertEquals(false, forgedFuture.isSuccess());
        Opportunity another = createOpenDeal('Forged-Insert');
        Database.SaveResult prefilled = Database.insert(new Onboarding__c(
            Name = 'Forged Entry', Opportunity__c = another.Id,
            OwnerId = backlog(), Kickoff_First_At__c = System.now()
        ), false);
        System.assertEquals(false, prefilled.isSuccess());
    }
    @IsTest
    static void legacyOnboardingWithNoVisitBackfillsOldInterval() {
        Onboarding__c ob = startOne('Legacy');
        delete [SELECT Id FROM Onboarding_Stage_Visit__c WHERE Onboarding__c = :ob.Id];
        move(ob.Id, 'Gathering Info', null, null, null);
        List<Onboarding_Stage_Visit__c> visits = [
            SELECT Stage__c, Exited_At__c, Visit_Number__c
            FROM Onboarding_Stage_Visit__c WHERE Onboarding__c = :ob.Id
            ORDER BY Visit_Number__c ASC
        ];
        System.assertEquals(2, visits.size());
        System.assertEquals('Kickoff Scheduled', visits[0].Stage__c);
        System.assertNotEquals(null, visits[0].Exited_At__c);
        System.assertEquals('Gathering Info', visits[1].Stage__c);
        System.assertEquals(null, visits[1].Exited_At__c);
    }
    @IsTest
    static void invalidStageInBulkCannotFalselyReleaseCSMCapacity() {
        // A rejected direct Kickoff->Post-Launch must not free capacity for
        // an incoming CSM assignment in the same partial-success batch.
        insert new CSM_Capacity__c(CSM_User__c = UserInfo.getUserId(),
            Max_Capacity__c = 1, Is_Active__c = true);
        Account a = new Account(Name = 'Invalid Stage Capacity Test');
        insert a;
        List<Opportunity> deals = new List<Opportunity>{
            new Opportunity(Name = 'Capacity 1', AccountId = a.Id,
                StageName = 'Closed Won', CloseDate = Date.today()),
            new Opportunity(Name = 'Capacity 2', AccountId = a.Id,
                StageName = 'Closed Won', CloseDate = Date.today())
        };
        insert deals;
        Set<Id> ids = new Map<Id, Opportunity>(deals).keySet();
        List<Onboarding__c> onboardings = [
            SELECT Id, OwnerId, Stage__c FROM Onboarding__c WHERE Opportunity__c IN :ids
        ];
        Id csmRow;
        Id backlogRow;
        for (Onboarding__c row : onboardings) {
            if (row.OwnerId == UserInfo.getUserId()) csmRow = row.Id;
            else backlogRow = row.Id;
        }
        System.assertNotEquals(null, csmRow);
        System.assertNotEquals(null, backlogRow);
        Database.SaveResult[] results = Database.update(new List<Onboarding__c>{
            new Onboarding__c(Id = csmRow, Stage__c = 'Post-Launch Review'),
            new Onboarding__c(Id = backlogRow, OwnerId = UserInfo.getUserId())
        }, false);
        System.assertEquals(false, results[0].isSuccess());
        System.assertEquals(false, results[1].isSuccess());
        System.assertEquals('Kickoff Scheduled', [
            SELECT Stage__c FROM Onboarding__c WHERE Id = :csmRow
        ].Stage__c);
        System.assertEquals(backlog(), [
            SELECT OwnerId FROM Onboarding__c WHERE Id = :backlogRow
        ].OwnerId);
    }

    @IsTest
    static void bulk200StageUpdatesCreateOneVisitEach() {
        Account account = new Account(Name = 'Bulk Stage Updates');
        insert account;
        List<Opportunity> deals = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            deals.add(new Opportunity(Name = 'Bulk Stage Deal ' + i,
                AccountId = account.Id, StageName = 'Prospecting',
                CloseDate = Date.today()));
        }
        insert deals;
        List<Onboarding__c> onboardingRows = new List<Onboarding__c>();
        Id queue = backlog();
        for (Opportunity deal : deals) {
            onboardingRows.add(new Onboarding__c(
                Name = 'Bulk Stage - ' + deal.Name,
                Opportunity__c = deal.Id, OwnerId = queue,
                Stage__c = 'Kickoff Scheduled'
            ));
        }
        insert onboardingRows;
        Test.startTest();
        for (Onboarding__c row : onboardingRows) row.Stage__c = 'Gathering Info';
        update onboardingRows;
        Test.stopTest();
        Set<Id> ids = new Map<Id, Onboarding__c>(onboardingRows).keySet();
        System.assertEquals(400, [
            SELECT COUNT() FROM Onboarding_Stage_Visit__c WHERE Onboarding__c IN :ids
        ]);
        System.assertEquals(200, [
            SELECT COUNT() FROM Onboarding_Stage_Visit__c
            WHERE Onboarding__c IN :ids AND Exited_At__c = null
        ]);
    }
}
