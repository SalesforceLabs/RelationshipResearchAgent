global class RRALogsCleanupJob implements Database.Batchable<SObject>, Schedulable {
  Integer retentionDays = 365;

  public RRALogsCleanupJob() {
  }

  public RRALogsCleanupJob(Integer retentionDays) {
    this.retentionDays = retentionDays;
  }

  global Database.QueryLocator start(Database.BatchableContext bc) {
    System.debug('RRALogsCleanupJob started');
    String soql =
      'SELECT Id FROM RRALogs__c WHERE CreatedDate < LAST_N_DAYS:' + retentionDays.toString();

    return Database.getQueryLocator(soql);
  }

  global void execute(Database.BatchableContext bc, List<RRALogs__c> scope) {
    System.debug('RRALogsCleanupJob: Deleting ' + scope.size() + ' RRALogs__c records');
    delete scope;
  }

  global void finish(Database.BatchableContext bc) {
    System.debug('RRALogsCleanupJob finished');
  }

  // Schedulable interface method
  global void execute(SchedulableContext sc) {
    Database.executeBatch(new RRALogsCleanupJob(), 200);
  }

  global static void runCleanupNow(Integer retentionDays) {
    Database.executeBatch(new RRALogsCleanupJob(retentionDays), 200);
  }

  global static void scheduleJobWeekly() {
    String jobName = 'RRALogs Cleanup';

    // Delete existing scheduled job with the same name
    for (CronTrigger ct : [
      SELECT Id
      FROM CronTrigger
      WHERE CronJobDetail.Name = :jobName
    ]) {
      System.abortJob(ct.Id);
    }

    String cronExpression = '0 0 2 ? * SUN'; // every Sunday at 2am
    System.schedule(jobName, cronExpression, new RRALogsCleanupJob());
  }
}
