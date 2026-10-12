/**
 * @description Domain rules of the renewal process. Pure logic: no SOQL, no DML and no static
 *              state. All inputs (today, window and lead time) are received through the
 *              constructor, which makes every rule unit-testable with fixed dates.
 *
 *              All calculations use the Date type and Date.addDays()/daysBetween(), which are
 *              calendar-aware. Month ends, year ends and leap years are therefore handled by the
 *              platform, and no Datetime is involved, so time zones cannot shift a day.
 * @author      Enzo Fischer
 */
public with sharing class RenewalEligibility {
  public static final String STATUS_ACTIVE = 'Active';

  private final Date today;
  private final Integer windowDays;
  private final Integer taskLeadDays;

  /**
   * Constructor that builds the rules for an explicit reference date and configuration.
   * @param today        The reference date ("today").
   * @param windowDays   Look-ahead window in calendar days.
   * @param taskLeadDays Days before the End Date on which the Renewal Task is due.
   */
  public RenewalEligibility(
    Date today,
    Integer windowDays,
    Integer taskLeadDays
  ) {
    this.today = today;
    this.windowDays = windowDays;
    this.taskLeadDays = taskLeadDays;
  }

  /**
   * Method that builds the rules for the current date and the configured settings.
   * @return A RenewalEligibility based on RenewalClock and RenewalSettings.
   */
  public static RenewalEligibility forToday() {
    return new RenewalEligibility(
      RenewalClock.today(),
      RenewalSettings.windowDays(),
      RenewalSettings.taskLeadDays()
    );
  }

  /**
   * Method that decides if an agreement needs renewal attention: it must be Active, have
   * Renewal Required checked and end within the look-ahead window.
   * @param agreement The agreement to evaluate.
   * @return True when the agreement requires renewal attention.
   */
  public Boolean requiresAttention(Service_Agreement__c agreement) {
    return agreement != null &&
      agreement.Status__c == STATUS_ACTIVE &&
      agreement.Renewal_Required__c == true &&
      isWithinWindow(agreement.End_Date__c);
  }

  /**
   * Method that checks if an End Date falls inside the window, from today through
   * today + windowDays, both days included. Agreements that already ended are outside.
   * @param endDate The agreement End Date.
   * @return True when the End Date is inside the window.
   */
  public Boolean isWithinWindow(Date endDate) {
    return endDate != null &&
      endDate >= windowStart() &&
      endDate <= windowEnd();
  }

  /**
   * Method that returns the first day of the look-ahead window, which is today.
   * @return The window start date.
   */
  public Date windowStart() {
    return today;
  }

  /**
   * Method that returns the last day of the look-ahead window (today + windowDays).
   * @return The window end date.
   */
  public Date windowEnd() {
    return today.addDays(windowDays);
  }

  /**
   * Method that calculates when the Renewal Task is due: taskLeadDays calendar days before the
   * End Date, or today when that date has already passed, so a Task is never born overdue.
   * @param endDate The agreement End Date.
   * @return The Task due date.
   */
  public Date taskDueDate(Date endDate) {
    Date dueDate = endDate.addDays(-taskLeadDays);
    return dueDate < today ? today : dueDate;
  }

  /**
   * Method that counts the calendar days from today until the End Date (0 when it ends today).
   * @param endDate The agreement End Date.
   * @return Days remaining, negative when the agreement has already ended.
   */
  public Integer daysRemaining(Date endDate) {
    return today.daysBetween(endDate);
  }
}
