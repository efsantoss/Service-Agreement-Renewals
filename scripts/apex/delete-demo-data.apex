// Removes the demonstration data created by seed-demo-data.apex
// (agreements whose name starts with "DEMO - " and their Renewal Tasks).
//
// Run:  sf apex run --file scripts/apex/delete-demo-data.apex --target-org dev

List<Service_Agreement__c> demoAgreements = [
  SELECT Id
  FROM Service_Agreement__c
  WHERE Name LIKE 'DEMO - %'
];
List<Task> demoTasks = [SELECT Id FROM Task WHERE WhatId IN :demoAgreements];
delete demoTasks;
delete demoAgreements;
System.debug(
  LoggingLevel.INFO,
  'Deleted ' +
    demoAgreements.size() +
    ' demo agreements and ' +
    demoTasks.size() +
    ' tasks.'
);
