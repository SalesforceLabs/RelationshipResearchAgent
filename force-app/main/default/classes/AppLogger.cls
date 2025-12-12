public class AppLogger {
  // Default scenarios
  private static String DEFAULT_LOG_SCENARIO = 'RRALogs';
  private static String DEFAULT_TELEMETRY_SCENARIO = 'RRATelemetry';

  // ------------------------------
  // Logging methods
  // ------------------------------
  public AppLogger info(Map<String, Object> extraContext) {
    return info(JSON.serialize(extraContext));
  }

  public AppLogger info(String message) {
    logInternal('INFO', message);
    return this;
  }

  public AppLogger warn(Map<String, Object> extraContext) {
    return info(JSON.serialize(extraContext));
  }
  public AppLogger warn(String message) {
    logInternal('WARN', message);
    return this;
  }

  public AppLogger error(Map<String, Object> extraContext) {
    return error(JSON.serialize(extraContext));
  }

  public AppLogger error(Exception ex) {
    return error(ex.getMessage());
  }

  public AppLogger error(String message) {
    logInternal('ERROR', message);
    return this;
  }

  public AppLogger AppLogger(Map<String, Object> extraContext) {
    return debug(JSON.serialize(extraContext));
  }

  public AppLogger debug(String message) {
    logInternal('DEBUG', message);
    return this;
  }

  private static Callable getNebulaLoggerInstance() {
    // The following is from the official Nebula Callable Logger integration pattern
    Type nebulaLoggerType = Type.forName('Nebula', 'CallableLogger') ??
      Type.forName('CallableLogger');
    return (Callable) nebulaLoggerType?.newInstance();
  }

  public static Boolean isNebulaLoggerAvailable() {
    return getNebulaLoggerInstance() != null;
  }

  // Cache Nebula Logger instance. Can be null.
  final Callable nebulaLoggerInstance = getNebulaLoggerInstance();
  final String scenario;

  private Integer scenarioSet = 0;

  public AppLogger startScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('setScenario', new Map<String, Object>{ 'scenario' => scenario });
      this.scenarioSet++;
    }
    return this;
  }

  public AppLogger endScenario() {
    if (nebulaLoggerInstance != null) {
      nebulaLoggerInstance.call('endScenario', new Map<String, Object>{ 'scenario' => scenario });
    }
    return this;
  }

  public AppLogger close() {
    while (this.scenarioSet > 0) {
      endScenario();
      scenarioSet--;
    }
    return this;
  }

  public AppLogger() {
    this.scenario = DEFAULT_LOG_SCENARIO;
  }

  public AppLogger(string scenario) {
    this.scenario = scenario;
  }

  public static AppLogger start() {
    return start(DEFAULT_LOG_SCENARIO);
  }

  public static AppLogger start(String scenario) {
    return (new AppLogger(scenario)).startScenario();
  }

  public static AppLogger startTelemetry() {
    return start(DEFAULT_TELEMETRY_SCENARIO);
  }

  // set autoSave to true to automatically save log entries on each log call.
  public Boolean autoSave = false;

  // Internal logging implementation
  private void logInternal(String level, String message) {
    // In Nebula-independent version, we just use System.debug,
    // but it makes sense to make a debug log even if Nebula Logger is available.
    System.debug('[' + level + '][' + scenario + '] ' + message);
    if (nebulaLoggerInstance == null) {
      // If it's null, then neither of Nebula Logger's packages is available in the org.
      // since we've already logged to System.debug, we just return.
      return;
    }
    Map<String, Object> newEntryInput = new Map<String, Object>{
      'loggingLevel' => level,
      'message' => message
    };
    if (autoSave) {
      newEntryInput.put('saveLog', true);
    }
    nebulaLoggerInstance.call('newEntry', newEntryInput);
  }

  public void save() {
    if (nebulaLoggerInstance == null) {
      // In Nebula-independent version, nothing to save
      throw new EventObjectException('nothing available');
      //return;
    }
    nebulaLoggerInstance.call('saveLog', null);
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

    AppLogger log = new AppLogger(scenario);
    if (log.nebulaLoggerInstance == null) {
      // If it's null, then neither of Nebula Logger's packages is available in the org.
      // In Nebula-independent version, we just use System.debug
      System.debug(
        '[Telemetry][' +
          scenario +
          '] Event: ' +
          eventName +
          ' | Properties: ' +
          JSON.serialize(properties)
      );
      return;
    }
    // We want to differentiate the entries even though we set a scenario.
    properties.put('mode', 'telemetry');
    properties.put('eventName', eventName);
    // Currently just log for Nebula-independent fallback
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
