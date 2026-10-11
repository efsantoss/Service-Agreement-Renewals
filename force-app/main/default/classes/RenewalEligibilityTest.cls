/**
 * @description Unit tests for the pure renewal rules: qualification criteria, window edges and
 *              calendar-date boundaries (month, year, leap year). No DML is needed because
 *              RenewalEligibility receives "today" and its settings through the constructor.
 * @author      Enzo Fischer
 */
@IsTest
private class RenewalEligibilityTest {
  private static final Date TODAY = Date.newInstance(2027, 1, 10);
  private static final RenewalEligibility RULES = new RenewalEligibility(
    TODAY,
    30,
    10
  );

  private static Service_Agreement__c agreementEnding(Date endDate) {
    return new Service_Agreement__c(
      Status__c = RenewalEligibility.STATUS_ACTIVE,
      Renewal_Required__c = true,
      End_Date__c = endDate
    );
  }

  // ---------- Qualifying agreements ----------

  @IsTest
  static void qualifiesWhenActiveRequiredAndInsideWindow() {
    Assert.isTrue(
      RULES.requiresAttention(agreementEnding(TODAY.addDays(15))),
      'Mid-window agreement should qualify.'
    );
  }

  @IsTest
  static void qualifiesOnFirstDayOfWindow() {
    Assert.isTrue(
      RULES.requiresAttention(agreementEnding(TODAY)),
      'An agreement ending today should qualify.'
    );
  }

  @IsTest
  static void qualifiesOnLastDayOfWindow() {
    Assert.isTrue(
      RULES.requiresAttention(agreementEnding(TODAY.addDays(30))),
      'Day 30 should be inside the window.'
    );
  }

  // ---------- Non-qualifying agreements ----------

  @IsTest
  static void doesNotQualifyOneDayAfterWindow() {
    Assert.isFalse(
      RULES.requiresAttention(agreementEnding(TODAY.addDays(31))),
      'Day 31 should be outside the window.'
    );
  }

  @IsTest
  static void doesNotQualifyWhenAlreadyEnded() {
    Assert.isFalse(
      RULES.requiresAttention(agreementEnding(TODAY.addDays(-1))),
      'Ended agreements should not qualify.'
    );
  }

  @IsTest
  static void doesNotQualifyWhenStatusIsNotActive() {
    for (String status : new List<String>{ 'Draft', 'Expired', 'Cancelled' }) {
      Service_Agreement__c agreement = agreementEnding(TODAY.addDays(5));
      agreement.Status__c = status;
      Assert.isFalse(
        RULES.requiresAttention(agreement),
        status + ' agreements should not qualify.'
      );
    }
  }

  @IsTest
  static void doesNotQualifyWhenRenewalIsNotRequired() {
    Service_Agreement__c agreement = agreementEnding(TODAY.addDays(5));
    agreement.Renewal_Required__c = false;
    Assert.isFalse(
      RULES.requiresAttention(agreement),
      'Agreements without Renewal Required should not qualify.'
    );
  }

  @IsTest
  static void doesNotQualifyWithoutEndDateOrRecord() {
    Assert.isFalse(
      RULES.requiresAttention(agreementEnding(null)),
      'A null End Date should not qualify.'
    );
    Assert.isFalse(
      RULES.requiresAttention(null),
      'A null agreement should not qualify.'
    );
  }

  // ---------- Task due date and date boundaries ----------

  @IsTest
  static void dueDateIsTenCalendarDaysBeforeEndDate() {
    Assert.areEqual(
      Date.newInstance(2027, 1, 30),
      RULES.taskDueDate(Date.newInstance(2027, 2, 9)),
      'Due date should be End Date - 10.'
    );
  }

  @IsTest
  static void dueDateCrossesMonthBoundary() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2027, 2, 10),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2027, 2, 23),
      rules.taskDueDate(Date.newInstance(2027, 3, 5)),
      'Mar 5 - 10 days should be Feb 23 (28-day February).'
    );
  }

  @IsTest
  static void dueDateCrossesYearBoundary() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2026, 12, 20),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2026, 12, 26),
      rules.taskDueDate(Date.newInstance(2027, 1, 5)),
      'Jan 5 - 10 days should be Dec 26 of the previous year.'
    );
  }

  @IsTest
  static void dueDateHandlesLeapYear() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2028, 2, 1),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2028, 2, 20),
      rules.taskDueDate(Date.newInstance(2028, 3, 1)),
      'Mar 1, 2028 - 10 days should be Feb 20 (29-day February).'
    );
  }

  @IsTest
  static void dueDateHandlesNonLeapYear() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2027, 2, 1),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2027, 2, 19),
      rules.taskDueDate(Date.newInstance(2027, 3, 1)),
      'Mar 1, 2027 - 10 days should be Feb 19 (28-day February).'
    );
  }

  @IsTest
  static void dueDateNeverInThePast() {
    Assert.areEqual(
      TODAY,
      RULES.taskDueDate(TODAY.addDays(4)),
      'When End Date - 10 is in the past, the Task is due today.'
    );
  }

  @IsTest
  static void windowSpansYearEnd() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2026, 12, 20),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2027, 1, 19),
      rules.windowEnd(),
      'Window should continue into the next year.'
    );
    Assert.isTrue(
      rules.isWithinWindow(Date.newInstance(2027, 1, 19)),
      'Last day across the year end should qualify.'
    );
    Assert.isFalse(
      rules.isWithinWindow(Date.newInstance(2027, 1, 20)),
      'Day 31 across the year end should not qualify.'
    );
  }

  @IsTest
  static void windowIncludesLeapDay() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2028, 2, 15),
      30,
      10
    );
    Assert.areEqual(
      Date.newInstance(2028, 3, 16),
      rules.windowEnd(),
      'Feb 15 + 30 days should be Mar 16 in a leap year.'
    );
    Assert.isTrue(
      rules.isWithinWindow(Date.newInstance(2028, 2, 29)),
      'Feb 29 should be a valid End Date inside the window.'
    );
  }

  @IsTest
  static void daysRemainingCountsCalendarDays() {
    RenewalEligibility rules = new RenewalEligibility(
      Date.newInstance(2028, 2, 28),
      30,
      10
    );
    Assert.areEqual(
      2,
      rules.daysRemaining(Date.newInstance(2028, 3, 1)),
      'Feb 28 to Mar 1, 2028 is 2 days (leap day included).'
    );
    Assert.areEqual(
      0,
      rules.daysRemaining(Date.newInstance(2028, 2, 28)),
      'Ending today means 0 days remaining.'
    );
  }

  // ---------- Configuration ----------

  @IsTest
  static void honorsConfiguredWindowAndLeadDays() {
    RenewalEligibility rules = new RenewalEligibility(TODAY, 45, 5);
    Assert.isTrue(
      rules.isWithinWindow(TODAY.addDays(45)),
      'A 45-day window should include day 45.'
    );
    Assert.areEqual(
      TODAY.addDays(15),
      rules.taskDueDate(TODAY.addDays(20)),
      'A 5-day lead should be applied.'
    );
  }
}
