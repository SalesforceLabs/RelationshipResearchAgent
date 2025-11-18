public with sharing class RRAClientAsync implements Queueable {
  private String recordId;
  private Boolean useDeepWebSearch;
  private Boolean useRecordContext;
  private Boolean isNewResearch;

  public class JobResponse {
    public String jobId;
    public String status;

    public JobResponse(String jobId, String status) {
      this.jobId = jobId;
      this.status = status;
    }
  }

  public RRAClientAsync(
    String recordId,
    Boolean useDeepWebSearch,
    Boolean useRecordContext,
    Boolean isNewResearch
  ) {
    this.recordId = recordId;
    this.useDeepWebSearch = useDeepWebSearch;
    this.useRecordContext = useRecordContext;
    this.isNewResearch = isNewResearch;
  }

  private static String getCacheKey(String recordId) {
    return 'RRA' + recordId;
  }

  @AuraEnabled(cacheable=false)
  public static String createRelationshipsAsync(
    String recordId,
    Boolean useDeepWebSearch,
    Boolean useRecordContext,
    Boolean isNewResearch
  ) {
    String jobKey = getCacheKey(recordId);

    // Check for existing active job
    String existingJobId = (String) Cache.Org.get(jobKey);
    if (String.isNotBlank(existingJobId)) {
      AsyncApexJob activeJob = CrmDatabaseSelectors.getActiveAsyncJob(existingJobId);

      if (activeJob != null) {
        return JSON.serialize(new JobResponse(existingJobId, 'ALREADY_QUEUED'));
      } else {
        // Clean up stale cache entry
        Cache.Org.remove(jobKey);
      }
    }

    Id jobId = System.enqueueJob(
      new RRAClientAsync(recordId, useDeepWebSearch, useRecordContext, isNewResearch)
    );

    // Cache for 2 hours
    Cache.Org.put(jobKey, String.valueOf(jobId), 7200);

    return JSON.serialize(new JobResponse(String.valueOf(jobId), 'QUEUED'));
  }

  public void execute(QueueableContext context) {
    try {
      RRAClient.createRelationships(recordId, useDeepWebSearch, useRecordContext, isNewResearch);
      System.debug('RRA async job completed for record: ' + recordId);
    } catch (Exception e) {
      System.debug('RRA async job failed for record: ' + recordId + ' - ' + e.getMessage());
      throw e;
    } finally {
      // Clean up cache when job completes (success or failure)
      Cache.Org.remove(getCacheKey(recordId));
    }
  }
}
