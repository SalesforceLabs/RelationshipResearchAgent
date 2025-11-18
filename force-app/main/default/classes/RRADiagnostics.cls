public class RRADiagnostics {
  private static RRADiagnostics instance;
  public Map<String, Object> data;

  private RRADiagnostics() {
    this.data = new Map<String, Object>();
  }

  public static RRADiagnostics getInstance() {
    if (instance == null) {
      instance = new RRADiagnostics();
    }
    return instance;
  }

  public String toJson() {
    return JSON.serialize(data);
  }

  // Get or create diagnostic entry at key
  public DiagnosticEntry get(String key) {
    if (!this.data.containsKey(key)) {
      this.data.put(key, new Map<String, Object>());
    }
    return new DiagnosticEntry((Map<String, Object>) this.data.get(key));
  }

  // Put value at root level
  public void put(String key, Object value) {
    this.data.put(key, value);
  }

  // Wrapper class for easier nested diagnostics access
  public class DiagnosticEntry {
    private Map<String, Object> entryData;

    public DiagnosticEntry(Map<String, Object> data) {
      this.entryData = data;
    }

    public DiagnosticEntry get(String key) {
      if (!this.entryData.containsKey(key)) {
        this.entryData.put(key, new Map<String, Object>());
      }
      return new DiagnosticEntry((Map<String, Object>) this.entryData.get(key));
    }

    public void put(String key, Object value) {
      this.entryData.put(key, value);
    }
  }
}
