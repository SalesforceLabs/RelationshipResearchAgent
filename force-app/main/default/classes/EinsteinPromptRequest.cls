public with sharing class EinsteinPromptRequest {
  // The application name is required by the
  // ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate method. Prompt
  // execution will fail if absent or invalid. Example error:
  //
  //   ConnectApi.ConnectApiException: Application Name is a required field
  //   providing existing registered ai applicaton
  public String applicationName = 'PromptTemplateGenerationsInvocable';

  public String templateApiName;
  public Map<String, ConnectApi.WrappedValue> inputParams;
  public Boolean isPreview = false;

  public EinsteinPromptRequest(String templateApiName) {
    this.templateApiName = templateApiName;
  }

  // Validates the request. Ensures that the application name, template API name
  // are not blank, and either no input parameters are present or at least one
  // input parameter is provided.
  public Boolean isValid() {
    return !String.isBlank(applicationName) &&
      !String.isBlank(templateApiName) &&
      // It's reasonable to assume that a prompt might not require any
      // user-supplied input parameters at all (e.g. static prompt that executes
      // a web search or RAG query.)
      (inputParams == null || !inputParams.isEmpty());
  }

  // Fluent interface for building the request
  public EinsteinPromptRequest withPreview(Boolean p) {
    this.isPreview = p;
    return this;
  }

  public EinsteinPromptRequest withApp(String app) {
    this.applicationName = app;
    return this;
  }

  public EinsteinPromptRequest withInputs(Map<String, Object> p) {
    Map<String, ConnectApi.WrappedValue> wrapped = new Map<String, ConnectApi.WrappedValue>();
    // Throws exception if p is null by design.
    for (String key : p.keySet()) {
      ConnectApi.WrappedValue wv = new ConnectApi.WrappedValue();
      wv.value = p.get(key);
      wrapped.put(key, wv);
    }

    return withInputs(wrapped);
  }

  public EinsteinPromptRequest withInputs(Map<String, ConnectApi.WrappedValue> p) {
    this.inputParams = p;
    return this;
  }
}
