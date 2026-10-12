/**
 * @description Read model of one upcoming renewal, shaped for the Upcoming Renewals component.
 *              Exposes only the fields the UI displays, so raw records never reach the browser.
 * @author      Enzo Fischer
 */
public with sharing class UpcomingRenewalDto {
  @AuraEnabled
  public Id id;
  @AuraEnabled
  public String agreementName;
  @AuraEnabled
  public Id accountId;
  @AuraEnabled
  public String accountName;
  @AuraEnabled
  public Date endDate;
  @AuraEnabled
  public Integer daysRemaining;
  @AuraEnabled
  public Decimal agreementValue;
  @AuraEnabled
  public Id accountManagerId;
  @AuraEnabled
  public String accountManagerName;
  @AuraEnabled
  public String renewalWorkStatus;
  @AuraEnabled
  public Boolean hasRenewalTask;

  /**
   * Constructor that copies the displayed fields of an agreement into the read model.
   * @param agreement     Agreement read by ServiceAgreementSelector.selectRequiringAttention.
   * @param daysRemaining Calendar days until the End Date.
   */
  public UpcomingRenewalDto(
    Service_Agreement__c agreement,
    Integer daysRemaining
  ) {
    this.id = agreement.Id;
    this.agreementName = agreement.Name;
    this.accountId = agreement.Account__c;
    this.accountName = agreement.Account__r?.Name;
    this.endDate = agreement.End_Date__c;
    this.daysRemaining = daysRemaining;
    this.agreementValue = agreement.Agreement_Value__c;
    this.accountManagerId = agreement.Account_Manager__c;
    this.accountManagerName = agreement.Account_Manager__r?.Name;
    this.renewalWorkStatus = agreement.Renewal_Work_Status__c;
    this.hasRenewalTask = String.isNotBlank(agreement.Renewal_Task_Id__c);
  }
}
