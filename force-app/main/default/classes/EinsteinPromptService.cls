// A generic service class for executing Einstein Prompt Templates.
//
// This class abstracts the boilerplate code required to call the
// ConnectApi.EinsteinLLM class, providing a simpler and more reusable
// interface.
public with sharing class EinsteinPromptService {
  public interface Executor {
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation run(
      String templateApiName,
      ConnectApi.EinsteinPromptTemplateGenerationsInput cfg
    );
  }

  // Default implementation delegates to ConnectApi.EinsteinLLM
  private class LiveExecutor implements Executor {
    public ConnectApi.EinsteinPromptTemplateGenerationsRepresentation run(
      String templateApiName,
      ConnectApi.EinsteinPromptTemplateGenerationsInput cfg
    ) {
      return ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateApiName, cfg);
    }
  }

  // This class would ideally be visible only to MockExecutor, however Apex does
  // not allow this constraint to be expressed since namespaces aren't supported
  // and nested classes beyond a depth of 1 are not permitted.
  private class MockCallRecord {
    public String promptId;
    public List<List<String>> calledInputs = new List<List<String>>();
  }

  /**
   * Minimal mock executor for EinsteinPromptService.
   * - Map prompt template API name -> raw text body to return
   * - Captures each call and its input params for assertions
   */
  public class MockExecutor implements EinsteinPromptService.Executor {
    private final Map<String, String> results = new Map<String, String>();
    public final List<MockCallRecord> calls = new List<MockCallRecord>();
    private String defaultResults = '[]';

    public void setResults(String promptId, String rawResult) {
      results.put(promptId == null ? null : promptId.toLowerCase(), rawResult);
    }

    public void setResultsEmptyArray(String promptId) {
      setResults(promptId, '[]');
    }

    public void setDefaultResults(String defaultResults) {
      this.defaultResults = defaultResults;
    }

    public ConnectApi.EinsteinPromptTemplateGenerationsRepresentation run(
      String templateApiName,
      ConnectApi.EinsteinPromptTemplateGenerationsInput cfg
    ) {
      MockCallRecord rec = new MockCallRecord();
      rec.promptId = templateApiName;

      if (cfg != null && cfg.inputParams != null) {
        for (String k : cfg.inputParams.keySet()) {
          // store as <name, stringified value> "tuples", preserving order
          rec.calledInputs.add(new List<String>{ k, String.valueOf(cfg.inputParams.get(k).value) });
        }
      }
      calls.add(rec);

      String key = (templateApiName == null) ? null : templateApiName.toLowerCase();
      String body = results.containsKey(key) ? results.get(key) : defaultResults;

      ConnectApi.EinsteinLLMGenerationItemOutput item = new ConnectApi.EinsteinLLMGenerationItemOutput();
      item.text = body;

      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation out = new ConnectApi.EinsteinPromptTemplateGenerationsRepresentation();
      out.generations = new List<ConnectApi.EinsteinLLMGenerationItemOutput>{ item };
      return out;
    }
  }

  /* A static that points at the real thing in prod. */
  private static Executor executor = new LiveExecutor();

  @TestVisible
  public static void setExecutorForTest(Executor mock) {
    executor = (mock == null) ? new LiveExecutor() : mock;
  }

  public class PromptExecutionException extends Exception {
  }

  // The core method to execute a prompt template with all possible
  // configurations.
  public static EinsteinPromptResponse prompt(EinsteinPromptRequest request) {
    if (request == null || !request.isValid()) {
      throw new PromptExecutionException('Prompt request is null or invalid.');
    }

    ConnectApi.EinsteinPromptTemplateGenerationsInput config = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
    config.inputParams = request.inputParams;
    config.isPreview = request.isPreview;

    config.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
    config.additionalConfig.applicationName = request.applicationName;

    System.debug('Running prompt "' + request.templateApiName + '" with input parameters:');
    System.debug(request.inputParams);

    try {
      ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput = executor.run(
        request.templateApiName,
        config
      );
      return EinsteinPromptResponse.fromGenerationOutput(generationsOutput);
    } catch (ConnectApi.ConnectApiException e) {
      System.debug(
        System.LoggingLevel.ERROR,
        'Error executing Einstein prompt template "' +
          request.templateApiName +
          '". Status: ' +
          e.getErrorCode() +
          ', Message: ' +
          e.getMessage()
      );

      throw e;
    }
  }
  private class RunFlowInputs {
    final Map<String, Object> unwrappedInputs = new Map<String, Object>();
    public void add(String key, Object value) {
      String unwrappedKey = key;
      if (key.startsWith('Input:')) {
        unwrappedKey = key.substring('Input:'.length());
      }
      unwrappedInputs.put(unwrappedKey, value);
    }
  }

  // executes a prompt within a Flow context
  public static EinsteinPromptResponse runWithFlow(EinsteinPromptRequest request) {
    RunFlowInputs inputs = new RunFlowInputs();
    Map<String, Object> unwrappedInputs = new Map<String, Object>();
    for (String key : request.inputParams.keySet()) {
      inputs.add(key, request.inputParams.get(key).value);
    }
    return executePromptWithFlow(request.templateApiName, inputs);
  }

  // Convenience overload. Executes a prompt within a Flow context,
  // and also unwraps the input keys by stripping any "Input:" prefix.
  public static EinsteinPromptResponse runWithFlow(
    String templateApiName,
    Map<String, Object> inputParams
  ) {
    RunFlowInputs inputs = new RunFlowInputs();
    for (String key : inputParams.keySet()) {
      inputs.add(key, inputParams.get(key));
    }
    return executePromptWithFlow(templateApiName, inputs);
  }

  static EinsteinPromptResponse executePromptWithFlow(
    String templateApiName,
    RunFlowInputs inputs
  ) {
    Flow.Interview flow = Flow.Interview.createInterview(templateApiName, inputs.unwrappedInputs);
    flow.start();
    return EinsteinPromptResponse.fromFlowInterview(flow);
  }

  // Convenience overload. Executes a prompt with a ConnectApi.WrappedValue map
  // as input.
  public static EinsteinPromptResponse prompt(
    String templateApiName,
    Map<String, ConnectApi.WrappedValue> inputParams
  ) {
    EinsteinPromptRequest r = new EinsteinPromptRequest(templateApiName).withInputs(inputParams);
    return prompt(r);
  }

  // Convenience overload. Executes a prompt with a simple Map<String, Object>
  // as input.
  public static EinsteinPromptResponse prompt(
    String templateApiName,
    Map<String, Object> inputParams
  ) {
    EinsteinPromptRequest r = new EinsteinPromptRequest(templateApiName).withInputs(inputParams);
    return prompt(r);
  }

  public static List<Object> promptListSafe(
    String templateApiName,
    Map<String, Object> inputParams
  ) {
    try {
      EinsteinPromptRequest req = new EinsteinPromptRequest(templateApiName)
        .withInputs(inputParams);
      return prompt(req).getJsonList();
    } catch (Exception e) {
      return new List<Object>();
    }
  }
}
