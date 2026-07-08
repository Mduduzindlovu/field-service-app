trigger CaseStatusChangedTrigger on CaseStatusChanged__e (after insert) {
    System.enqueueJob(new CaseEventCallout(Trigger.new));
}
