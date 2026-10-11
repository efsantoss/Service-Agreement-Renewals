/**
 * Upcoming Renewals
 *
 * Lists the Service Agreements that require renewal attention and lets the user mark
 * renewal work as started on the selected rows.
 *
 * Data flow:
 *  - getUpcomingRenewals (cacheable) is wired, so Lightning Data Service caches the result.
 *  - startRenewalWork is called imperatively; afterwards the wired result is refreshed
 *    with refreshApex so the list always reflects the server state.
 */
import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getUpcomingRenewals from "@salesforce/apex/UpcomingRenewalsController.getUpcomingRenewals";
import startRenewalWork from "@salesforce/apex/UpcomingRenewalsController.startRenewalWork";

// Agreements ending within this many days are highlighted as urgent.
const URGENT_DAYS = 10;
const IN_PROGRESS = "In Progress";

const COLUMNS = [
  {
    label: "Account",
    fieldName: "accountUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "accountName" }, target: "_self" },
    sortable: false
  },
  {
    label: "Agreement",
    fieldName: "agreementUrl",
    type: "url",
    typeAttributes: { label: { fieldName: "agreementName" }, target: "_self" }
  },
  {
    // date-local renders a Date without time-zone conversion, so the day never shifts.
    label: "End Date",
    fieldName: "endDate",
    type: "date-local",
    typeAttributes: { year: "numeric", month: "short", day: "2-digit" }
  },
  {
    label: "Days Remaining",
    fieldName: "daysRemaining",
    type: "number",
    cellAttributes: {
      class: { fieldName: "daysRemainingClass" },
      alignment: "left"
    }
  },
  {
    label: "Agreement Value",
    fieldName: "agreementValue",
    type: "currency",
    cellAttributes: { alignment: "left" }
  },
  { label: "Account Manager", fieldName: "accountManagerName", type: "text" },
  { label: "Renewal Work", fieldName: "renewalWorkStatus", type: "text" }
];

export default class UpcomingRenewals extends LightningElement {
  columns = COLUMNS;
  renewals = [];
  selectedIds = [];
  errorMessage;
  isLoading = true;
  isSaving = false;

  wiredRenewalsResult;

  @wire(getUpcomingRenewals)
  wiredRenewals(result) {
    this.wiredRenewalsResult = result;
    const { data, error } = result;
    if (data) {
      this.renewals = data.map((renewal) => this.toRow(renewal));
      this.errorMessage = undefined;
      this.isLoading = false;
    } else if (error) {
      this.renewals = [];
      this.errorMessage = this.reduceError(error);
      this.isLoading = false;
    }
  }

  get hasRenewals() {
    return this.renewals.length > 0;
  }

  get isEmpty() {
    return !this.isLoading && !this.errorMessage && this.renewals.length === 0;
  }

  get isStartDisabled() {
    return this.selectedIds.length === 0 || this.isSaving;
  }

  get cardTitle() {
    return this.hasRenewals
      ? `Upcoming Renewals (${this.renewals.length})`
      : "Upcoming Renewals";
  }

  get selectionLabel() {
    const count = this.selectedIds.length;
    return count === 1
      ? "1 agreement selected"
      : `${count} agreements selected`;
  }

  handleRowSelection(event) {
    this.selectedIds = event.detail.selectedRows.map((row) => row.id);
  }

  async handleRefresh() {
    this.isLoading = true;
    try {
      await refreshApex(this.wiredRenewalsResult);
    } finally {
      this.isLoading = false;
    }
  }

  async handleStartRenewal() {
    // Rows already in progress are skipped so the action is idempotent.
    const idsToStart = this.renewals
      .filter(
        (row) =>
          this.selectedIds.includes(row.id) &&
          row.renewalWorkStatus !== IN_PROGRESS
      )
      .map((row) => row.id);

    if (idsToStart.length === 0) {
      this.showToast(
        "Nothing to start",
        "Renewal work is already in progress for the selected agreements.",
        "info"
      );
      return;
    }

    this.isSaving = true;
    try {
      const result = await startRenewalWork({ agreementIds: idsToStart });
      this.notifyResult(result);
      this.selectedIds = [];
      const datatable = this.template.querySelector("lightning-datatable");
      if (datatable) {
        datatable.selectedRows = [];
      }
      await refreshApex(this.wiredRenewalsResult);
    } catch (error) {
      this.showToast(
        "Renewal work was not started",
        this.reduceError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  notifyResult(result) {
    const { successCount, errors } = result;
    if (successCount > 0) {
      const noun = successCount === 1 ? "agreement" : "agreements";
      this.showToast(
        "Renewal work started",
        `${successCount} ${noun} marked as In Progress.`,
        "success"
      );
    }
    if (errors && errors.length > 0) {
      this.showToast(
        "Some agreements were not updated",
        errors.join("\n"),
        "warning"
      );
    }
  }

  toRow(renewal) {
    const isUrgent = renewal.daysRemaining <= URGENT_DAYS;
    return {
      ...renewal,
      agreementUrl: `/${renewal.id}`,
      accountUrl: renewal.accountId ? `/${renewal.accountId}` : undefined,
      daysRemainingClass: isUrgent
        ? "slds-text-color_error slds-text-title_bold"
        : ""
    };
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((item) => item.message).join(", ");
    }
    return error?.body?.message || error?.message || "Unexpected error.";
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
