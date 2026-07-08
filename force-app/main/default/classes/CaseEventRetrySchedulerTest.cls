@isTest
private class CaseEventRetrySchedulerTest {

    private class MockHttpResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        MockHttpResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    private static Sync_Failure__c buildFailure(Integer retryCount) {
        return new Sync_Failure__c(
            Case_Id__c       = '500fj00001k99CMAAY',
            Payload__c       = '{"caseId":"500fj00001k99CMAAY","status":"New",'
                             + '"lastModifiedDate":"2026-07-08T08:00:00Z"}',
            Error_Message__c = 'HTTP 500',
            Failed_At__c     = Datetime.now().addHours(-1),
            Retry_Count__c   = retryCount,
            Resolved__c      = false
        );
    }

    @isTest
    static void resolvesFailureOnSuccessfulRetry() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, '{"ok":true}'));
        Sync_Failure__c failure = buildFailure(1);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c, Last_Retry_At__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(true, updated.Resolved__c, 'Should be resolved on 200');
        System.assertNotEquals(null, updated.Last_Retry_At__c,
            'Last_Retry_At__c must be set');
    }

    @isTest
    static void incrementsRetryCountOnFailedRetry() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(500, 'Server Error'));
        Sync_Failure__c failure = buildFailure(2);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c, Last_Retry_At__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(false, updated.Resolved__c);
        System.assertEquals(3, updated.Retry_Count__c,
            'Retry count should increment on failure');
        System.assertNotEquals(null, updated.Last_Retry_At__c,
            'Last_Retry_At__c must be set even on failed retry');
    }

    @isTest
    static void skipsFailuresAtMaxRetries() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, '{"ok":true}'));
        Sync_Failure__c failure = buildFailure(5);
        insert failure;

        Test.startTest();
        new CaseEventRetryScheduler().execute(null);
        Test.stopTest();

        Sync_Failure__c updated = [
            SELECT Resolved__c, Retry_Count__c
            FROM Sync_Failure__c WHERE Id = :failure.Id
        ];
        System.assertEquals(false, updated.Resolved__c,
            'Should not resolve record at max retries');
        System.assertEquals(5, updated.Retry_Count__c,
            'Retry count should not increment past 5');
    }
}
