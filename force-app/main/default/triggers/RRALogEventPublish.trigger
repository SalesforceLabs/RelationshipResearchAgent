trigger RRALogEventPublish on RRALogEvent__e(after insert) {
  List<RRALogs__c> logsToInsert = new List<RRALogs__c>();

  for (RRALogEvent__e evt : Trigger.New) {
    logsToInsert.add(new RRALogs__c(Category__c = evt.Category__c, Log__c = evt.Log__c));
  }

  if (!logsToInsert.isEmpty()) {
    try {
      insert logsToInsert;
    } catch (Exception e) {
      // Never throw from a Platform Event trigger
      System.debug('RRALogEventPublish failed: ' + e.getMessage());
    }
  }
}