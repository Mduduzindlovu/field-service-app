public with sharing class CaseMapController {

    @AuraEnabled(cacheable=true)
    public static List<CaseMapRecord> getOpenCases() {
        List<CaseMapRecord> results = new List<CaseMapRecord>();

        List<Case> cases = [
            SELECT Id, CaseNumber, Subject, Status,
                   Locations__c, Locations__r.Name,
                   Locations__r.Coordinates__Latitude__s,
                   Locations__r.Coordinates__Longitude__s,
                   Assigned_Technician__c, Assigned_Technician__r.Name
            FROM Case
            WHERE Status != 'Closed'
            AND Locations__c != null
        ];

        for (Case c : cases) {
            results.add(new CaseMapRecord(c));
        }

        return results;
    }

    public class CaseMapRecord {
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String locationName;
        @AuraEnabled public Double latitude;
        @AuraEnabled public Double longitude;
        @AuraEnabled public String technicianName;

        public CaseMapRecord(Case c) {
            this.caseId = c.Id;
            this.caseNumber = c.CaseNumber;
            this.subject = c.Subject;
            this.status = c.Status;
            this.locationName = c.Locations__r != null ? c.Locations__r.Name : null;
            this.latitude = c.Locations__r != null ? c.Locations__r.Coordinates__Latitude__s : null;
            this.longitude = c.Locations__r != null ? c.Locations__r.Coordinates__Longitude__s : null;
            this.technicianName = c.Assigned_Technician__r != null ? c.Assigned_Technician__r.Name : null;
        }
    }
}