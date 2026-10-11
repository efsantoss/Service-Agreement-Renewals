/**
 * @description Routes ServiceAgreementTrigger events to the right service. Contains no business
 *              rules: it only decides what runs in each trigger context and reports failures
 *              back to the records being saved.
 *
 *              No static "already ran" flag is used to stop recursion. Such flags break bulk
 *              loads larger than 200 records (the platform splits them into chunks within one
 *              transaction). Instead, the service is idempotent: once an agreement has its
 *              Renewal_Task_Id__c marker, later passes skip it without spending queries.
 * @author      Enzo Fischer
 */
public with sharing class ServiceAgreementTriggerHandler {
  @TestVisible
  private static final String RENEWAL_TASK_ERROR = 'The Renewal Task could not be created: ';

  private final RenewalTaskService renewalTaskService;

  /**
   * @description Creates the handler with the default service.
   */
  public ServiceAgreementTriggerHandler() {
    this(new RenewalTaskService());
  }

  /**
   * @description Creates the handler with an explicit service (dependency injection).
   * @param renewalTaskService Service that creates the Renewal Tasks.
   */
  public ServiceAgreementTriggerHandler(RenewalTaskService renewalTaskService) {
    this.renewalTaskService = renewalTaskService;
  }

  /**
   * @description Entry point called by the trigger.
   * @param operation  The trigger context (Trigger.operationType).
   * @param newRecords The records being saved (Trigger.new).
   */
  public void run(
    System.TriggerOperation operation,
    List<Service_Agreement__c> newRecords
  ) {
    switch on operation {
      when AFTER_INSERT, AFTER_UPDATE {
        // After context: the agreement Id exists and is used as the Task WhatId.
        createRenewalTasks(newRecords);
      }
      when else {
        // No logic for other contexts yet.
        return;
      }
    }
  }

  private void createRenewalTasks(List<Service_Agreement__c> records) {
    Map<Id, String> errorsByAgreementId = renewalTaskService.createRenewalTasks(
      records
    );
    if (errorsByAgreementId.isEmpty()) {
      return;
    }
    // Surface failures on the agreement itself, so a renewal is never dropped silently.
    for (Service_Agreement__c record : records) {
      if (errorsByAgreementId.containsKey(record.Id)) {
        record.addError(
          RENEWAL_TASK_ERROR + errorsByAgreementId.get(record.Id)
        );
      }
    }
  }
}
