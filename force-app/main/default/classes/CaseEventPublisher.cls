public with sharing class CaseEventPublisher {

    @TestVisible
    private static List<CaseStatusChanged__e> publishedEvents = new List<CaseStatusChanged__e>();

    public static void publish(List<Case> newCases, Map<Id, Case> oldMap) {
        List<Id> caseIdsToPublish = new List<Id>();

        for (Case c : newCases) {
            // Skip Cases with no Location — they can't populate lat/lon.
            // This means a location-removal update (value → null) produces no event,
            // which is intentional: a Case without a location is invisible to the
            // dispatcher map and the Postgres cache regardless.
            if (c.Locations__c == null) {
                continue;
            }

            if (oldMap == null) {
                // Insert context — publish for all Cases with a Location
                caseIdsToPublish.add(c.Id);
            } else {
                // Update context — publish only if a watched field changed
                Case old = oldMap.get(c.Id);
                if (c.Status != old.Status
                    || c.Assigned_Technician__c != old.Assigned_Technician__c
                    || c.Scheduled_Date__c != old.Scheduled_Date__c
                    || c.Locations__c != old.Locations__c) {
                    caseIdsToPublish.add(c.Id);
                }
            }
        }

        if (caseIdsToPublish.isEmpty()) {
            return;
        }

        List<Case> enriched = [
            SELECT Id, CaseNumber, Subject, Status,
                   Assigned_Technician__c, Assigned_Technician__r.Name,
                   Scheduled_Date__c, LastModifiedDate,
                   Locations__c, Locations__r.Name,
                   Locations__r.Coordinates__Latitude__s,
                   Locations__r.Coordinates__Longitude__s
            FROM Case
            WHERE Id IN :caseIdsToPublish
        ];

        List<CaseStatusChanged__e> events = new List<CaseStatusChanged__e>();
        for (Case c : enriched) {
            CaseStatusChanged__e evt = new CaseStatusChanged__e();
            evt.Case_Id__c                  = c.Id;
            evt.Case_Number__c              = c.CaseNumber;
            evt.Subject__c                  = c.Subject;
            evt.Status__c                   = c.Status;
            evt.Assigned_Technician_Id__c   = c.Assigned_Technician__c;
            evt.Assigned_Technician_Name__c =
                c.Assigned_Technician__r != null ? c.Assigned_Technician__r.Name : null;
            evt.Scheduled_Date__c           = c.Scheduled_Date__c;
            evt.Last_Modified_Date__c       = c.LastModifiedDate;
            evt.Location_Name__c            =
                c.Locations__r != null ? c.Locations__r.Name : null;
            evt.Latitude__c                 =
                c.Locations__r != null ? c.Locations__r.Coordinates__Latitude__s : null;
            evt.Longitude__c                =
                c.Locations__r != null ? c.Locations__r.Coordinates__Longitude__s : null;
            events.add(evt);
        }

        publishedEvents.addAll(events);
        EventBus.publish(events);
    }
}
