/**
 * @description Data access for Service_Agreement__c. All SOQL for the object lives here.
 *              Declared "inherited sharing" so record visibility follows the caller, while each
 *              method states its access mode explicitly:
 *                - UI reads run in USER_MODE (object, field and record access enforced).
 *                - The renewal Task automation reads in system context (see RenewalTaskService).
 * @author      Enzo Fischer
 */
public inherited sharing class ServiceAgreementSelector {
  /**
   * @description Agreements that require renewal attention, for display to the current user.
   *              Ordered by the soonest End Date, then by the highest value.
   * @param windowStart First End Date included (today).
   * @param windowEnd   Last End Date included (today + window).
   * @param maxRows     Maximum number of rows to return.
   * @return            Qualifying agreements visible to the current user.
   */
  public List<Service_Agreement__c> selectRequiringAttention(
    Date windowStart,
    Date windowEnd,
    Integer maxRows
  ) {
    return [
      SELECT
        Id,
        Name,
        End_Date__c,
        Agreement_Value__c,
        Renewal_Work_Status__c,
        Renewal_Task_Id__c,
        Account__c,
        Account__r.Name,
        Account_Manager__c,
        Account_Manager__r.Name
      FROM Service_Agreement__c
      WHERE
        Status__c = :RenewalEligibility.STATUS_ACTIVE
        AND Renewal_Required__c = TRUE
        AND End_Date__c >= :windowStart
        AND End_Date__c <= :windowEnd
      WITH USER_MODE
      ORDER BY End_Date__c ASC, Agreement_Value__c DESC NULLS LAST, Name ASC
      LIMIT :maxRows
    ];
  }

  /**
   * @description Fresh read of agreements for the renewal Task automation, locking the rows
   *              (FOR UPDATE) so two transactions cannot decide on the same agreement at the
   *              same time. Values in Trigger.new may be stale, so decisions use this read.
   *              Note: SOQL with FOR UPDATE cannot use ORDER BY.
   * @param agreementIds Agreements to read.
   * @return             Current state of the agreements, including owner and Account Manager.
   */
  public List<Service_Agreement__c> selectByIdForUpdate(Set<Id> agreementIds) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        Renewal_Required__c,
        End_Date__c,
        Renewal_Task_Id__c,
        OwnerId,
        Owner.IsActive,
        Account_Manager__c,
        Account_Manager__r.IsActive
      FROM Service_Agreement__c
      WHERE Id IN :agreementIds
      FOR UPDATE
    ];
  }
}
