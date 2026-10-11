/**
 * @description Integration tests for the Renewal Task automation, exercised through real DML so
 *              the trigger, handler, service, selectors and rules are tested together.
 *              "Today" is pinned with RenewalClock so results do not depend on the run date.
 * @author      Enzo Fischer
 */
@IsTest
private class ServiceAgreementTriggerTest {
  private static final Date TODAY = Date.newInstance(2027, 1, 10);

  @TestSetup
  static void setup() {
    RenewalTestDataFactory.createAccount('Acme Corporation');
  }

  private static Id accountId() {
    return [SELECT Id FROM Account WHERE Name = 'Acme Corporation' LIMIT 1].Id;
  }

  private static Service_Agreement__c reload(Id agreementId) {
    return [
      SELECT Id, Renewal_Task_Id__c
      FROM Service_Agreement__c
      WHERE Id = :agreementId
    ];
  }

  // ---------- Qualifying agreements ----------

  @IsTest
  static void createsRenewalTaskForQualifyingAgreement() {
    RenewalClock.setToday(TODAY);
    User accountManager = RenewalTestDataFactory.createUser(
      RenewalTestDataFactory.STANDARD_USER_PROFILE,
      true
    );
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    agreement.Account_Manager__c = accountManager.Id;

    Test.startTest();
    insert agreement;
    Test.stopTest();

    List<Task> tasks = RenewalTestDataFactory.getRenewalTasks(
      new Set<Id>{ agreement.Id }
    );
    Assert.areEqual(
      1,
      tasks.size(),
      'Exactly one Renewal Task should be created.'
    );
    Task renewalTask = tasks[0];
    Assert.areEqual(
      accountManager.Id,
      renewalTask.OwnerId,
      'The Task should be assigned to the Account Manager.'
    );
    Assert.areEqual(
      TODAY.addDays(10),
      renewalTask.ActivityDate,
      'The Task should be due 10 days before the End Date.'
    );
    Assert.areEqual(
      RenewalTaskService.SUBJECT_PREFIX + agreement.Name,
      renewalTask.Subject,
      'Unexpected subject.'
    );
    Assert.areEqual(
      RenewalTaskService.TASK_STATUS,
      renewalTask.Status,
      'Unexpected status.'
    );
    Assert.areEqual(
      RenewalTaskService.TASK_PRIORITY,
      renewalTask.Priority,
      'Unexpected priority.'
    );
    Assert.areEqual(
      renewalTask.Id,
      reload(agreement.Id).Renewal_Task_Id__c,
      'The agreement should store the Task Id.'
    );
  }

