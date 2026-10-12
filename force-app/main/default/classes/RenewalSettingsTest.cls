/**
 * @description Tests for RenewalSettings and RenewalClock: configured values, safe defaults and
 *              the pinned date used by every other test.
 * @author      Enzo Fischer
 */
@IsTest
private class RenewalSettingsTest {
  // Test method that checks the configured window and lead time are used.
  @IsTest
  static void usesConfiguredValues() {
    RenewalSettings.useOverride = true;
    RenewalSettings.settingOverride = new Renewal_Setting__mdt(
      Renewal_Window_Days__c = 45,
      Task_Lead_Days__c = 5
    );

    Assert.areEqual(
      45,
      RenewalSettings.windowDays(),
      'The configured window should be used.'
    );
    Assert.areEqual(
      5,
      RenewalSettings.taskLeadDays(),
      'The configured lead time should be used.'
    );
  }

  // Test method that checks the safe defaults are used when the record is missing.
  @IsTest
  static void fallsBackToDefaultsWhenRecordIsMissing() {
    RenewalSettings.useOverride = true;
    RenewalSettings.settingOverride = null;

    Assert.areEqual(
      RenewalSettings.DEFAULT_WINDOW_DAYS,
      RenewalSettings.windowDays(),
      'Missing configuration should use 30.'
    );
    Assert.areEqual(
      RenewalSettings.DEFAULT_TASK_LEAD_DAYS,
      RenewalSettings.taskLeadDays(),
      'Missing configuration should use 10.'
    );
  }

  // Test method that checks the safe defaults are used when values are blank or negative.
  @IsTest
  static void fallsBackToDefaultsWhenValuesAreInvalid() {
    RenewalSettings.useOverride = true;
    RenewalSettings.settingOverride = new Renewal_Setting__mdt(
      Renewal_Window_Days__c = -1,
      Task_Lead_Days__c = null
    );

    Assert.areEqual(
      RenewalSettings.DEFAULT_WINDOW_DAYS,
      RenewalSettings.windowDays(),
      'A negative window should use the default.'
    );
    Assert.areEqual(
      RenewalSettings.DEFAULT_TASK_LEAD_DAYS,
      RenewalSettings.taskLeadDays(),
      'A blank lead time should use the default.'
    );
  }

  // Test method that checks the deployed Default record is the one read at runtime.
  @IsTest
  static void readsTheDeployedDefaultRecord() {
    Renewal_Setting__mdt deployed = Renewal_Setting__mdt.getInstance(
      RenewalSettings.DEFAULT_RECORD_NAME
    );

    Assert.isNotNull(
      deployed,
      'The Default renewal setting record should be deployed.'
    );
    Assert.areEqual(
      deployed.Renewal_Window_Days__c.intValue(),
      RenewalSettings.windowDays(),
      'The deployed window should be used.'
    );
    Assert.areEqual(
      deployed.Task_Lead_Days__c.intValue(),
      RenewalSettings.taskLeadDays(),
      'The deployed lead time should be used.'
    );
  }

  // Test method that checks the rules for "today" combine the clock and the settings.
  @IsTest
  static void eligibilityForTodayUsesClockAndSettings() {
    Date pinned = Date.newInstance(2028, 2, 15);
    RenewalClock.setToday(pinned);
    RenewalSettings.useOverride = true;
    RenewalSettings.settingOverride = new Renewal_Setting__mdt(
      Renewal_Window_Days__c = 45,
      Task_Lead_Days__c = 5
    );

    RenewalEligibility rules = RenewalEligibility.forToday();

    Assert.areEqual(
      pinned,
      rules.windowStart(),
      'The window should start on the pinned date.'
    );
    Assert.areEqual(
      pinned.addDays(45),
      rules.windowEnd(),
      'The configured window should be applied.'
    );
  }

  // Test method that checks the clock returns the real date when nothing is pinned.
  @IsTest
  static void clockReturnsRealDateWhenNotPinned() {
    RenewalClock.setToday(null);
    Assert.areEqual(
      Date.today(),
      RenewalClock.today(),
      'Without a pinned date the clock should return today.'
    );
  }
}
