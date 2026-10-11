/**
 * @description Single trigger for Service_Agreement__c. Contains no logic: all behavior lives in
 *              ServiceAgreementTriggerHandler, so it can be tested and extended in one place.
 * @author      Enzo Fischer
 */
trigger ServiceAgreementTrigger on Service_Agreement__c(
  after insert,
  after update
) {
  new ServiceAgreementTriggerHandler().run(Trigger.operationType, Trigger.new);
}
