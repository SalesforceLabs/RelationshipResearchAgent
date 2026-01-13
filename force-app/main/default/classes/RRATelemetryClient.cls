public with sharing class RRATelemetryClient {
  private final Map<String, TelemetryLogger> telemetries = new Map<String, TelemetryLogger>();

  private TelemetryLogger activeTelemetryLogger;

  private Benchmarker bm;

  public class RRATelemetryClientException extends Exception {
  }

  public static RRATelemetryClient startTelemetry(String operation) {
    RRATelemetryClient client = new RRATelemetryClient();
    client.start(operation);
    return client;
  }

  private List<Exception> exceptions = new List<Exception>();

  public void error(Exception ex) {
    exceptions.add(ex);
  }

  RRALoggerFacade logger;
  // cached logger for convenience
  public RRALoggerFacade getLogger() {
    if (logger == null) {
      if (bm == null) {
        throw new RRATelemetryClientException('start telemetry before getting logger');
      }
      logger = bm.getLogger();
    }
    return logger;
  }

  public void complete() {
    if (bm == null) {
      return;
    }
    System.debug('RRATelemetryClient: Completing ' + bm.getOperation());
    RRALoggerFacade logger = this.logger;
    if (exceptions.size() > 0) {
      logger = getLogger();
      if (activeTelemetryLogger != null) {
        activeTelemetryLogger.addError(exceptions.size());
      }
      for (Exception ex : exceptions) {
        logger.error(ex);
      }
      exceptions.clear();
    }
    if (bm.stop()) {
      activeTelemetryLogger?.logGeneralCall();
    }
    logger?.save();
  }

  public void complete(List<Object> successes) {
    complete(successes, null);
  }

  public void complete(List<Object> successes, List<Object> failures) {
    this.complete();
    activeTelemetryLogger?.logResultSuccess(successes);
    activeTelemetryLogger?.logResultFailure(failures);
  }

  public void complete(Integer successes) {
    this.complete();
    activeTelemetryLogger?.logResultSuccess(successes);
  }

  public void complete(Integer successes, Integer failures) {
    this.complete();
    activeTelemetryLogger?.logResultSuccess(successes);
    activeTelemetryLogger?.logResultFailure(failures);
  }

  public TelemetryLogger start(String componentName) {
    return start(componentName, null);
  }

  public TelemetryLogger start(String componentName, String context) {
    if (bm == null) {
      bm = new Benchmarker(componentName);
    }
    bm.start();
    String key = componentName + '-' + (String.isNotBlank(context) ? '-' + context : '');
    activeTelemetryLogger = telemetries.get(key);
    if (activeTelemetryLogger == null) {
      activeTelemetryLogger = new TelemetryLogger(bm, componentName, context);
      telemetries.put(key, activeTelemetryLogger);
    }
    return activeTelemetryLogger;
  }

  public class TelemetryLogger {
    private final String componentName;
    private final Benchmarker bm;
    public String context; // optional context, read/writable

    public TelemetryLogger(Benchmarker bm, String componentName, String context) {
      this.bm = bm;
      this.componentName = componentName;
      this.context = context;
    }

    private String buildTelemetryKey(String eventType, String eventContext) {
      return componentName +
        '-' +
        eventType +
        (String.isNotBlank(eventContext) ? '-' + eventContext : '');
    }

    Integer errorCount = 0;
    public void addError() {
      errorCount++;
    }

    public void addError(Integer count) {
      errorCount += count;
    }

    public void logGeneralError(Integer count) {
      Long durationMs = bm.getDuration();
      RRALoggerFacade.sendTelemetry(buildTelemetryKey('Error', context), 1, durationMs);
    }

    public void logGeneralCall() {
      bm.stop();
      Long durationMs = bm.getDuration();
      RRALoggerFacade.sendTelemetry(buildTelemetryKey('Call', context), 1, durationMs);
      if (errorCount > 0) {
        logGeneralError(errorCount);
      }
    }

    public void logResultSuccess(List<Object> results) {
      logResult('Result-Success', results);
    }

    public void logResultSuccess(Integer count) {
      logResult('Result-Success', count);
    }

    public void logResultFailure(List<Object> results) {
      logResult('Result-Failure', results);
    }

    public void logResultFailure(Integer count) {
      logResult('Result-Failure', count);
    }

    void logResult(String eventType, List<Object> results) {
      Integer count = (results != null) ? results.size() : 0;
      logResult(eventType, count);
    }

    void logResult(String eventType, Integer count) {
      if (count > 0) {
        Long durationMs = bm.getDuration();
        RRALoggerFacade.sendTelemetry(buildTelemetryKey(eventType, context), count, durationMs);
      }
    }
  }
}
