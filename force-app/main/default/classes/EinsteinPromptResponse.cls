public with sharing class EinsteinPromptResponse {
  private String outputText;
  private Map<Type, Object> parsedJsonCache = new Map<Type, Object>();

  // Static utility methods for parsing JSON responses from LLMs.
  // ----------------------------------------------------------------------
  // LLM models often wrap the response in a Markdown code block (e.g. ```json
  // ... ```), even when a clear instruction is given not to do so. This regex
  // is used to strip the markdown fence before attempting to parse, and thus
  // prevent easily avoidable errors.
  //
  // Note that this logic only strips the fenced block if it surrounds the
  // *entire* output, and does NOT remove inline backticks or inner code
  // blocks inside string values.
  //
  // EXPLANATION
  // -----------
  // (?s)              - DOTALL so '.' matches newlines
  // ^                 - start-of-string (after trim)
  // ```(?:json)?\s*\R - opening fence, optional 'json', newline
  // ([\s\S]*?)        - lazy capture of everything
  // \R```$            - newline + closing fence at very end
  private static final Pattern fence = Pattern.compile(
    '(?s)^```(?:json)?\\s*\\R([\\s\\S]*?)\\R```$'
  );

  // Some LLMs (e.g. GPT-3.5, Claude, Gemini) may add explanation outside the fenced code,
  // so we need to locate the first fenced block anywhere in the text.
  //
  // Fallback: First JSON object or array, greedy match so we don't have
  // to match brackets. ``` fence seems to be working pretty well, we do not
  // need to match beyond that, and there will be only one block of json
  // returned per call.
  private static final Pattern jsonFallbackPattern = Pattern.compile(
    '(?s)```(?:json)?\\s*\\R([\\s\\S]*)\\R```'
  );

  private static Boolean isLikelyJson(String text) {
    if (String.isBlank(text)) {
      return false;
    }

    text = text.trim();
    return (text.startsWith('{') && text.endsWith('}')) ||
      (text.startsWith('[') && text.endsWith(']'));
  }

  // Unfences Markdown code block if present and returns inner JSON payload
  public static String unfenceJson(String body) {
    if (String.isBlank(body)) {
      return null;
    }

    Matcher m = fence.matcher(body.trim());
    if (m.matches()) {
      String s = m.group(1).trim();
      if (isLikelyJson(s)) {
        return s;
      }
    }

    Matcher fallbackMatcher = jsonFallbackPattern.matcher(body);
    if (fallbackMatcher.find()) {
      String s = fallbackMatcher.group(1).trim();
      if (isLikelyJson(s)) {
        return s;
      }
    }

    if (isLikelyJson(body)) {
      return body.trim();
    }

    // This handles cases where LLM adds conversational text before/after JSON
    String extracted = extractFirstJsonFromText(body);
    if (String.isNotBlank(extracted) && isLikelyJson(extracted)) {
      System.debug(
        'Warning: Extracted JSON from conversational response. Prompt may need adjustment.'
      );
      return extracted;
    }

    return null;
  }

  // Extract first JSON array or object from text, handling nested structures
  // Prioritizes arrays since most LLM responses return JSON arrays
  private static String extractFirstJsonFromText(String text) {
    if (String.isBlank(text)) {
      return null;
    }

    // Try to find first JSON array (most common case for our use)
    Integer arrayStart = text.indexOf('[');
    if (arrayStart >= 0) {
      String extracted = extractBalancedJson(text, arrayStart, '[', ']');
      if (String.isNotBlank(extracted)) {
        return extracted;
      }
    }

    // Fallback: Try to find first JSON object
    Integer objectStart = text.indexOf('{');
    if (objectStart >= 0) {
      String extracted = extractBalancedJson(text, objectStart, '{', '}');
      if (String.isNotBlank(extracted)) {
        return extracted;
      }
    }

    return null;
  }

  // Extract balanced JSON structure starting from a given index
  private static String extractBalancedJson(
    String text,
    Integer startIndex,
    String openChar,
    String closeChar
  ) {
    if (startIndex < 0 || startIndex >= text.length()) {
      return null;
    }

    Integer depth = 0;
    Integer jsonStart = startIndex;
    Boolean inString = false;
    Boolean escaped = false;

    for (Integer i = startIndex; i < text.length(); i++) {
      String currentChar = text.substring(i, i + 1);

      // Handle string boundaries and escaping
      if (currentChar == '\\' && !escaped) {
        escaped = true;
        continue;
      }

      if (currentChar == '"' && !escaped) {
        inString = !inString;
      }

      escaped = false;

      // Only count brackets outside of strings
      if (!inString) {
        if (currentChar == openChar) {
          depth++;
        } else if (currentChar == closeChar) {
          depth--;
          if (depth == 0) {
            // Found matching closing bracket
            return text.substring(jsonStart, i + 1);
          }
        }
      }
    }

    return null;
  }

  public static Object parseJson(String body, Type apexType) {
    if (String.isBlank(body)) {
      return null;
    }

    String jsonText = unfenceJson(body);
    if (String.isBlank(jsonText)) {
      return null;
    }

    try {
      if (apexType == null) {
        return JSON.deserializeUntyped(jsonText);
      } else {
        return JSON.deserialize(jsonText, apexType);
      }
    } catch (Exception e) {
      System.debug(System.LoggingLevel.ERROR, 'Failed to parse JSON: ' + e.getMessage());
      return null;
    }
  }

  public static Object parseJson(String body) {
    return parseJson(body, null);
  }

  public class PromptResponseException extends Exception {
  }

  public static EinsteinPromptResponse fromGenerationOutput(
    ConnectApi.EinsteinPromptTemplateGenerationsRepresentation generationsOutput
  ) {
    if (
      generationsOutput == null ||
      generationsOutput.generations == null ||
      generationsOutput.generations.isEmpty()
    ) {
      throw new PromptResponseException('No generations returned from the prompt template.');
    }

    if (generationsOutput.generations.size() > 1) {
      System.debug(
        System.LoggingLevel.WARN,
        'Multiple generations returned but only one response for the first will be created.'
      );
    }

    return new EinsteinPromptResponse(generationsOutput.generations[0]);
  }
  public static EinsteinPromptResponse fromFlowInterview(Flow.Interview flowInterview) {
    String responseText = (String) flowInterview.getVariableValue('responseText');
    if (responseText == null || String.isBlank(responseText)) {
      throw new PromptResponseException('No responseText variable found in the Flow Interview.');
    }
    return new EinsteinPromptResponse(responseText);
  }

  public EinsteinPromptResponse(ConnectApi.EinsteinLLMGenerationItemOutput output) {
    this.outputText = output == null ? null : output.text;
  }
  public EinsteinPromptResponse(String responseText) {
    this.outputText = responseText;
  }

  /** The raw text returned by the LLM (always present). */
  public String getText() {
    return outputText;
  }

  public Object getJson() {
    return getJson(null);
  }

  public Object getJson(Type apexType) {
    if (!parsedJsonCache.containsKey(apexType)) {
      String text = getText();
      if (String.isBlank(text)) {
        parsedJsonCache.put(apexType, null);
      } else {
        Object parsed = parseJson(text, apexType);
        parsedJsonCache.put(apexType, parsed);
      }
    }

    return parsedJsonCache.get(apexType);
  }

  public List<Object> getJsonList() {
    Object json = getJson();
    if (json == null) {
      return new List<Object>();
    }

    if (!(json instanceof List<Object>)) {
      System.debug(System.LoggingLevel.ERROR, 'Response is not a list of objects');
      return new List<Object>();
    }

    return (List<Object>) json;
  }
}
