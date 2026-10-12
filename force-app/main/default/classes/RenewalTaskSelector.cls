/**
 * @description Data access for Renewal Tasks. Used as a secondary duplicate check: it finds
 *              Renewal Tasks that already exist for agreements whose Renewal_Task_Id__c marker
 *              is empty (for example, cleared by a data load).
 * @author      Enzo Fischer
 */
public inherited sharing class RenewalTaskSelector {
  /**
   * Method that finds the Renewal Tasks that already exist for the given agreements, matching
   * the agreement (WhatId) and the Renewal Task subject prefix.
   * @param agreementIds Agreements to check.
   * @return Map of agreement Id to the Id of its existing Renewal Task.
   */
  public Map<Id, Id> selectRenewalTaskIdsByAgreementId(Set<Id> agreementIds) {
    Map<Id, Id> taskIdByAgreementId = new Map<Id, Id>();
    String subjectPattern = RenewalTaskService.SUBJECT_PREFIX + '%';

    for (Task existingTask : [
      SELECT Id, WhatId
      FROM Task
      WHERE WhatId IN :agreementIds AND Subject LIKE :subjectPattern
      ORDER BY CreatedDate ASC
    ]) {
      // Keep the oldest Task when, for any reason, more than one exists.
      if (!taskIdByAgreementId.containsKey(existingTask.WhatId)) {
        taskIdByAgreementId.put(existingTask.WhatId, existingTask.Id);
      }
    }
    return taskIdByAgreementId;
  }
}
