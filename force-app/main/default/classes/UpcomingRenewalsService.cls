/**
 * @description Use cases behind the Upcoming Renewals component:
 *                - list the agreements that require renewal attention (Requirement 1);
 *                - mark renewal work as started on selected agreements (Requirement 3).
 *              Runs "with sharing" and in USER_MODE, so the current user's object, field and
 *              record access is always enforced.
 * @author      Enzo Fischer
 */
public with sharing class UpcomingRenewalsService {
  public static final String WORK_STATUS_IN_PROGRESS = 'In Progress';
  @TestVisible
  private static final Integer MAX_ROWS = 500;

  private final RenewalEligibility eligibility;
  private final ServiceAgreementSelector agreementSelector;

  /**
   * @description Creates the service for the current date and configured settings.
   */
  public UpcomingRenewalsService() {
    this(RenewalEligibility.forToday(), new ServiceAgreementSelector());
  }

  /**
   * @description Creates the service with explicit collaborators (dependency injection).
   * @param eligibility       Renewal rules to apply.
   * @param agreementSelector Data access for agreements.
   */
  public UpcomingRenewalsService(
    RenewalEligibility eligibility,
    ServiceAgreementSelector agreementSelector
  ) {
    this.eligibility = eligibility;
    this.agreementSelector = agreementSelector;
  }

  /**
   * @description Returns the agreements that require renewal attention, soonest first.
   * @return      Read models ready for display, including days remaining.
   */
  public List<UpcomingRenewalDto> getUpcomingRenewals() {
    List<UpcomingRenewalDto> renewals = new List<UpcomingRenewalDto>();
    for (
      Service_Agreement__c agreement : agreementSelector.selectRequiringAttention(
        eligibility.windowStart(),
        eligibility.windowEnd(),
        MAX_ROWS
      )
    ) {
      renewals.add(
        new UpcomingRenewalDto(
          agreement,
          eligibility.daysRemaining(agreement.End_Date__c)
        )
      );
    }
    return renewals;
  }

  /**
   * @description Sets Renewal Work Status to In Progress on the selected agreements.
   *              Partial success: valid records are saved even if others fail.
   *              Saving the agreement also re-runs the trigger, which creates the Renewal Task
   *              if the agreement does not have one yet.
   * @param agreementIds Agreements selected by the user.
   * @return             How many agreements were updated and the errors of the others.
   */
  public StartRenewalResult startRenewalWork(List<Id> agreementIds) {
    StartRenewalResult result = new StartRenewalResult();
    if (agreementIds == null || agreementIds.isEmpty()) {
      return result;
    }

    List<Service_Agreement__c> updates = new List<Service_Agreement__c>();
    for (Id agreementId : new Set<Id>(agreementIds)) {
      if (agreementId?.getSobjectType() != Service_Agreement__c.SObjectType) {
        result.errors.add(
          'Ignored an Id that is not a Service Agreement: ' + agreementId
        );
        continue;
      }
      updates.add(
        new Service_Agreement__c(
          Id = agreementId,
          Renewal_Work_Status__c = WORK_STATUS_IN_PROGRESS
        )
      );
    }

    List<Database.SaveResult> saveResults = Database.update(
      updates,
      false,
      AccessLevel.USER_MODE
    );
    for (Integer i = 0; i < saveResults.size(); i++) {
      if (saveResults[i].isSuccess()) {
        result.successCount++;
      } else {
        result.errors.add(
          updates[i].Id + ': ' + saveResults[i].getErrors()[0].getMessage()
        );
      }
    }
    return result;
  }

  /**
   * @description Outcome of startRenewalWork, returned to the component.
   */
  public class StartRenewalResult {
    @AuraEnabled
    public Integer successCount = 0;
    @AuraEnabled
    public List<String> errors = new List<String>();
  }
}
