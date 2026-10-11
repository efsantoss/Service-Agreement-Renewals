/**
 * @description Tests for the Upcoming Renewals entry point: what the list returns, how renewal
 *              work is started, and that security is enforced for users with and without the
 *              Upcoming Renewals User permission set.
 * @author      Enzo Fischer
 */
@IsTest
private class UpcomingRenewalsControllerTest {
  private static final Date TODAY = Date.newInstance(2027, 1, 10);

  @TestSetup
  static void setup() {
    RenewalClock.setToday(TODAY);
    Account account = RenewalTestDataFactory.createAccount('Globex');

    Service_Agreement__c soonest = RenewalTestDataFactory.buildAgreement(
      account.Id,
      TODAY.addDays(5)
    );
    soonest.Name = 'Soonest';
    Service_Agreement__c sameDayHigherValue = RenewalTestDataFactory.buildAgreement(
      account.Id,
      TODAY.addDays(20)
    );
    sameDayHigherValue.Name = 'Same Day Higher Value';
    sameDayHigherValue.Agreement_Value__c = 90000;
    Service_Agreement__c sameDayLowerValue = RenewalTestDataFactory.buildAgreement(
      account.Id,
      TODAY.addDays(20)
    );
    sameDayLowerValue.Name = 'Same Day Lower Value';
    sameDayLowerValue.Agreement_Value__c = 1000;
    Service_Agreement__c outsideWindow = RenewalTestDataFactory.buildAgreement(
      account.Id,
      TODAY.addDays(45)
    );
    outsideWindow.Name = 'Outside Window';
    Service_Agreement__c draft = RenewalTestDataFactory.buildAgreement(
      account.Id,
      TODAY.addDays(10)
    );
    draft.Name = 'Draft';
    draft.Status__c = 'Draft';

    insert new List<Service_Agreement__c>{
      soonest,
      sameDayHigherValue,
      sameDayLowerValue,
      outsideWindow,
      draft
    };
  }

  // ---------- Listing ----------

  @IsTest
  static void returnsOnlyQualifyingAgreementsInPriorityOrder() {
    RenewalClock.setToday(TODAY);

    Test.startTest();
    List<UpcomingRenewalDto> renewals = UpcomingRenewalsController.getUpcomingRenewals();
    Test.stopTest();

    Assert.areEqual(
      3,
      renewals.size(),
      'Only Active, Renewal Required agreements inside the window should be returned.'
    );
    Assert.areEqual(
      'Soonest',
      renewals[0].agreementName,
      'The soonest End Date should come first.'
    );
    Assert.areEqual(
      'Same Day Higher Value',
      renewals[1].agreementName,
      'Higher value should come first on the same date.'
    );
    Assert.areEqual(
      'Same Day Lower Value',
      renewals[2].agreementName,
      'Lower value should come last on the same date.'
    );
  }

  @IsTest
  static void mapsDisplayFields() {
    RenewalClock.setToday(TODAY);

    Test.startTest();
    UpcomingRenewalDto renewal = UpcomingRenewalsController.getUpcomingRenewals()[0];
    Test.stopTest();

    Assert.areEqual(
      5,
      renewal.daysRemaining,
      'Days remaining should be calendar days until the End Date.'
    );
    Assert.areEqual(TODAY.addDays(5), renewal.endDate, 'Unexpected End Date.');
    Assert.areEqual('Globex', renewal.accountName, 'Unexpected account name.');
    Assert.areEqual(
      10000,
      renewal.agreementValue,
      'Unexpected agreement value.'
    );
    Assert.areEqual(
      'Not Started',
      renewal.renewalWorkStatus,
      'Unexpected renewal work status.'
    );
    Assert.isTrue(
      renewal.hasRenewalTask,
      'The trigger should already have created the Renewal Task.'
    );
  }

  // ---------- Starting renewal work ----------

  @IsTest
  static void startsRenewalWorkOnSelectedAgreements() {
    RenewalClock.setToday(TODAY);
    List<Id> selectedIds = new List<Id>();
    for (
      UpcomingRenewalDto renewal : UpcomingRenewalsController.getUpcomingRenewals()
    ) {
      selectedIds.add(renewal.id);
    }

    Test.startTest();
    UpcomingRenewalsService.StartRenewalResult result = UpcomingRenewalsController.startRenewalWork(
      selectedIds
    );
    Test.stopTest();

    Assert.areEqual(
      3,
      result.successCount,
      'All selected agreements should be updated.'
    );
    Assert.isTrue(
      result.errors.isEmpty(),
      'No errors were expected: ' + result.errors
    );
    for (Service_Agreement__c agreement : [
      SELECT Renewal_Work_Status__c
      FROM Service_Agreement__c
      WHERE Id IN :selectedIds
    ]) {
      Assert.areEqual(
        UpcomingRenewalsService.WORK_STATUS_IN_PROGRESS,
        agreement.Renewal_Work_Status__c,
        'Status should be In Progress.'
      );
    }
  }

