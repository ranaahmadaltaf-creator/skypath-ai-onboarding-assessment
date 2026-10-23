@IsTest
private class OnboardingAssignmentServiceTest {
    @TestSetup
    static void makeTestUsers() {
        List<User> newUsers = new List<User>();
        for (Integer i = 0; i < 2; i++) {
            newUsers.add(new User(
                FirstName = 'SkyPath', LastName = 'AssignmentTester',
                Alias = 'spct' + i,
                Email = 'skypath.assignee.' + i + '@example.org',
                Username = 'spct.' + UserInfo.getOrganizationId() + '.'
                    + System.now().getTime() + '.' + i + '@example.org',
                ProfileId = UserInfo.getProfileId(),
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
            ));
        }
        insert newUsers;
        PermissionSet managerPermission = [
            SELECT Id FROM PermissionSet
            WHERE Name = 'SkyPath_Onboarding_Manager'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = newUsers[0].Id,
            PermissionSetId = managerPermission.Id
        );
    }

    private static List<User> csms() {
        List<User> users = [
            SELECT Id, Alias FROM User WHERE LastName = 'AssignmentTester'
            ORDER BY Alias ASC
        ];
        System.assertEquals(2, users.size());
        return users;
    }
    private static Id queueId() {
        return [SELECT Id FROM Group WHERE Type = 'Queue'
                AND DeveloperName = 'CS_Onboarding_Backlog' LIMIT 1].Id;
    }
    private static void createConfig(User u, Integer maxCapacity) {
        insert new CSM_Capacity__c(
            CSM_User__c = u.Id, Max_Capacity__c = maxCapacity, Is_Active__c = true
        );
    }
    private static List<Opportunity> createWon(Integer howMany) {
        Account a = new Account(Name = 'Assignment Test Account');
        insert a;
        List<Opportunity> deals = new List<Opportunity>();
        for (Integer i = 0; i < howMany; i++) {
            deals.add(new Opportunity(
                Name = 'Assignment Deal ' + i, StageName = 'Closed Won',
                AccountId = a.Id, CloseDate = Date.today()
            ));
        }
        insert deals;
        return deals;
    }

    @IsTest
    static void bulk200RespectsCapacityAndBalancesWorkload() {
        List<User> users = csms();
        createConfig(users[0], 60);
        createConfig(users[1], 50);
        Id queue = queueId();
        Test.startTest();
        List<Opportunity> deals = createWon(200);
        Test.stopTest();
        Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();
        Map<Id, Integer> assigned = new Map<Id, Integer>();
        Set<Id> seenDeals = new Set<Id>();
        for (Onboarding__c o : [
            SELECT OwnerId, Opportunity__c, Stage__c, Assigned_At__c
            FROM Onboarding__c WHERE Opportunity__c IN :dealIds
        ]) {
            seenDeals.add(o.Opportunity__c);
            assigned.put(o.OwnerId,
                (assigned.containsKey(o.OwnerId) ? assigned.get(o.OwnerId) : 0) + 1
            );
            if (o.OwnerId != queue)
                System.assertNotEquals(null, o.Assigned_At__c);
        }
        System.assertEquals(200, seenDeals.size());
        System.assertEquals(60, assigned.get(users[0].Id));
        System.assertEquals(50, assigned.get(users[1].Id));
        System.assertEquals(90, assigned.get(queue));
    }

    @IsTest
    static void swapAtFullCapacityAllowedButOverCapacityBlocked() {
        List<User> users = csms();
        createConfig(users[0], 2);
        createConfig(users[1], 2);
        List<Opportunity> deals = createWon(4);
        List<Onboarding__c> aRows = [
            SELECT Id, OwnerId FROM Onboarding__c WHERE OwnerId = :users[0].Id LIMIT 2
        ];
        List<Onboarding__c> bRows = [
            SELECT Id, OwnerId FROM Onboarding__c WHERE OwnerId = :users[1].Id LIMIT 2
        ];
        System.assertEquals(2, aRows.size());
        System.assertEquals(2, bRows.size());
        // Net deltas are zero despite both CSMs starting at full capacity.
        System.runAs(users[0]) {
        aRows[0].OwnerId = users[1].Id;
        bRows[0].OwnerId = users[0].Id;
        update new List<Onboarding__c>{aRows[0], bRows[0]};
        Onboarding__c blocked = new Onboarding__c(
            Id = aRows[1].Id, OwnerId = users[1].Id
        );
        Database.SaveResult result = Database.update(blocked, false);
        System.assertEquals(false, result.isSuccess(), 'Capacity overflow must be rejected.');
        }
    }