  @IsTest
  static void createsTaskWhenAgreementStartsQualifyingOnUpdate() {
    RenewalClock.setToday(TODAY);
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    agreement.Status__c = 'Draft';
    insert agreement;
    Assert.areEqual(
      0,
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })
        .size(),
      'Draft agreements should not get a Task.'
    );

    Test.startTest();
    agreement.Status__c = RenewalEligibility.STATUS_ACTIVE;
    update agreement;
    Test.stopTest();

    Assert.areEqual(
      1,
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })
        .size(),
      'Activating the agreement should create the Task.'
    );
  }

  // ---------- Non-qualifying agreements ----------

  @IsTest
  static void doesNotCreateTasksForNonQualifyingAgreements() {
    RenewalClock.setToday(TODAY);
    Id accountId = accountId();

    Service_Agreement__c draft = RenewalTestDataFactory.buildAgreement(
      accountId,
      TODAY.addDays(5)
    );
    draft.Status__c = 'Draft';
    Service_Agreement__c notRequired = RenewalTestDataFactory.buildAgreement(
      accountId,
      TODAY.addDays(5)
    );
    notRequired.Renewal_Required__c = false;
    Service_Agreement__c tooFar = RenewalTestDataFactory.buildAgreement(
      accountId,
      TODAY.addDays(31)
    );
    Service_Agreement__c ended = RenewalTestDataFactory.buildAgreement(
      accountId,
      TODAY.addDays(-1)
    );
    Service_Agreement__c cancelled = RenewalTestDataFactory.buildAgreement(
      accountId,
      TODAY.addDays(5)
    );
    cancelled.Status__c = 'Cancelled';
    List<Service_Agreement__c> agreements = new List<Service_Agreement__c>{
      draft,
      notRequired,
      tooFar,
      ended,
      cancelled
    };

    Test.startTest();
    insert agreements;
    Test.stopTest();

    Map<Id, Service_Agreement__c> saved = new Map<Id, Service_Agreement__c>(
      agreements
    );
    Assert.areEqual(
      0,
      RenewalTestDataFactory.getRenewalTasks(saved.keySet()).size(),
      'No agreement should get a Renewal Task.'
    );
    for (Service_Agreement__c agreement : [
      SELECT Renewal_Task_Id__c
      FROM Service_Agreement__c
      WHERE Id IN :saved.keySet()
    ]) {
      Assert.isNull(
        agreement.Renewal_Task_Id__c,
        'Non-qualifying agreements should have no marker.'
      );
    }
  }

  @IsTest
  static void rejectsEndDateBeforeStartDate() {
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    agreement.Start_Date__c = agreement.End_Date__c.addDays(1);

    Test.startTest();
    Database.SaveResult result = Database.insert(agreement, false);
    Test.stopTest();

    Assert.isFalse(
      result.isSuccess(),
      'The validation rule should reject an End Date before the Start Date.'
    );
  }

  // ---------- Duplicate prevention ----------

  @IsTest
  static void repeatedEditsDoNotCreateDuplicateTasks() {
    RenewalClock.setToday(TODAY);
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    insert agreement;

    Test.startTest();
    agreement.Agreement_Value__c = 20000;
    update agreement;
    agreement.Name = 'Renamed Agreement';
    update agreement;
    agreement.End_Date__c = TODAY.addDays(25);
    update agreement;
    Test.stopTest();

    Assert.areEqual(
      1,
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })
        .size(),
      'Edits must not create a second Task.'
    );
  }

  @IsTest
  static void restoresMarkerInsteadOfDuplicatingTask() {
    RenewalClock.setToday(TODAY);
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    insert agreement;
    Id originalTaskId = reload(agreement.Id).Renewal_Task_Id__c;

    Test.startTest();
    agreement.Renewal_Task_Id__c = null; // e.g. cleared by a data load
    update agreement;
    Test.stopTest();

    Assert.areEqual(
      1,
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })
        .size(),
      'No second Task should be created.'
    );
    Assert.areEqual(
      originalTaskId,
      reload(agreement.Id).Renewal_Task_Id__c,
      'The marker should point to the existing Task again.'
    );
  }

  // ---------- Bulk operations ----------

  @IsTest
  static void handlesBulkInsertAndUpdateWithinLimits() {
    RenewalClock.setToday(TODAY);
    Id accountId = accountId();
    List<Service_Agreement__c> agreements = RenewalTestDataFactory.buildAgreements(
      accountId,
      TODAY.addDays(15),
      200
    );
    List<Service_Agreement__c> outsideWindow = RenewalTestDataFactory.buildAgreements(
      accountId,
      TODAY.addDays(60),
      50
    );
    agreements.addAll(outsideWindow);

    Test.startTest();
    insert agreements;
    Integer queriesAfterInsert = Limits.getQueries();
    update agreements;
    Integer queriesAfterUpdate = Limits.getQueries();
    Test.stopTest();

    Map<Id, Service_Agreement__c> saved = new Map<Id, Service_Agreement__c>(
      agreements
    );
    Assert.areEqual(
      200,
      RenewalTestDataFactory.getRenewalTasks(saved.keySet()).size(),
      'One Task per qualifying agreement, even after a bulk update.'
    );
    Assert.isTrue(
      queriesAfterInsert <= 3,
      'Bulk insert should use a constant number of queries, used: ' +
      queriesAfterInsert
    );
    Assert.areEqual(
      queriesAfterInsert,
      queriesAfterUpdate,
      'Agreements that already have a Task should not cost extra queries.'
    );
  }

  // ---------- Task owner ----------

  @IsTest
  static void assignsTaskToOwnerWhenAccountManagerIsEmpty() {
    RenewalClock.setToday(TODAY);
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );

    Test.startTest();
    insert agreement;
    Test.stopTest();

    Task renewalTask = RenewalTestDataFactory.getRenewalTasks(
      new Set<Id>{ agreement.Id }
    )[0];
    Assert.areEqual(
      UserInfo.getUserId(),
      renewalTask.OwnerId,
      'Without an Account Manager the agreement owner should receive the Task.'
    );
  }

  @IsTest
  static void assignsTaskToOwnerWhenAccountManagerIsInactive() {
    RenewalClock.setToday(TODAY);
    User inactiveManager = RenewalTestDataFactory.createUser(
      RenewalTestDataFactory.STANDARD_USER_PROFILE,
      false
    );
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(20)
    );
    agreement.Account_Manager__c = inactiveManager.Id;

    Test.startTest();
    insert agreement;
    Test.stopTest();

    Task renewalTask = RenewalTestDataFactory.getRenewalTasks(
      new Set<Id>{ agreement.Id }
    )[0];
    Assert.areEqual(
      UserInfo.getUserId(),
      renewalTask.OwnerId,
      'An inactive Account Manager should fall back to the owner.'
    );
  }

  // ---------- Date boundaries through the trigger ----------

  @IsTest
  static void dueDateIsTodayWhenAgreementEndsWithinLeadTime() {
    RenewalClock.setToday(TODAY);
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      TODAY.addDays(3)
    );

    Test.startTest();
    insert agreement;
    Test.stopTest();

    Assert.areEqual(
      TODAY,
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })[0]
        .ActivityDate,
      'The Task must not be created overdue.'
    );
  }

  @IsTest
  static void dueDateAcrossYearBoundary() {
    RenewalClock.setToday(Date.newInstance(2026, 12, 20));
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      Date.newInstance(2027, 1, 5)
    );

    Test.startTest();
    insert agreement;
    Test.stopTest();

    Assert.areEqual(
      Date.newInstance(2026, 12, 26),
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })[0]
        .ActivityDate,
      'Unexpected due date across the year end.'
    );
  }

  @IsTest
  static void dueDateInLeapYear() {
    RenewalClock.setToday(Date.newInstance(2028, 2, 15));
    Service_Agreement__c agreement = RenewalTestDataFactory.buildAgreement(
      accountId(),
      Date.newInstance(2028, 3, 1)
    );

    Test.startTest();
    insert agreement;
    Test.stopTest();

    Assert.areEqual(
      Date.newInstance(2028, 2, 20),
      RenewalTestDataFactory.getRenewalTasks(new Set<Id>{ agreement.Id })[0]
        .ActivityDate,
      'Unexpected due date in a leap year.'
    );
  }
}
