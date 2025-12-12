public with sharing class RRAClientAsync implements Queueable {
  private String recordId;
  private String optionsJson;
  public class JobResponse {
    public String jobId;
    public String status;

    public JobResponse(String jobId, String status) {
      this.jobId = jobId;
      this.status = status;
    }
  }

  public RRAClientAsync(String recordId, String optionsJson) {
    this.recordId = recordId;
    this.optionsJson = optionsJson;
  }

  private static String getCacheKey(String recordId) {
    return 'RRA' + recordId;
  }

  @AuraEnabled(cacheable=false)
  public static String createRelationshipsAsync(String recordId, String optionsJson) {
    String jobKey = getCacheKey(recordId);
    Cache.OrgPartition rraPartition = CacheProvider.getRRAPartition();

    if (rraPartition == null) {
      throw new AuraHandledException(
        'Platform cache partition is required for async job tracking. Please deploy the rraCache partition.'
      );
    }

    // Check for existing active job
    String existingJobId = (String) rraPartition.get(jobKey);

    if (String.isNotBlank(existingJobId)) {
      AsyncApexJob activeJob = CrmDatabaseSelectors.getActiveAsyncJob(existingJobId);

      if (activeJob != null) {
        return JSON.serialize(new JobResponse(existingJobId, 'ALREADY_QUEUED'));
      } else {
        // Clean up stale cache entry
        rraPartition.remove(jobKey);
      }
    }

    Id jobId = System.enqueueJob(new RRAClientAsync(recordId, optionsJson));

    // Cache for 2 hours
    rraPartition.put(jobKey, String.valueOf(jobId), 7200);

    return JSON.serialize(new JobResponse(String.valueOf(jobId), 'QUEUED'));
  }

  String getDebugErrorInfo(Exception e) {
    return 'RRA async job failed for record: ' +
      recordId +
      ' - ' +
      e.getMessage() +
      ' | line=' +
      e.getLineNumber() +
      ' | stack=' +
      e.getStackTraceString();
  }

  public void execute(QueueableContext context) {
    Benchmarker bm = new Benchmarker('RRAClientAsync.execute');
    bm.startTelemetry();
    String jobCompleteEventStatus = 'Failed';
    try {
      AppLoggerFacade.SuspendAutoSave();
      RRAClient.createRelationships(recordId, optionsJson);
      System.debug('RRA async job completed for record: ' + recordId);
      jobCompleteEventStatus = 'Success';
    } catch (Exception e) {
      bm.error(e);
      System.debug(getDebugErrorInfo(e));
      throw e;
    } finally {
      publishJobCompleteEvent(recordId, jobCompleteEventStatus);
      bm.complete();
      // make sure logs get written
      AppLoggerFacade.ResumeAutoSave();
      // Clean up cache when job completes (success or failure)
      Cache.OrgPartition rraPartition = CacheProvider.getRRAPartition();
      if (rraPartition != null) {
        rraPartition.remove(getCacheKey(recordId));
      }
    }
  }

  private void publishJobCompleteEvent(String recordId, String status) {
    RRA_Job_Complete__e event = new RRA_Job_Complete__e(RecordId__c = recordId, Status__c = status);

    Database.SaveResult result = EventBus.publish(event);

    if (result.isSuccess()) {
      System.debug('Successfully published RRA job completion event for record: ' + recordId);
    } else {
      for (Database.Error error : result.getErrors()) {
        System.debug('Error publishing event: ' + error.getMessage());
      }
    }
  }
}
