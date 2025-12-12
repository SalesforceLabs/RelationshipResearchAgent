public with sharing class Benchmarker {
  private Long startTime = null;
  // null until stop() is called
  private Long endTime = null;
  private String operation;

  public AppLogger logger = null;

  public AppLogger getLogger() {
    if (this.logger == null) {
      // default app logger, do not start a scenario.
      this.logger = new AppLogger();
      this.logger.autoSave = true;
    }
    return this.logger;
  }

  public Benchmarker(String operationName) {
    this.operation = operationName;
  }

  public void start() {
    if (startTime == null) {
      this.startTime = System.currentTimeMillis();
      getLogger().debug('Benchmarker: Starting ' + this.operation);
    }
  }

  private final Map<String, Benchmarker.TelemetryLogger> telemetries = new Map<String, Benchmarker.TelemetryLogger>();

  private TelemetryLogger activeTelemetryLogger;

  public TelemetryLogger startTelemetry() {
    return startTelemetry(operation);
  }

  private List<Exception> exceptions = new List<Exception>();
  public void error(Exception ex) {
    exceptions.add(ex);
  }

  public void complete() {
    System.debug('Benchmarker: Completing ' + this.operation);
    AppLogger logger = null;
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
    if (this.stop()) {
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

  public TelemetryLogger startTelemetry(String componentName) {
    start();
    return startTelemetry(componentName, null);
  }

  public TelemetryLogger startTelemetry(String componentName, string context) {
    String key = componentName + '-' + (String.isNotBlank(context) ? '-' + context : '');
    activeTelemetryLogger = telemetries.get(key);
    if (activeTelemetryLogger == null) {
      activeTelemetryLogger = new TelemetryLogger(this, componentName, context);
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
      AppLogger.sendTelemetry(buildTelemetryKey('Error', context), 1, durationMs);
    }

    public void logGeneralCall() {
      bm.stop();
      Long durationMs = bm.getDuration();
      AppLogger.sendTelemetry(buildTelemetryKey('Call', context), 1, durationMs);
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
        AppLogger.sendTelemetry(buildTelemetryKey(eventType, context), count, durationMs);
      }
    }
  }

  public Boolean stop() {
    // it's more efficient to guard here against repeated calls to stop(),
    // so it's possible to call stop() multiple times safely, for example
    // in both catch and finally blocks, without affecting the endTime.
    if (this.endTime == null) {
      this.endTime = System.currentTimeMillis();
      getLogger().debug('Benchmarker: Completed ' + this.operation);
      return true;
    }
    return false;
  }

  public void report() {
    if (this.startTime == null) {
      getLogger().debug('Benchmarker: ' + this.operation + ' - No start time recorded');
      return;
    }
    calculateDuration(true);
  }

  Long calculateDuration(Boolean logDuration) {
    if (this.endTime == null) {
      Long elapsed = System.currentTimeMillis() - this.startTime;
      if (logDuration) {
        getLogger()
          .debug(
            'Benchmarker: ' +
              this.operation +
              ' - Still running, elapsed: ' +
              elapsed.toString() +
              'ms'
          );
      }
      return elapsed;
    }

    Long duration = this.endTime - this.startTime;
    if (logDuration) {
      getLogger()
        .debug('Benchmarker: ' + this.operation + ' completed in ' + duration.toString() + 'ms');
    }
    return duration;
  }

  public Long getDuration() {
    // we can safely call it several times
    start();
    return calculateDuration(false);
  }
}
