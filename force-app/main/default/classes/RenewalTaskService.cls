/**
 * @description Creates the Renewal Task for Service Agreements that require renewal attention.
 *
 *              Duplicate prevention works in three layers:
 *                1. Marker: Renewal_Task_Id__c on the agreement stores the created Task Id; an
 *                   agreement with a marker never receives another Task.
 *                2. Locked fresh read: decisions use a FOR UPDATE re-read instead of the possibly
 *                   stale trigger records, which serializes concurrent saves of one agreement.
 *                3. Secondary check: an existing Renewal Task found by WhatId restores the marker
 *                   instead of creating a second Task.
 *              (A unique key on Task would be the natural database guarantee, but this org does
 *              not accept custom fields on Task.)
 *
 *              Sharing: declared "without sharing" on purpose. This is a system automation that
 *              runs whenever any user or integration saves an agreement: it must see Renewal Tasks
 *              owned by other users and stamp the system-managed marker even when the editing
 *              user cannot edit that field. User-facing reads and writes are enforced in user mode
 *              by UpcomingRenewalsService.
 *
 *              Governor limits per transaction: at most 2 SOQL queries and 2 DML statements,
 *              independent of the number of records.
 * @author      Enzo Fischer
 */
public without sharing class RenewalTaskService {
  public static final String SUBJECT_PREFIX = 'Renewal: ';
  @TestVisible
  private static final String TASK_STATUS = 'Not Started';
  @TestVisible
  private static final String TASK_PRIORITY = 'Normal';

  private final RenewalEligibility eligibility;
  private final ServiceAgreementSelector agreementSelector;
  private final RenewalTaskSelector taskSelector;

  /**
   * @description Creates the service for the current date and configured settings.
   */
  public RenewalTaskService() {
    this(
      RenewalEligibility.forToday(),
      new ServiceAgreementSelector(),
      new RenewalTaskSelector()
    );
  }

  /**
   * @description Creates the service with explicit collaborators (dependency injection).
   * @param eligibility       Renewal rules to apply.
   * @param agreementSelector Data access for agreements.
   * @param taskSelector      Data access for existing Renewal Tasks.
   */
  public RenewalTaskService(
    RenewalEligibility eligibility,
    ServiceAgreementSelector agreementSelector,
    RenewalTaskSelector taskSelector
  ) {
    this.eligibility = eligibility;
    this.agreementSelector = agreementSelector;
    this.taskSelector = taskSelector;
  }

  /**
   * @description Creates one Renewal Task for every agreement that requires attention and does
   *              not have one yet. Bulk-safe: works the same for 1 or 200 records.
   * @param agreements Agreements that were inserted or updated.
   * @return           Error message by agreement Id for agreements whose Task could not be
   *                   created or recorded. Empty when everything succeeded.
   */
  public Map<Id, String> createRenewalTasks(
    List<Service_Agreement__c> agreements
  ) {
    Map<Id, String> errorsByAgreementId = new Map<Id, String>();

    Set<Id> candidateIds = selectCandidateIds(agreements);
    if (candidateIds.isEmpty()) {
      // Cheap exit: no queries are spent when nothing qualifies, including the follow-up
      // trigger pass caused by stamping the marker.
      return errorsByAgreementId;
    }

    List<Service_Agreement__c> currentAgreements = agreementSelector.selectByIdForUpdate(
      candidateIds
    );
    Map<Id, Id> existingTaskIds = taskSelector.selectRenewalTaskIdsByAgreementId(
      candidateIds
    );

    List<Service_Agreement__c> markersToSave = new List<Service_Agreement__c>();
    List<Task> tasksToInsert = new List<Task>();
    List<Id> agreementIdByTaskIndex = new List<Id>();

    for (Service_Agreement__c agreement : currentAgreements) {
      if (
        String.isNotBlank(agreement.Renewal_Task_Id__c) ||
        !eligibility.requiresAttention(agreement)
      ) {
        continue;
      }
      if (existingTaskIds.containsKey(agreement.Id)) {
        // A Renewal Task already exists but the marker was lost: restore it, do not duplicate.
        markersToSave.add(
          buildMarker(agreement.Id, existingTaskIds.get(agreement.Id))
        );
        continue;
      }
      tasksToInsert.add(buildTask(agreement));
      agreementIdByTaskIndex.add(agreement.Id);
    }

    if (!tasksToInsert.isEmpty()) {
      List<Database.SaveResult> taskResults = Database.insert(
        tasksToInsert,
        false
      );
      for (Integer i = 0; i < taskResults.size(); i++) {
        Id agreementId = agreementIdByTaskIndex[i];
        if (taskResults[i].isSuccess()) {
          markersToSave.add(buildMarker(agreementId, taskResults[i].getId()));
        } else {
          errorsByAgreementId.put(
            agreementId,
            firstErrorMessage(taskResults[i])
          );
        }
      }
    }

    if (!markersToSave.isEmpty()) {
      List<Database.SaveResult> markerResults = Database.update(
        markersToSave,
        false
      );
      for (Integer i = 0; i < markerResults.size(); i++) {
        if (!markerResults[i].isSuccess()) {
          errorsByAgreementId.put(
            markersToSave[i].Id,
            firstErrorMessage(markerResults[i])
          );
        }
      }
    }

    return errorsByAgreementId;
  }

  /**
   * @description Chooses who receives the Renewal Task: the Account Manager when set and
   *              active; otherwise the agreement owner when it is an active user; otherwise the
   *              running user. Salesforce rejects Tasks assigned to inactive users, so this
   *              chain guarantees that a renewal is never dropped.
   * @param agreement Agreement read by ServiceAgreementSelector.selectByIdForUpdate.
   * @return          Id of the user who will own the Task.
   */
  @TestVisible
  private static Id resolveTaskOwnerId(Service_Agreement__c agreement) {
    if (
      agreement.Account_Manager__c != null &&
      agreement.Account_Manager__r?.IsActive == true
    ) {
      return agreement.Account_Manager__c;
    }
    if (
      agreement.OwnerId?.getSobjectType() == User.SObjectType &&
      agreement.Owner?.IsActive == true
    ) {
      return agreement.OwnerId;
    }
    return UserInfo.getUserId();
  }

  private Set<Id> selectCandidateIds(List<Service_Agreement__c> agreements) {
    Set<Id> candidateIds = new Set<Id>();
    for (Service_Agreement__c agreement : agreements) {
      if (
        agreement.Id != null &&
        String.isBlank(agreement.Renewal_Task_Id__c) &&
        eligibility.requiresAttention(agreement)
      ) {
        candidateIds.add(agreement.Id);
      }
    }
    return candidateIds;
  }

  private Task buildTask(Service_Agreement__c agreement) {
    return new Task(
      Subject = (SUBJECT_PREFIX + agreement.Name).left(255),
      WhatId = agreement.Id,
      OwnerId = resolveTaskOwnerId(agreement),
      ActivityDate = eligibility.taskDueDate(agreement.End_Date__c),
      Status = TASK_STATUS,
      Priority = TASK_PRIORITY,
      Description = 'Service Agreement "' +
        agreement.Name +
        '" ends on ' +
        agreement.End_Date__c.format() +
        '. Start the renewal conversation with the customer.'
    );
  }

  private static Service_Agreement__c buildMarker(Id agreementId, Id taskId) {
    return new Service_Agreement__c(
      Id = agreementId,
      Renewal_Task_Id__c = taskId
    );
  }

  private static String firstErrorMessage(Database.SaveResult result) {
    List<Database.Error> errors = result.getErrors();
    return errors.isEmpty() ? 'Unknown error.' : errors[0].getMessage();
  }
}
