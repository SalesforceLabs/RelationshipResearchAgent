public with sharing class Benchmarker {
  private Long startTime;
  private Long endTime;
  private String operation;

  public Benchmarker(String operationName) {
    this.operation = operationName;
  }

  public void start() {
    this.startTime = System.currentTimeMillis();
    System.debug('Benchmarker: Starting ' + this.operation);
  }

  public void stop() {
    this.endTime = System.currentTimeMillis();
    System.debug('Benchmarker: Completed ' + this.operation);
  }

  public void report() {
    if (this.startTime == null) {
      System.debug('Benchmarker: ' + this.operation + ' - No start time recorded');
      return;
    }

    if (this.endTime == null) {
      System.debug(
        'Benchmarker: ' +
          this.operation +
          ' - Still running, elapsed: ' +
          (System.currentTimeMillis() - this.startTime) +
          'ms'
      );
      return;
    }

    Long duration = this.endTime - this.startTime;
    System.debug('Benchmarker: ' + this.operation + ' completed in ' + duration + 'ms');
  }

  public Long getDuration() {
    if (this.startTime == null || this.endTime == null) {
      return null;
    }
    return this.endTime - this.startTime;
  }
}
