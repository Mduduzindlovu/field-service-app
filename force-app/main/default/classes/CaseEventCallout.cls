public with sharing class CaseEventCallout implements Queueable, Database.AllowsCallouts {
    private List<CaseStatusChanged__e> events;

    public CaseEventCallout(List<CaseStatusChanged__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
        // NOTE: Salesforce allows max 100 callouts per transaction.
        // Callers should batch events (≤50 per job) to stay within governor limits.

        List<SyncConfig__mdt> configs = [
            SELECT Endpoint_URL__c, Sync_Secret__c
            FROM SyncConfig__mdt
            WHERE DeveloperName = 'FieldServiceSync'
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            // CMDT record missing — log a failure for every event so nothing is silently lost
            List<Sync_Failure__c> configFailures = new List<Sync_Failure__c>();
            for (CaseStatusChanged__e evt : events) {
                Sync_Failure__c f = new Sync_Failure__c();
                f.Case_Id__c       = evt.Case_Id__c;
                f.Payload__c       = buildPayload(evt);
                f.Error_Message__c = 'SyncConfig__mdt record FieldServiceSync not found';
                f.Failed_At__c     = Datetime.now();
                f.Retry_Count__c   = 0;
                f.Resolved__c      = false;
                configFailures.add(f);
            }
            if (!configFailures.isEmpty()) {
                insert configFailures;
            }
            return;
        }

        SyncConfig__mdt config = configs[0];
        List<Sync_Failure__c> failures = new List<Sync_Failure__c>();

        for (CaseStatusChanged__e evt : events) {
            String payload = buildPayload(evt);
            String errorMsg = SyncCalloutUtil.sendPayload(
                payload, config.Endpoint_URL__c, config.Sync_Secret__c);

            if (errorMsg != null) {
                Sync_Failure__c failure = new Sync_Failure__c();
                failure.Case_Id__c       = evt.Case_Id__c;
                failure.Payload__c       = payload;
                failure.Error_Message__c = errorMsg;
                failure.Failed_At__c     = Datetime.now();
                failure.Retry_Count__c   = 0;
                failure.Resolved__c      = false;
                failures.add(failure);
            }
        }

        if (!failures.isEmpty()) {
            insert failures;
        }
    }

    private String buildPayload(CaseStatusChanged__e evt) {
        Map<String, Object> payload = new Map<String, Object>{
            'caseId'           => evt.Case_Id__c,
            'caseNumber'       => evt.Case_Number__c,
            'subject'          => evt.Subject__c,
            'status'           => evt.Status__c,
            'technicianId'     => evt.Assigned_Technician_Id__c,
            'technicianName'   => evt.Assigned_Technician_Name__c,
            'scheduledDate'    => evt.Scheduled_Date__c != null
                ? evt.Scheduled_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                : null,
            'locationName'     => evt.Location_Name__c,
            'latitude'         => evt.Latitude__c,
            'longitude'        => evt.Longitude__c,
            'lastModifiedDate' => evt.Last_Modified_Date__c != null
                ? evt.Last_Modified_Date__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                : null
        };
        return JSON.serialize(payload);
    }

}
