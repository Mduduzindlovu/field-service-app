public with sharing class SyncCalloutUtil {

    /**
     * POST payload to endpointUrl with x-sync-secret header.
     * Returns null on 2xx success, or an error message string on failure.
     */
    public static String sendPayload(String payload, String endpointUrl, String secret) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointUrl);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-sync-secret', secret);
        req.setBody(payload);

        try {
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return null;
            }
            return 'HTTP ' + res.getStatusCode() + ': '
                + res.getBody().abbreviate(200);
        } catch (Exception e) {
            return e.getMessage().abbreviate(255);
        }
    }
}
