public class AppLoggerFacade {
  // Default scenarios
  private static String DEFAULT_LOG_SCENARIO = 'RRALogs';
  private static String DEFAULT_TELEMETRY_SCENARIO = 'RRATelemetry';

  // ------------------------------
  // Logging methods
  // ------------------------------
  public AppLoggerFacade info(Map<String, Object> extraContext) {
    return info(JSON.serialize(extraContext));
  }

  public AppLoggerFacade info(String message) {
    logInternal('INFO', message);
    return this;
  }

  public AppLoggerFacade warn(Map<String, Object> extraContext) {
    return info(JSON.serialize(extraContext));
  }
  public AppLoggerFacade warn(String message) {
    logInternal('WARN', message);
    return this;
  }

  public AppLoggerFacade error(Map<String, Object> extraContext) {
    return error(JSON.serialize(extraContext));
  }

  public AppLoggerFacade error(Exception ex) {
    return error(ex.getMessage());
  }

  public AppLoggerFacade error(String message) {
    logInternal('ERROR', message);
    return this;
  }

  public AppLoggerFacade AppLoggerFacade(Map<String, Object> extraContext) {
    return debug(JSON.serialize(extraContext));
  }

  public AppLoggerFacade debug(String message) {
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

  public AppLoggerFacade startScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('setScenario', new Map<String, Object>{ 'scenario' => scenario });
      this.scenarioSet++;
    }
    return this;
  }

  public AppLoggerFacade endScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('endScenario', new Map<String, Object>{ 'scenario' => scenario });
    }
    return this;
  }

  public AppLoggerFacade close() {
    while (this.scenarioSet > 0) {
      endScenario();
      scenarioSet--;
    }
    return this;
  }

  public AppLoggerFacade() {
    this.scenario = DEFAULT_LOG_SCENARIO;
  }

  public AppLoggerFacade(string scenario) {
    this.scenario = scenario;
  }

  public static AppLoggerFacade start() {
    return start(DEFAULT_LOG_SCENARIO);
  }

  public static AppLoggerFacade start(String scenario) {
    return (new AppLoggerFacade(scenario)).startScenario();
  }

  public static AppLoggerFacade startTelemetry() {
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

    public void Add(string category, string data) {
      logs.add(new LogDataToPublish(category, data));
    }
    // high-volume is 2000 events per call
    // but we also are limited per transaction
    Integer batchSize = 1500;
    public void save() {
      if (logs.isEmpty()) {
        return; // nothing to do
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
      batchSize -= logs.size();
      logs.clear();
    }
  }

  static Integer suspendAutoSaveCounter = 0;

  public static void SuspendAutoSave() {
    suspendAutoSaveCounter++;
  }

  public static void ResumeAutoSave() {
    suspendAutoSaveCounter = Math.max(0, suspendAutoSaveCounter - 1);
    if (suspendAutoSaveCounter == 0) {
      System.debug('Dispatching logs after ResumeAutoSave');
      // this is presumably the end of the suspend, dispatch logs.
      DispatchLogs();
    }
  }

  public static void DispatchLogs() {
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
      DispatchLogs();
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
    DispatchLogs();
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
    AppLoggerFacade log = new AppLoggerFacade(scenario);
    try {
      log.autoSave = true;
      log.startScenario();
      log.logInternal('INFO', JSON.serialize(properties));
    } finally {
      // Ensure we close the scenario.
      log.close();
    }
    // Example placeholder for stateless backend integration with InstrumentationService
    // Uncomment and implement when InstrumentationOperation is available
    /*
        InstrumentationService service = new InstrumentationService(MetricServiceEnum.CRM, 'subservice', 'feature', 'subfeature');
        InstrumentationOperation op = service.getInstrumentationOperation(eventName, null);
        // Example: publish request count
        op.publishIncrementalValue(MetricTypeEnum.REQUEST_COUNT, 1, 0);
        // Example: publish duration
        op.publishIncrementalValue(MetricTypeEnum.DURATION, durationMs, 0);
        */
  }
}
