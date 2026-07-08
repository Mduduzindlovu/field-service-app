public with sharing class CaseEventCallout implements Queueable, Database.AllowsCallouts {
    private List<CaseStatusChanged__e> events;

    public CaseEventCallout(List<CaseStatusChanged__e> events) {
        this.events = events;
    }

    public void execute(QueueableContext ctx) {
        SyncConfig__mdt config = [
            SELECT Endpoint_URL__c, Sync_Secret__c
            FROM SyncConfig__mdt
            WHERE DeveloperName = 'FieldServiceSync'
            LIMIT 1
        ];

        List<Sync_Failure__c> failures = new List<Sync_Failure__c>();

        for (CaseStatusChanged__e evt : events) {
            String payload = buildPayload(evt);
            String errorMsg = sendPayload(
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

    // Returns null on success, error message string on failure
    private String sendPayload(String payload, String endpointUrl, String secret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-sync-secret', secret);
        req.setBody(payload);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                return null;
            }
            return 'HTTP ' + res.getStatusCode() + ': '
                + res.getBody().abbreviate(200);
        } catch (Exception e) {
            return e.getMessage().abbreviate(255);
        }
    }
}
