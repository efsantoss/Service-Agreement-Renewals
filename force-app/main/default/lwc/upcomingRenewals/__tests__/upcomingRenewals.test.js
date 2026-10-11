import { createElement } from "@lwc/engine-dom";
import UpcomingRenewals from "c/upcomingRenewals";
import getUpcomingRenewals from "@salesforce/apex/UpcomingRenewalsController.getUpcomingRenewals";
import startRenewalWork from "@salesforce/apex/UpcomingRenewalsController.startRenewalWork";

// Event name dispatched by ShowToastEvent (the Jest stub does not export it).
const SHOW_TOAST_EVENT = "lightning__showtoast";

jest.mock(
  "@salesforce/apex/UpcomingRenewalsController.getUpcomingRenewals",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/UpcomingRenewalsController.startRenewalWork",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const RENEWALS = [
  {
    id: "a01000000000001AAA",
    agreementName: "Acme Support",
    accountId: "001000000000001AAA",
    accountName: "Acme",
    endDate: "2027-01-15",
    daysRemaining: 5,
    agreementValue: 25000,
    accountManagerName: "Jane Doe",
    renewalWorkStatus: "Not Started",
    hasRenewalTask: true
  },
  {
    id: "a01000000000002AAA",
    agreementName: "Globex Maintenance",
    accountId: "001000000000002AAA",
    accountName: "Globex",
    endDate: "2027-02-01",
    daysRemaining: 22,
    agreementValue: 9000,
    accountManagerName: "John Roe",
    renewalWorkStatus: "Not Started",
    hasRenewalTask: true
  }
];

// Lets pending promise callbacks run so the DOM reflects async updates.
async function flushPromises() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function createComponent() {
  const element = createElement("c-upcoming-renewals", {
    is: UpcomingRenewals
  });
  document.body.appendChild(element);
  return element;
}

describe("c-upcoming-renewals", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders one row per upcoming renewal and flags urgent ones", async () => {
    const element = createComponent();
    getUpcomingRenewals.emit(RENEWALS);
    await flushPromises();

    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable).not.toBeNull();
    expect(datatable.data).toHaveLength(2);
    expect(datatable.data[0].agreementUrl).toBe("/a01000000000001AAA");
    expect(datatable.data[0].daysRemainingClass).toContain(
      "slds-text-color_error"
    );
    expect(datatable.data[1].daysRemainingClass).toBe("");
  });

  it("shows an empty state when nothing requires attention", async () => {
    const element = createComponent();
    getUpcomingRenewals.emit([]);
    await flushPromises();

    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
  });

  it("shows a friendly error when the data cannot be loaded", async () => {
    const element = createComponent();
    getUpcomingRenewals.error({
      message: "Upcoming renewals could not be loaded."
    });
    await flushPromises();

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error).not.toBeNull();
    expect(error.textContent).toContain("could not be loaded");
  });

  it("starts renewal work for the selected rows and confirms with a toast", async () => {
    startRenewalWork.mockResolvedValue({ successCount: 1, errors: [] });
    const element = createComponent();
    const toastHandler = jest.fn();
    element.addEventListener(SHOW_TOAST_EVENT, toastHandler);
    getUpcomingRenewals.emit(RENEWALS);
    await flushPromises();

    const startButton = element.shadowRoot.querySelector("lightning-button");
    expect(startButton.disabled).toBe(true);

    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    datatable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [RENEWALS[0]] }
      })
    );
    await flushPromises();
    expect(startButton.disabled).toBe(false);

    startButton.click();
    await flushPromises();

    expect(startRenewalWork).toHaveBeenCalledWith({
      agreementIds: ["a01000000000001AAA"]
    });
    expect(toastHandler).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
  });
});
