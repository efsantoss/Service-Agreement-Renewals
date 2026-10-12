/**
 * @description Exposes the configurable parameters of the renewal process.
 *              Values come from the Renewal_Setting__mdt record named "Default", so the business
 *              can change the look-ahead window or the Task lead time without a code deployment.
 *              Safe defaults (30 and 10 days) are used when the record is missing or a value is
 *              invalid, so a configuration mistake never breaks the feature.
 *              Custom Metadata reads do not count against the SOQL query limit.
 * @author      Enzo Fischer
 */
public with sharing class RenewalSettings {
  @TestVisible
  private static final String DEFAULT_RECORD_NAME = 'Default';
  @TestVisible
  private static final Integer DEFAULT_WINDOW_DAYS = 30;
  @TestVisible
  private static final Integer DEFAULT_TASK_LEAD_DAYS = 10;

  // Allows tests to simulate any configuration, including a missing record.
  @TestVisible
  private static Renewal_Setting__mdt settingOverride;
  @TestVisible
  private static Boolean useOverride = false;

  /**
   * Method that tells how many calendar days ahead, starting today, an End Date needs attention.
   * @return The configured window, or 30 when it is not configured.
   */
  public static Integer windowDays() {
    Renewal_Setting__mdt setting = getSetting();
    return valueOrDefault(setting?.Renewal_Window_Days__c, DEFAULT_WINDOW_DAYS);
  }

  /**
   * Method that tells how many calendar days before the End Date the Renewal Task is due.
   * @return The configured lead time, or 10 when it is not configured.
   */
  public static Integer taskLeadDays() {
    Renewal_Setting__mdt setting = getSetting();
    return valueOrDefault(setting?.Task_Lead_Days__c, DEFAULT_TASK_LEAD_DAYS);
  }

  // Method that returns the configuration in use: the test override when set, otherwise the
  // Default Custom Metadata record (null when it does not exist).
  private static Renewal_Setting__mdt getSetting() {
    if (useOverride) {
      return settingOverride;
    }
    return Renewal_Setting__mdt.getInstance(DEFAULT_RECORD_NAME);
  }

  // Method that falls back to the default value when the configured one is blank or negative.
  private static Integer valueOrDefault(Decimal value, Integer fallback) {
    return (value == null || value < 0) ? fallback : value.intValue();
  }
}
