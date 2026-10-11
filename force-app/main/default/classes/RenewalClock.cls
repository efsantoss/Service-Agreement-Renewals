/**
 * @description Single source of "today" for the renewal process.
 *              Every date calculation reads the current date from here instead of calling
 *              Date.today() directly, so tests can pin the date and exercise month, year and
 *              leap-year boundaries deterministically, regardless of the day they run.
 *              Date.today() uses the running user's time zone, which is the expected behavior.
 * @author      Enzo Fischer
 */
public with sharing class RenewalClock {
  private static Date fixedToday;

  /**
   * @description Returns the current date, or the date pinned by a test.
   * @return      Today's date in the running user's time zone.
   */
  public static Date today() {
    return fixedToday != null ? fixedToday : Date.today();
  }

  /**
   * @description Pins "today" to a fixed date. Test use only.
   * @param value The date to return from today(); null restores the real date.
   */
  @TestVisible
  private static void setToday(Date value) {
    fixedToday = value;
  }
}