    @IsTest
    static void loweringCapacityStopsNewAssignmentsAndStageCompletionFreesSpace() {
        List<User> users = csms();
        createConfig(users[0], 2);
        createConfig(users[1], 0);
        List<Opportunity> first = createWon(2);
        CSM_Capacity__c config = [
            SELECT Id, Max_Capacity__c FROM CSM_Capacity__c WHERE CSM_User__c = :users[0].Id LIMIT 1
        ];
        config.Max_Capacity__c = 1;
        update config; // Existing assignments remain; new assignments pause.
        List<Opportunity> more = createWon(1);
        Onboarding__c overflow = [
            SELECT OwnerId FROM Onboarding__c WHERE Opportunity__c = :more[0].Id
        ];
        System.assertEquals(queueId(), overflow.OwnerId);
        Set<Id> firstIds = new Map<Id, Opportunity>(first).keySet();
        List<Onboarding__c> completed = [
            SELECT Id, Stage__c FROM Onboarding__c WHERE Opportunity__c IN :firstIds
        ];
        for (Onboarding__c o : completed) o.Stage__c = 'Gathering Info';
        update completed;
        for (Onboarding__c o : completed) {
            o.Stage__c = 'Implementation';
            o.Gathering_Notes__c = 'Customer provided contacts and requirements.';
        }
        update completed;
        for (Onboarding__c o : completed) {
            o.Stage__c = 'QA / Review';
            o.Implementation_Notes__c = 'Implementation work completed.';
        }
        update completed;
        for (Onboarding__c o : completed) o.Stage__c = 'Go Live';
        update completed;
        for (Onboarding__c o : completed) o.Stage__c = 'Post-Launch Review';
        update completed;
        List<Opportunity> after = createWon(1);
        Onboarding__c next = [
            SELECT OwnerId FROM Onboarding__c WHERE Opportunity__c = :after[0].Id
        ];
        System.assertEquals(users[0].Id, next.OwnerId);
    }

    @IsTest
    static void manualQueueToEligibleCSMAndInactiveUserRestrictions() {
        List<User> users = csms();
        createConfig(users[0], 1);
        createConfig(users[1], 0);
        Id queue = queueId();
        List<Opportunity> deals = createWon(2);
        Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();
        List<Onboarding__c> onboardings = [
            SELECT Id, OwnerId FROM Onboarding__c WHERE Opportunity__c IN :dealIds
        ];
        Id backlogId;
        for (Onboarding__c o : onboardings) {
            if (o.OwnerId == queue) backlogId = o.Id;
        }
        System.assertNotEquals(null, backlogId);
        System.runAs(users[0]) {
        Database.SaveResult blocked = Database.update(new Onboarding__c(
            Id = backlogId, OwnerId = users[1].Id
        ), false);
        System.assertEquals(false, blocked.isSuccess(), 'Zero-capacity owner must be blocked.');
        // Reassign the active first CSM to the queue, freeing room for the queued record.
        Id activeId;
        for (Onboarding__c o : onboardings) {
            if (o.OwnerId == users[0].Id) activeId = o.Id;
        }
        update new Onboarding__c(Id = activeId, OwnerId = queue);
        update new Onboarding__c(Id = backlogId, OwnerId = users[0].Id);
        Onboarding__c accepted = [
            SELECT OwnerId, Assigned_At__c FROM Onboarding__c WHERE Id = :backlogId
        ];
        System.assertEquals(users[0].Id, accepted.OwnerId);
        System.assertNotEquals(null, accepted.Assigned_At__c);
        }
    }

    @IsTest
    static void unconfiguredManualOwnerRejected() {
        Id queue = queueId();
        Account a = new Account(Name = 'Manual User Owner Test');
        insert a;
        Opportunity openDeal = new Opportunity(
            Name = 'Manual Owner Test', AccountId = a.Id,
            CloseDate = Date.today(), StageName = 'Prospecting'
        );
        insert openDeal;
        Onboarding__c invalid = new Onboarding__c(
            Name = 'Manual Owner Test', Opportunity__c = openDeal.Id,
            OwnerId = UserInfo.getUserId(), Stage__c = 'Kickoff Scheduled'
        );
        Database.SaveResult result = Database.insert(invalid, false);
        System.assertEquals(false, result.isSuccess(), 'Unconfigured User ownership must fail.');
        Onboarding__c valid = new Onboarding__c(
            Name = 'Manual Queue Test', Opportunity__c = openDeal.Id,
            OwnerId = queue, Stage__c = 'Kickoff Scheduled'
        );
        insert valid;
        System.assertEquals(queue, [SELECT OwnerId FROM Onboarding__c WHERE Id = :valid.Id].OwnerId);
    }

    @IsTest
    static void regularCsmTransferIsRejected() {
        List<User> users = csms();
        createConfig(users[0], 2);
        createConfig(users[1], 1);
        createWon(2);

        Onboarding__c owned = [
            SELECT Id FROM Onboarding__c
            WHERE OwnerId = :users[1].Id
            LIMIT 1
        ];

        System.runAs(users[1]) {
            Database.SaveResult result = Database.update(
                new Onboarding__c(
                    Id = owned.Id,
                    OwnerId = users[0].Id
                ),
                false
            );

            System.assertEquals(false, result.isSuccess());
            System.assert(
                result.getErrors()[0].getMessage()
                    .contains('Only authorized managers'),
                'Unauthorized ownership transfer must be rejected.'
            );
        }
    }
}
