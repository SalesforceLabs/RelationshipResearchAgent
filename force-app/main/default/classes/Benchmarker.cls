public with sharing class Benchmarker {
  private static Long getCurrentTimeMillis() {
    return System.currentTimeMillis();
  }
  // initialized at construction time, but then we can reset it with start()
  private Long startTime = getCurrentTimeMillis();
  // null until stop() is called
  private Long endTime = null;
  private String operation;

  public String getOperation() {
    return this.operation;
  }

  private RRALoggerFacade logger = null;

  public RRALoggerFacade getLogger() {
    if (this.logger == null) {
      // default app logger, do not start a scenario.
      this.logger = new RRALoggerFacade();
    }
    return this.logger;
  }

  public Benchmarker(String operationName) {
    this.operation = operationName;
  }

  Boolean started = false;
  public void start() {
    if (!this.started) {
      this.started = true;
      this.startTime = getCurrentTimeMillis();
      getLogger().debug('Benchmarker: Starting ' + this.operation);
    }
  }

  public Boolean stop() {
    // it's more efficient to guard here against repeated calls to stop(),
    // so it's possible to call stop() multiple times safely, for example
    // in both catch and finally blocks, without affecting the endTime.
    if (this.endTime == null) {
      this.endTime = getCurrentTimeMillis();
      getLogger().debug('Benchmarker: Completed ' + this.operation);
      return true;
    }
    return false;
  }

  public Long getDuration() {
    return (this.endTime ?? getCurrentTimeMillis()) - this.startTime;
  }
}
