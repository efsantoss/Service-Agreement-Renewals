/**
 * @description Builds test data for the renewal solution, so every test class creates records
 *              the same way and each test only states what is special about its scenario.
 * @author      Enzo Fischer
 */
@IsTest
public class RenewalTestDataFactory {
  public static final String PERMISSION_SET_NAME = 'Upcoming_Renewals_User';
  public static final String STANDARD_USER_PROFILE = 'Standard User';

  private static Integer userCounter = 0;

  /**
   * @description Inserts an Account.
   * @param name Account name.
   * @return     The inserted Account.
   */
  public static Account createAccount(String name) {
    Account account = new Account(Name = name);
    insert account;
    return account;
  }

  /**
   * @description Builds (does not insert) an agreement that qualifies for renewal attention
   *              when its End Date is inside the window: Active and Renewal Required.
   * @param accountId Parent Account.
   * @param endDate   Agreement End Date.
   * @return          The agreement, not inserted.
   */
  public static Service_Agreement__c buildAgreement(
    Id accountId,
    Date endDate
  ) {
    return new Service_Agreement__c(
      Name = 'Agreement ending ' + String.valueOf(endDate),
      Account__c = accountId,
      Start_Date__c = endDate.addYears(-1),
      End_Date__c = endDate,
      Status__c = RenewalEligibility.STATUS_ACTIVE,
      Agreement_Value__c = 10000,
      Renewal_Required__c = true,
      Renewal_Work_Status__c = 'Not Started'
    );
  }

  /**
   * @description Builds (does not insert) several qualifying agreements with the same End Date.
   * @param accountId Parent Account.
   * @param endDate   Agreement End Date.
   * @param count     Number of agreements.
   * @return          The agreements, not inserted.
   */
  public static List<Service_Agreement__c> buildAgreements(
    Id accountId,
    Date endDate,
    Integer count
  ) {
    List<Service_Agreement__c> agreements = new List<Service_Agreement__c>();
    for (Integer i = 0; i < count; i++) {
      Service_Agreement__c agreement = buildAgreement(accountId, endDate);
      agreement.Name = 'Bulk Agreement ' + i;
      agreements.add(agreement);
    }
    return agreements;
  }

  /**
   * @description Inserts a user. Runs as the current user to avoid mixed DML errors between
   *              setup objects (User) and regular records in the same test.
   * @param profileName Profile name.
   * @param isActive    Whether the user is active.
   * @return            The inserted user.
   */
  public static User createUser(String profileName, Boolean isActive) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];
    userCounter++;
    String uniqueKey = String.valueOf(System.currentTimeMillis()) + userCounter;
    User user = new User(
      FirstName = 'Renewal',
      LastName = 'Tester ' + userCounter,
      Alias = 'rtest' + userCounter,
      Email = 'renewal.tester' + uniqueKey + '@example.com',
      Username = 'renewal.tester' + uniqueKey + '@renewals.test',
      ProfileId = profile.Id,
      IsActive = isActive,
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert user;
    }
    return user;
  }

  /**
   * @description Assigns the Upcoming Renewals permission set to a user.
   * @param userId User to receive the permission set.
   */
  public static void assignPermissionSet(Id userId) {
    PermissionSet permissionSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :PERMISSION_SET_NAME
      LIMIT 1
    ];
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert new PermissionSetAssignment(
        AssigneeId = userId,
        PermissionSetId = permissionSet.Id
      );
    }
  }

  /**
   * @description Reads the Renewal Tasks related to the given agreements.
   * @param agreementIds Agreements to look up.
   * @return             Renewal Tasks, oldest first.
   */
  public static List<Task> getRenewalTasks(Set<Id> agreementIds) {
    return [
      SELECT Id, WhatId, OwnerId, Subject, ActivityDate, Status, Priority
      FROM Task
      WHERE WhatId IN :agreementIds
      ORDER BY CreatedDate ASC
    ];
  }
}