  @IsTest
  static void ignoresEmptySelectionAndForeignIds() {
    Test.startTest();
    UpcomingRenewalsService.StartRenewalResult emptyResult = UpcomingRenewalsController.startRenewalWork(
      new List<Id>()
    );
    UpcomingRenewalsService.StartRenewalResult foreignResult = UpcomingRenewalsController.startRenewalWork(
      new List<Id>{ UserInfo.getUserId() }
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      emptyResult.successCount,
      'An empty selection should update nothing.'
    );
    Assert.areEqual(
      0,
      foreignResult.successCount,
      'Ids of other objects should be ignored.'
    );
    Assert.areEqual(
      1,
      foreignResult.errors.size(),
      'Ignoring a foreign Id should be reported.'
    );
  }

  // ---------- Security ----------

  @IsTest
  static void userWithPermissionSetCanReviewAndStartRenewals() {
    RenewalClock.setToday(TODAY);
    User renewalUser = RenewalTestDataFactory.createUser(
      RenewalTestDataFactory.STANDARD_USER_PROFILE,
      true
    );
    RenewalTestDataFactory.assignPermissionSet(renewalUser.Id);

    List<UpcomingRenewalDto> renewals;
    UpcomingRenewalsService.StartRenewalResult result;
    Test.startTest();
    System.runAs(renewalUser) {
      renewals = UpcomingRenewalsController.getUpcomingRenewals();
      result = UpcomingRenewalsController.startRenewalWork(
        new List<Id>{ renewals[0].id }
      );
    }
    Test.stopTest();

    Assert.areEqual(
      3,
      renewals.size(),
      'A permitted user should see the upcoming renewals.'
    );
    Assert.areEqual(
      1,
      result.successCount,
      'A permitted user should be able to start renewal work.'
    );
  }

  @IsTest
  static void userWithoutPermissionSetGetsFriendlyError() {
    RenewalClock.setToday(TODAY);
    User restrictedUser = RenewalTestDataFactory.createUser(
      RenewalTestDataFactory.STANDARD_USER_PROFILE,
      true
    );

    String errorMessage;
    Test.startTest();
    System.runAs(restrictedUser) {
      try {
        UpcomingRenewalsController.getUpcomingRenewals();
      } catch (AuraHandledException e) {
        errorMessage = e.getMessage();
      }
    }
    Test.stopTest();

    Assert.areEqual(
      UpcomingRenewalsController.LOAD_ERROR,
      errorMessage,
      'Users without access should get a friendly error, not data.'
    );
  }

  @IsTest
  static void userWithoutPermissionSetCannotStartRenewalWork() {
    RenewalClock.setToday(TODAY);
    Id agreementId = [
      SELECT Id
      FROM Service_Agreement__c
      WHERE Name = 'Soonest'
      LIMIT 1
    ]
    .Id;
    User restrictedUser = RenewalTestDataFactory.createUser(
      RenewalTestDataFactory.STANDARD_USER_PROFILE,
      true
    );

    Boolean blocked = false;
    Test.startTest();
    System.runAs(restrictedUser) {
      // The platform may report the missing access per record or as an exception;
      // either way the user must be told and the record must not change.
      try {
        UpcomingRenewalsService.StartRenewalResult result = UpcomingRenewalsController.startRenewalWork(
          new List<Id>{ agreementId }
        );
        blocked = result.successCount == 0 && result.errors.size() == 1;
      } catch (AuraHandledException e) {
        blocked = e.getMessage() == UpcomingRenewalsController.START_ERROR;
      }
    }
    Test.stopTest();

    Assert.isTrue(
      blocked,
      'Users without edit access must be blocked with a clear error.'
    );
    Assert.areEqual(
      'Not Started',
      [
        SELECT Renewal_Work_Status__c
        FROM Service_Agreement__c
        WHERE Id = :agreementId
      ]
      .Renewal_Work_Status__c,
      'The agreement must remain unchanged.'
    );
  }
}
