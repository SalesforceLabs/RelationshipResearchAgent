public with sharing class RRAClientAsync implements Queueable {
  private String recordId;
  private RRAClientOptions options;
  public class JobResponse {
    public String jobId;
    public String status;

    public JobResponse(String jobId, String status) {
      this.jobId = jobId;
      this.status = status;
    }
  }

  public RRAClientAsync(String recordId, RRAClientOptions options) {
    this.recordId = recordId;
    this.options = options;
  }

  private static String getCacheKey(String recordId) {
    return 'RRA' + recordId;
  }

  @AuraEnabled(cacheable=false)
  public static String createRelationshipsAsync(String recordId, RRAClientOptions options) {
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

    Id jobId = System.enqueueJob(new RRAClientAsync(recordId, options));

    // Cache for 2 hours
    rraPartition.put(jobKey, String.valueOf(jobId), 7200);

    return JSON.serialize(new JobResponse(String.valueOf(jobId), 'QUEUED'));
  }

  public void execute(QueueableContext context) {
    try {
      RRAClient.createRelationships(recordId, options);
      System.debug('RRA async job completed for record: ' + recordId);
    } catch (Exception e) {
      System.debug('RRA async job failed for record: ' + recordId + ' - ' + e.getMessage());
      throw e;
    } finally {
      // Clean up cache when job completes (success or failure)
      Cache.OrgPartition rraPartition = CacheProvider.getRRAPartition();
      if (rraPartition != null) {
        rraPartition.remove(getCacheKey(recordId));
      }
    }
  }
}
