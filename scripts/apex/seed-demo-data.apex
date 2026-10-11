// Creates demonstration data for the Upcoming Renewals component.
// Dates are relative to today, so the demo always shows a realistic list.
// Safe to run more than once: previous demo records (names starting with "DEMO - ") are replaced.
//
// Run:  sf apex run --file scripts/apex/seed-demo-data.apex --target-org dev

final String PREFIX = 'DEMO - ';
Date today = Date.today();
Id currentUserId = UserInfo.getUserId();

// 1. Remove previous demo data (Renewal Tasks first, then agreements).
List<Service_Agreement__c> previous = [
  SELECT Id
  FROM Service_Agreement__c
  WHERE Name LIKE 'DEMO - %'
];
delete [SELECT Id FROM Task WHERE WhatId IN :previous];
delete previous;

// 2. Use existing accounts, or create a few when the org has none.
List<Account> accounts = [SELECT Id FROM Account ORDER BY Name LIMIT 5];
if (accounts.isEmpty()) {
  accounts = new List<Account>{
    new Account(Name = 'Acme Corporation'),
    new Account(Name = 'Globex'),
    new Account(Name = 'Initech')
  };
  insert accounts;
}

// 3. Scenarios: name, days until End Date, Status, Renewal Required, value, has Account Manager.
List<Object[]> scenarios = new List<Object[]>{
  // Qualifying: shown in the component and receive a Renewal Task.
  new List<Object>{ 'Premium Support', 2, 'Active', true, 48000, true },
  new List<Object>{ 'Field Service Plan', 6, 'Active', true, 120000, true },
  new List<Object>{ 'Cloud Hosting', 12, 'Active', true, 36000, false },
  new List<Object>{ 'Managed Network', 21, 'Active', true, 75000, true },
  new List<Object>{ 'Annual Maintenance', 30, 'Active', true, 15000, true },
  // Not qualifying: hidden from the component and no Task.
  new List<Object>{ 'Draft Proposal', 10, 'Draft', true, 20000, true },
  new List<Object>{ 'No Renewal Needed', 8, 'Active', false, 5000, true },
  new List<Object>{ 'Outside Window', 45, 'Active', true, 60000, true },
  new List<Object>{ 'Already Expired', -5, 'Expired', true, 30000, true },
  new List<Object>{ 'Cancelled Contract', 15, 'Cancelled', true, 12000, true }
};

List<Service_Agreement__c> agreements = new List<Service_Agreement__c>();
for (Integer i = 0; i < scenarios.size(); i++) {
  Object[] scenario = scenarios[i];
  Date endDate = today.addDays((Integer) scenario[1]);
  agreements.add(
    new Service_Agreement__c(
      Name = PREFIX + (String) scenario[0],
      Account__c = accounts[Math.mod(i, accounts.size())].Id,
      Start_Date__c = endDate.addYears(-1),
      End_Date__c = endDate,
      Status__c = (String) scenario[2],
      Renewal_Required__c = (Boolean) scenario[3],
      Agreement_Value__c = (Integer) scenario[4],
      Account_Manager__c = (Boolean) scenario[5] ? currentUserId : null,
      Renewal_Work_Status__c = 'Not Started'
    )
  );
}
insert agreements;

Integer renewalTasks = [SELECT COUNT() FROM Task WHERE WhatId IN :agreements];
System.debug(
  LoggingLevel.INFO,
  'Demo agreements created: ' +
    agreements.size() +
    ', Renewal Tasks created: ' +
    renewalTasks
);
