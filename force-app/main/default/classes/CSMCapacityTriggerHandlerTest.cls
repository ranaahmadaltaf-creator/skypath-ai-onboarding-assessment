@IsTest
private class CSMCapacityTriggerHandlerTest {
    @IsTest
    static void insertAndUpdatePopulateCanonicalUserKey() {
        Id csmUserId = UserInfo.getUserId();
        CSM_Capacity__c config = new CSM_Capacity__c(
            CSM_User__c = csmUserId,
            Is_Active__c = true,
            Max_Capacity__c = 5
        );

        insert config;
        config = [
            SELECT Id, CSM_User__c, CSM_User_Key__c, Max_Capacity__c
            FROM CSM_Capacity__c WHERE Id = :config.Id
        ];
        System.assertEquals(String.valueOf(csmUserId), config.CSM_User_Key__c,
            'Insert trigger must create the canonical 18-character user key.');

        config.Max_Capacity__c = 7;
        update config;
        CSM_Capacity__c saved = [
            SELECT Max_Capacity__c, CSM_User_Key__c
            FROM CSM_Capacity__c WHERE Id = :config.Id
        ];
        System.assertEquals(Decimal.valueOf('7'), saved.Max_Capacity__c);
        System.assertEquals(String.valueOf(csmUserId), saved.CSM_User_Key__c,
            'Changing capacity must not change the natural key.');
    }

    @IsTest
    static void rejectsUserKeyTamperingOnInsertAndUpdate() {
        Id csmUserId = UserInfo.getUserId();

        CSM_Capacity__c tamperedInsert = new CSM_Capacity__c(
            CSM_User__c = csmUserId,
            CSM_User_Key__c = 'MANUAL_KEY',
            Is_Active__c = true,
            Max_Capacity__c = 2
        );
        Database.SaveResult insertResult = Database.insert(tamperedInsert, false);
        System.assertEquals(false, insertResult.isSuccess(),
            'A manually supplied mismatched key must be rejected on insert.');

        CSM_Capacity__c config = new CSM_Capacity__c(
            CSM_User__c = csmUserId,
            Is_Active__c = true,
            Max_Capacity__c = 4
        );
        insert config;

        CSM_Capacity__c edited = new CSM_Capacity__c(
            Id = config.Id,
            CSM_User_Key__c = 'MANUAL_CHANGE'
        );
        Database.SaveResult updateResult = Database.update(edited, false);
        System.assertEquals(false, updateResult.isSuccess(),
            'The update trigger must prevent manual key tampering.');

        System.assertEquals(String.valueOf(csmUserId), [
            SELECT CSM_User_Key__c FROM CSM_Capacity__c WHERE Id = :config.Id
        ].CSM_User_Key__c, 'Rejected updates must not modify the stored key.');
    }

    @IsTest
    static void rejectsMissingUserAndNegativeCapacity() {
        CSM_Capacity__c missingUser = new CSM_Capacity__c(
            Is_Active__c = true, Max_Capacity__c = 3
        );
        Database.SaveResult missingUserResult = Database.insert(missingUser, false);
        System.assertEquals(false, missingUserResult.isSuccess(),
            'Configuration without a CSM User must fail validation.');

        CSM_Capacity__c negative = new CSM_Capacity__c(
            CSM_User__c = UserInfo.getUserId(),
            Is_Active__c = true,
            Max_Capacity__c = -1
        );
        Database.SaveResult negativeResult = Database.insert(negative, false);
        System.assertEquals(false, negativeResult.isSuccess(),
            'Negative CSM capacity must fail validation.');
    }
}
