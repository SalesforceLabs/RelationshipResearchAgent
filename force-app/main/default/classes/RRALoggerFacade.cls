public class RRALoggerFacade {
  // Default scenarios
  private static String DEFAULT_LOG_SCENARIO = 'RRALogs';
  private static String DEFAULT_TELEMETRY_SCENARIO = 'RRATelemetry';

  // ------------------------------
  // Logging methods
  // ------------------------------

  public RRALoggerFacade info(String message) {
    logInternal('INFO', message);
    return this;
  }

  public RRALoggerFacade warn(String message) {
    logInternal('WARN', message);
    return this;
  }

  public RRALoggerFacade error(Exception ex) {
    return error(ex.getMessage());
  }

  public RRALoggerFacade error(String message) {
    logInternal('ERROR', message);
    return this;
  }

  // Currently used by Benchmarker
  public RRALoggerFacade debug(String message) {
    logInternal('DEBUG', message);
    return this;
  }

  private static Callable getNebulaLoggerInstance() {
    // The following is from the official Nebula Callable Logger integration pattern
    try {
      Type nebulaLoggerType = Type.forName('Nebula', 'CallableLogger') ??
        Type.forName('CallableLogger');
      return (Callable) nebulaLoggerType?.newInstance();
    } catch (Exception e) {
      System.debug('Error getting Nebula Logger instance: ' + e.getMessage());
      return null;
    }
  }

  public static Boolean isNebulaLoggerAvailable() {
    return nebulaLoggerInstance != null;
  }

  // Cache Nebula Logger instance. Can be null.
  final static Callable nebulaLoggerInstance = getNebulaLoggerInstance();
  final String scenario;

  private Integer scenarioSet = 0;

  public RRALoggerFacade startScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('setScenario', new Map<String, Object>{ 'scenario' => scenario });
      this.scenarioSet++;
    }
    return this;
  }

  public RRALoggerFacade endScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('endScenario', new Map<String, Object>{ 'scenario' => scenario });
    }
    return this;
  }

  public RRALoggerFacade close() {
    while (this.scenarioSet > 0) {
      endScenario();
      scenarioSet--;
    }
    return this;
  }

  public RRALoggerFacade() {
    this.scenario = DEFAULT_LOG_SCENARIO;
  }

  public RRALoggerFacade(String scenario) {
    this.scenario = scenario;
  }

  public static RRALoggerFacade start() {
    return start(DEFAULT_LOG_SCENARIO);
  }

  public static RRALoggerFacade start(String scenario) {
    return (new RRALoggerFacade(scenario)).startScenario();
  }

  public static RRALoggerFacade startTelemetry() {
    return start(DEFAULT_TELEMETRY_SCENARIO);
  }

  // set autoSave to true to automatically save log entries on each log call.
  public Boolean autoSave = false;

  class LogDataToPublish {
    public String category;
    public String message;
    public Integer purgeOrder;

    public LogDataToPublish(String category, String message) {
      this.category = category;
      this.message = message;
      if (category.startsWith('RRATelemetry:EinsteinPromptService-Call')) {
        this.purgeOrder = 4;
      } else if (category.startsWith('RRATelemetry:')) {
        this.purgeOrder = 3;
      } else if (category.startsWith('ERROR')) {
        this.purgeOrder = 2;
      } else if (category.startsWith('WARN')) {
        this.purgeOrder = 1;
      } else {
        this.purgeOrder = 0;
      }
    }
  }

  public class LogQueueable {
    private final List<LogDataToPublish> logs = new List<LogDataToPublish>();

    public void add(String category, String data) {
      logs.add(new LogDataToPublish(category, data));
    }
    // high-volume is 2000 events per call
    // but we also are limited per transaction
    final Integer callBatchSize = 1500;
    // max per transaction is 10000 events, however we want to leave some room
    // for other DML operations in the transaction, most importantly Nebula Logger calls.
    Integer maxTransactionBatchSize = 4000;

    public void save() {
      if (logs.isEmpty()) {
        return; // nothing to do
      }
      Integer batchSize = Math.min(maxTransactionBatchSize, callBatchSize);
      // we want to make sure that all telemetry events are preserved .
      Integer countOfTelemetryLogs = 0;
      for (Integer i = 0; i < logs.size(); i++) {
        LogDataToPublish log = logs[i];
        if (log.category.startsWith('RRATelemetry:')) {
          // telemetry logs must always be preserved
          countOfTelemetryLogs++;
        }
      }
      // increase batch size to accommodate all telemetry logs.
      if (countOfTelemetryLogs >= batchSize) {
        batchSize = countOfTelemetryLogs;
      }
      if (batchSize <= 0) {
        // not a fatal error: the batch size would have been extended to preserve
        // telemetry logs already.
        System.debug('RRALoggerFacade.LogQueueable: Zero available batch size');
        return;
      }
      while (logs.size() > batchSize) {
        Integer maxPurgeOrder = -1;
        Integer minPurgeOrder = -1;
        for (Integer i = 0; i < logs.size(); i++) {
          // do nothing, just to advance the index
          Integer checkPurgeOrder = logs[i].purgeOrder;
          if (maxPurgeOrder == -1 || checkPurgeOrder > maxPurgeOrder) {
            maxPurgeOrder = checkPurgeOrder;
          }
          if (minPurgeOrder == -1 || checkPurgeOrder < minPurgeOrder) {
            minPurgeOrder = checkPurgeOrder;
          }
        }
        for (Integer i = logs.size() - 1; i >= 0; i--) {
          LogDataToPublish log = logs[i];
          // purge lowest priority first
          if (log.purgeOrder == minPurgeOrder) {
            logs.remove(i);
            // check if we are under batch size now.
            // but if we can remove lower-order priority only, continue
            if (maxPurgeOrder == minPurgeOrder && logs.size() <= batchSize) {
              break;
            }
          }
        }
      }
      List<RRALogEvent__e> eventsToInsert = new List<RRALogEvent__e>();
      for (LogDataToPublish log : logs) {
        eventsToInsert.add(new RRALogEvent__e(Category__c = log.category, Log__c = log.message));
      }
      Database.SaveResult[] results = EventBus.publish(eventsToInsert);
      Integer publishedCount = 0;
      for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
          publishedCount++;
        } else {
          System.debug(
            'Failed to publish log event: ' +
              results[i].getErrors()[0].getMessage() +
              ' | Category=' +
              eventsToInsert[i].Category__c +
              ' | Log=' +
              eventsToInsert[i].Log__c
          );
        }
      }
      System.debug('published ' + publishedCount.toString() + ' events through RRALogEvent__e');
      this.maxTransactionBatchSize -= logs.size();
      logs.clear();
    }
  }

  static Integer suspendAutoSaveCounter = 0;

  public static void suspendAutoSave() {
    suspendAutoSaveCounter++;
  }

  public static void resumeAutoSave() {
    suspendAutoSaveCounter = Math.max(0, suspendAutoSaveCounter - 1);
    if (suspendAutoSaveCounter == 0) {
      System.debug('Dispatching logs after resumeAutoSave');
      // this is presumably the end of the suspend, dispatch logs.
      dispatchLogs();
    }
  }

  public static void dispatchLogs() {
    if (suspendAutoSaveCounter > 0) {
      return;
    }
    logQueueableInstance.save();
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('saveLog', null);
    }
  }

  static LogQueueable logQueueableInstance = new LogQueueable();

  // Internal logging implementation
  private void logInternal(String level, String message) {
    // In Nebula-independent version, we just use System.debug,
    // but it makes sense to make a debug log even if Nebula Logger is available.
    System.debug('[' + level + '][' + scenario + '] ' + message);
    // skip logging when doing apex jobs - only telemetry is needed
    // Also, do not save DEBUG logs to avoid excessive DML usage
    if (suspendAutoSaveCounter == 0 && level != 'DEBUG') {
      logQueueableInstance.add(level, message);
    }
    if (nebulaLoggerInstance == null) {
      // If it's null, then neither of Nebula Logger's packages is available in the org.
      // since we've already logged to System.debug, we just return.
      dispatchLogs();
      return;
    }
    Map<String, Object> newEntryInput = new Map<String, Object>{
      'loggingLevel' => level,
      'message' => message
    };
    // avoid auto save while we're running background jobs.
    if (autoSave && suspendAutoSaveCounter == 0) {
      newEntryInput.put('saveLog', true);
    }
    nebulaLoggerInstance.call('newEntry', newEntryInput);
  }

  public void save() {
    dispatchLogs();
  }

  // ------------------------------
  // Telemetry methods
  // ------------------------------

  // Publish telemetry with default scenario
  public static void sendTelemetry(String eventName, Map<String, Object> properties) {
    sendTelemetry(eventName, DEFAULT_TELEMETRY_SCENARIO, null, null, properties);
  }

  public static void sendTelemetry(String eventName, Integer count) {
    sendTelemetry(eventName, DEFAULT_TELEMETRY_SCENARIO, count, null, null);
  }

  public static void sendTelemetry(String eventName, Integer count, Long durationMs) {
    sendTelemetry(eventName, DEFAULT_TELEMETRY_SCENARIO, count, durationMs, null);
  }

  // Publish telemetry with custom scenario and properties
  public static void sendTelemetry(
    String eventName,
    String scenario,
    Integer count,
    Long durationMs,
    Map<String, Object> properties
  ) {
    if (properties == null) {
      properties = new Map<String, Object>();
    }
    // currently, operate through properties only, nebula or not
    if (count != null) {
      properties.put('count', count);
    }
    if (durationMs != null) {
      properties.put('durationMs', durationMs);
    }
    String jsonProperties = JSON.serialize(properties);

    // We always queue the telemetry event through our log queueable.
    logQueueableInstance.add(scenario + ':' + eventName, jsonProperties);
    // If it's null, then neither of Nebula Logger's packages is available in the org.
    if (nebulaLoggerInstance == null) {
      // In Nebula-independent version, we just use System.debug
      System.debug(
        '[Telemetry][' + scenario + '] Event: ' + eventName + ' | Properties: ' + jsonProperties
      );
      return;
    }
    // We want to differentiate the entries even though we set a scenario.
    properties.put('mode', 'telemetry');
    properties.put('eventName', eventName);
    // Perform Nebula logging
    RRALoggerFacade log = new RRALoggerFacade(scenario);
    try {
      log.autoSave = true;
      log.startScenario();
      log.logInternal('INFO', JSON.serialize(properties));
    } finally {
      // Must always call close() after startScenario() to properly finalize and persist the scenario.
      log.close();
    }
  }
}
