/**
 * @description Unit tests for ServiceAgreementTriggerHandler. The RenewalTaskService is replaced
 *              by a stub (Apex Stub API), so failure paths that are hard to provoke with real
 *              data can be verified: a Task that cannot be created must be reported on the
 *              agreement instead of being dropped silently.
 * @author      Enzo Fischer
 */
@IsTest
private class ServiceAgreementTriggerHandlerTest {
  private static final String SIMULATED_ERROR = 'Simulated failure';

  // Inner class that plays the role of a RenewalTaskService that fails for every agreement.
  private class FailingRenewalTaskService implements System.StubProvider {
    public Integer callCount = 0;

    // Method that answers every stubbed call with a failure for each received agreement.
    public Object handleMethodCall(
      Object stubbedObject,
      String stubbedMethodName,
      Type returnType,
      List<Type> parameterTypes,
      List<String> parameterNames,
      List<Object> arguments
    ) {
      callCount++;
      Map<Id, String> errors = new Map<Id, String>();
      for (
        Service_Agreement__c agreement : (List<Service_Agreement__c>) arguments[0]
      ) {
        errors.put(agreement.Id, SIMULATED_ERROR);
      }
      return errors;
    }
  }

  // Method that builds an in-memory agreement with a valid-looking fake Id (no DML needed).
  private static Service_Agreement__c agreementWithFakeId(Integer index) {
    String keyPrefix = Service_Agreement__c.SObjectType.getDescribe()
      .getKeyPrefix();
    return new Service_Agreement__c(
      Id = keyPrefix + String.valueOf(index).leftPad(12, '0')
    );
  }

  // Test method that checks a Task failure is reported as an error on the agreement.
  @IsTest
  static void reportsTaskFailuresOnTheAgreement() {
    FailingRenewalTaskService provider = new FailingRenewalTaskService();
    RenewalTaskService failingService = (RenewalTaskService) Test.createStub(
      RenewalTaskService.class,
      provider
    );
    Service_Agreement__c agreement = agreementWithFakeId(1);

    Test.startTest();
    new ServiceAgreementTriggerHandler(failingService)
      .run(
        System.TriggerOperation.AFTER_INSERT,
        new List<Service_Agreement__c>{ agreement }
      );
    Test.stopTest();

    Assert.isTrue(
      agreement.hasErrors(),
      'A Task failure must be reported on the agreement.'
    );
    Assert.isTrue(
      agreement.getErrors()[0].getMessage().contains(SIMULATED_ERROR),
      'The error should explain why the Task was not created.'
    );
  }

  // Test method that checks the service is not called in contexts without renewal logic.
  @IsTest
  static void ignoresContextsWithoutRenewalLogic() {
    FailingRenewalTaskService provider = new FailingRenewalTaskService();
    RenewalTaskService failingService = (RenewalTaskService) Test.createStub(
      RenewalTaskService.class,
      provider
    );
    Service_Agreement__c agreement = agreementWithFakeId(2);

    Test.startTest();
    new ServiceAgreementTriggerHandler(failingService)
      .run(
        System.TriggerOperation.BEFORE_UPDATE,
        new List<Service_Agreement__c>{ agreement }
      );
    Test.stopTest();

    Assert.areEqual(
      0,
      provider.callCount,
      'The service should only run in after insert and after update.'
    );
    Assert.isFalse(
      agreement.hasErrors(),
      'No errors are expected in other contexts.'
    );
  }
}
