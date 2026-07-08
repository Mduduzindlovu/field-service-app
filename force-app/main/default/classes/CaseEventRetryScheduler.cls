public with sharing class CaseEventRetryScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {
        // LIMIT 100 matches Salesforce's max callouts per transaction
        List<Sync_Failure__c> failures = [
            SELECT Id, Payload__c, Retry_Count__c
            FROM Sync_Failure__c
            WHERE Resolved__c = false
            AND Retry_Count__c < 5
            LIMIT 100
        ];

        if (failures.isEmpty()) {
            return;
        }

        List<SyncConfig__mdt> configs = [
            SELECT Endpoint_URL__c, Sync_Secret__c
            FROM SyncConfig__mdt
            WHERE DeveloperName = 'FieldServiceSync'
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return;
        }

        SyncConfig__mdt config = configs[0];
        List<Sync_Failure__c> toUpdate = new List<Sync_Failure__c>();

        for (Sync_Failure__c failure : failures) {
            String errorMsg = SyncCalloutUtil.sendPayload(
                failure.Payload__c,
                config.Endpoint_URL__c,
                config.Sync_Secret__c
            );

            failure.Last_Retry_At__c = Datetime.now();

            if (errorMsg == null) {
                failure.Resolved__c = true;
            } else {
                failure.Retry_Count__c += 1;
                failure.Error_Message__c = errorMsg;
            }

            toUpdate.add(failure);
        }

        update toUpdate;
    }
}
