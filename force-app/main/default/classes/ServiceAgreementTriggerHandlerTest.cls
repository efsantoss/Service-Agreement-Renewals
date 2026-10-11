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

  /**
   * @description Stub that reports every received agreement as failed.
   */
  private class FailingRenewalTaskService implements System.StubProvider {
    public Integer callCount = 0;

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

  private static Service_Agreement__c agreementWithFakeId(Integer index) {
    String keyPrefix = Service_Agreement__c.SObjectType.getDescribe()
      .getKeyPrefix();
    return new Service_Agreement__c(
      Id = keyPrefix + String.valueOf(index).leftPad(12, '0')
    );
  }

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
