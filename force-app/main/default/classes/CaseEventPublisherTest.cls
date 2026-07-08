@isTest
private class CaseEventPublisherTest {

    @TestSetup
    static void makeData() {
        Locations__c loc = new Locations__c(
            Name = 'Test Site',
            Coordinates__Latitude__s = -33.9249,
            Coordinates__Longitude__s = 18.4241
        );
        insert loc;

        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            Locations__c = loc.Id
        );
        insert c;
    }

    @isTest
    static void publishesEventOnInsert() {
        Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

        Test.startTest();
        Case c = new Case(
            Subject = 'New Install',
            Status = 'New',
            Locations__c = loc.Id
        );
        insert c;
        Test.stopTest();

        // Events captured via @TestVisible accumulator in CaseEventPublisher.
        List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;

        System.assertEquals(1, events.size(), 'Expected 1 event on insert');
        System.assertEquals('New Install', events[0].Subject__c);
        System.assertEquals('New', events[0].Status__c);
        System.assertNotEquals(null, events[0].Case_Id__c);
        System.assertNotEquals(null, events[0].Latitude__c);
        System.assertNotEquals(null, events[0].Longitude__c);
    }

    @isTest
    static void publishesEventOnStatusChange() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        c.Status = 'Working';
        update c;
        Test.stopTest();

        List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;

        System.assertEquals(1, events.size(), 'Expected 1 event on status change');
        System.assertEquals('Working', events[0].Status__c);
    }

    @isTest
    static void noEventWhenUnrelatedFieldChanges() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        c.Description = 'Updated description only';
        update c;
        Test.stopTest();

        List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;

        System.assertEquals(0, events.size(), 'Expected no events for unrelated field change');
    }

    @isTest
    static void publishesOneEventPerChangedCaseInBulkUpdate() {
        Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

        // Insert 5 Cases — all with a Location so all 5 will produce events
        List<Case> cases = new List<Case>();
        for (Integer i = 0; i < 5; i++) {
            cases.add(new Case(
                Subject = 'Bulk Case ' + i,
                Status = 'New',
                Locations__c = loc.Id
            ));
        }
        insert cases;

        // Clear insert events from the accumulator — the 5 inserts above fire the trigger
        // and populate publishedEvents. Clear before the update so the assertion counts
        // only update-triggered events (the 5 we care about).
        CaseEventPublisher.publishedEvents.clear();

        Test.startTest();
        for (Case cas : cases) {
            cas.Status = 'Working';
        }
        update cases;
        Test.stopTest();

        List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;

        System.assertEquals(5, events.size(),
            'Expected exactly 1 event per updated Case, got ' + events.size());
    }

    @isTest
    static void publishesEventOnLocationChange() {
        Locations__c loc = [SELECT Id FROM Locations__c LIMIT 1];

        // Create a second location to reassign the case to
        Locations__c loc2 = new Locations__c(
            Name = 'New Site',
            Coordinates__Latitude__s = -33.8000,
            Coordinates__Longitude__s = 18.5000
        );
        insert loc2;

        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        c.Locations__c = loc2.Id;
        update c;
        Test.stopTest();

        List<CaseStatusChanged__e> events = CaseEventPublisher.publishedEvents;
        System.assertEquals(1, events.size(), 'Expected 1 event on location change');
        System.assertEquals('New Site', events[0].Location_Name__c);
    }
}
