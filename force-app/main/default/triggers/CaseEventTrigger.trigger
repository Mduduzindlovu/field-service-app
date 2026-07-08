trigger CaseEventTrigger on Case (after insert, after update) {
    CaseEventPublisher.publish(Trigger.new, Trigger.oldMap);
}
