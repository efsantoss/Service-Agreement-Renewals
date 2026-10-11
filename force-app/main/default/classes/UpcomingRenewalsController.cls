/**
 * @description The only Apex entry point of the Upcoming Renewals Lightning Web Component.
 *              Delegates to UpcomingRenewalsService and translates unexpected exceptions into
 *              user-friendly AuraHandledExceptions, logging the technical detail.
 * @author      Enzo Fischer
 */
public with sharing class UpcomingRenewalsController {
  @TestVisible
  private static final String LOAD_ERROR = 'Upcoming renewals could not be loaded. Please try again or contact your administrator.';
  @TestVisible
  private static final String START_ERROR = 'Renewal work could not be started. Please try again or contact your administrator.';

  /**
   * @description Agreements that require renewal attention, for display.
   *              Cacheable: the component refreshes it after starting renewal work.
   * @return      Upcoming renewals visible to the current user.
   */
  @AuraEnabled(cacheable=true)
  public static List<UpcomingRenewalDto> getUpcomingRenewals() {
    try {
      return new UpcomingRenewalsService().getUpcomingRenewals();
    } catch (Exception e) {
      throw buildAuraException(LOAD_ERROR, e);
    }
  }

  /**
   * @description Marks renewal work as started on the selected agreements.
   * @param agreementIds Agreements selected in the component.
   * @return             Number of updated agreements and any per-record errors.
   */
  @AuraEnabled
  public static UpcomingRenewalsService.StartRenewalResult startRenewalWork(
    List<Id> agreementIds
  ) {
    try {
      return new UpcomingRenewalsService().startRenewalWork(agreementIds);
    } catch (Exception e) {
      throw buildAuraException(START_ERROR, e);
    }
  }

  private static AuraHandledException buildAuraException(
    String message,
    Exception cause
  ) {
    System.debug(
      LoggingLevel.ERROR,
      message +
        ' Cause: ' +
        cause.getMessage() +
        '\n' +
        cause.getStackTraceString()
    );
    AuraHandledException auraException = new AuraHandledException(message);
    // setMessage keeps the friendly text available to Apex tests as well.
    auraException.setMessage(message);
    return auraException;
  }
}
