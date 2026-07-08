@isTest
private class CaseEventCalloutTest {

    // Mock captures the outgoing request so tests can assert on payload shape
    private class CapturingMock implements HttpCalloutMock {
        public HttpRequest capturedRequest;
        private Integer statusCode;
        private String body;

        CapturingMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            this.capturedRequest = req;
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static CaseStatusChanged__e buildTestEvent() {
        CaseStatusChanged__e evt = new CaseStatusChanged__e();
        evt.Case_Id__c                  = '500fj00001k99CMAAY';
        evt.Case_Number__c              = '00001026';
        evt.Subject__c                  = 'Rooftop AC unit down';
        evt.Status__c                   = 'Working';
        evt.Assigned_Technician_Id__c   = '005fj00000IDO8cAAH';
        evt.Assigned_Technician_Name__c = 'Mduduzi Ndlovu';
        evt.Scheduled_Date__c           = Datetime.newInstance(2026, 7, 10, 9, 0, 0);
        evt.Location_Name__c            = 'Riverside Mall';
        evt.Latitude__c                 = -33.9249;
        evt.Longitude__c                = 18.4241;
        evt.Last_Modified_Date__c       = Datetime.newInstance(2026, 7, 8, 8, 0, 0);
        return evt;
    }

    @isTest
    static void postsCorrectJsonPayloadOn200() {
        CapturingMock mock = new CapturingMock(200, '{"ok":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new CaseEventCallout(
            new List<CaseStatusChanged__e>{ buildTestEvent() }
        ));
        Test.stopTest();

        // Assert no failure records on success
        System.assertEquals(0,
            [SELECT Id FROM Sync_Failure__c].size(),
            'Expected no failures on 200');

        // Assert all 11 camelCase field mappings in the JSON body
        System.assertNotEquals(null, mock.capturedRequest, 'Request must have been sent');
        Map<String, Object> sent = (Map<String, Object>)
            JSON.deserializeUntyped(mock.capturedRequest.getBody());

        System.assertEquals('500fj00001k99CMAAY',  sent.get('caseId'));
        System.assertEquals('00001026',             sent.get('caseNumber'));
        System.assertEquals('Rooftop AC unit down', sent.get('subject'));
        System.assertEquals('Working',              sent.get('status'));
        System.assertEquals('005fj00000IDO8cAAH',   sent.get('technicianId'));
        System.assertEquals('Mduduzi Ndlovu',       sent.get('technicianName'));
        System.assertNotEquals(null,                sent.get('scheduledDate'));
        System.assertEquals('Riverside Mall',       sent.get('locationName'));
        System.assertEquals(-33.9249,               sent.get('latitude'));
        System.assertEquals(18.4241,                sent.get('longitude'));
        System.assertNotEquals(null,                sent.get('lastModifiedDate'));

        // Assert headers
        System.assertEquals('application/json',
            mock.capturedRequest.getHeader('Content-Type'));
        System.assertNotEquals(null,
            mock.capturedRequest.getHeader('x-sync-secret'),
            'Secret header must be set');
    }

    @isTest
    static void insertsSyncFailureRecordOnNon200() {
        CapturingMock mock = new CapturingMock(500, 'Server Error');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new CaseEventCallout(
            new List<CaseStatusChanged__e>{ buildTestEvent() }
        ));
        Test.stopTest();

        List<Sync_Failure__c> failures = [
            SELECT Case_Id__c, Error_Message__c, Retry_Count__c,
                   Resolved__c, Payload__c, Failed_At__c
            FROM Sync_Failure__c
        ];
        System.assertEquals(1, failures.size(), 'Expected 1 failure record');
        System.assertEquals('500fj00001k99CMAAY', failures[0].Case_Id__c);
        System.assertEquals(0,     failures[0].Retry_Count__c);
        System.assertEquals(false, failures[0].Resolved__c);
        System.assertNotEquals(null, failures[0].Payload__c,
            'Payload must be stored for retry');
        System.assertNotEquals(null, failures[0].Failed_At__c);

        // Payload must include lastModifiedDate for ordering guard on retry
        Map<String, Object> storedPayload = (Map<String, Object>)
            JSON.deserializeUntyped(failures[0].Payload__c);
        System.assertNotEquals(null, storedPayload.get('lastModifiedDate'),
            'Stored payload must include lastModifiedDate');
    }
}
