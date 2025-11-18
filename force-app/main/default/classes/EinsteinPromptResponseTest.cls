@IsTest(SeeAllData=false)
public class EinsteinPromptResponseTest {
  // Helper method to create a mock EinsteinPromptResponse
  private static EinsteinPromptResponse createMockResponse(String text) {
    ConnectApi.EinsteinLLMGenerationItemOutput output = new ConnectApi.EinsteinLLMGenerationItemOutput();
    output.text = text;
    return new EinsteinPromptResponse(output);
  }

  @IsTest
  public static void testPlainJsonArray() {
    String jsonText = '[{"name":"Test","value":123}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    Assert.isNotNull(result, 'Should parse plain JSON array');
    Assert.isTrue(result instanceof List<Object>, 'Should return a list');

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should have one element');
  }

  @IsTest
  public static void testPlainJsonObject() {
    String jsonText = '{"name":"Test","value":123}';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    Assert.isNotNull(result, 'Should parse plain JSON object');
    Assert.isTrue(result instanceof Map<String, Object>, 'Should return a map');
  }

  @IsTest
  public static void testMarkdownFencedJson() {
    String jsonText = '```json\n[{"entityName":"Microsoft","entityType":"Organization"}]\n```';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract JSON from markdown fence');

    Map<String, Object> entity = (Map<String, Object>) resultList[0];
    Assert.areEqual('Microsoft', entity.get('entityName'), 'Should parse entity correctly');
  }

  @IsTest
  public static void testMarkdownFenceWithoutJsonTag() {
    String jsonText = '```\n[{"key":"value"}]\n```';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract JSON from markdown fence without json tag');
  }

  @IsTest
  public static void testConversationalTextBeforeJson() {
    String jsonText = 'Here is the data you requested:\n```json\n[{"name":"Test"}]\n```';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract JSON from conversational text');
  }

  @IsTest
  public static void testConversationalTextWithEmbeddedJson() {
    String jsonText = 'Based on my analysis, I found the following relationships: [{"entityName":"Apple","predicate":"Competitor of"}] which indicates...';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract embedded JSON from conversational text');

    Map<String, Object> entity = (Map<String, Object>) resultList[0];
    Assert.areEqual('Apple', entity.get('entityName'), 'Should parse embedded entity correctly');
  }

  @IsTest
  public static void testEscapedQuotesInJson() {
    String jsonText = '[{"description":"He said \\"hello\\" to me"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should handle escaped quotes');

    Map<String, Object> item = (Map<String, Object>) resultList[0];
    Assert.isTrue(
      ((String) item.get('description')).contains('hello'),
      'Should preserve escaped quotes in string'
    );
  }

  @IsTest
  public static void testNestedJsonStructures() {
    String jsonText = '[{"name":"Parent","children":[{"name":"Child1"},{"name":"Child2"}]}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should handle nested structures');

    Map<String, Object> parent = (Map<String, Object>) resultList[0];
    List<Object> children = (List<Object>) parent.get('children');
    Assert.areEqual(2, children.size(), 'Should parse nested arrays');
  }

  @IsTest
  public static void testJsonWithBracketsInStrings() {
    String jsonText = '[{"description":"See [this link] for more {info}"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should handle brackets in string values');

    Map<String, Object> item = (Map<String, Object>) resultList[0];
    String description = (String) item.get('description');
    Assert.isTrue(description.contains('[this link]'), 'Should preserve brackets in strings');
    Assert.isTrue(description.contains('{info}'), 'Should preserve braces in strings');
  }

  @IsTest
  public static void testEmptyArray() {
    String jsonText = '[]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(0, resultList.size(), 'Should return empty list for empty array');
  }

  @IsTest
  public static void testEmptyResponse() {
    String jsonText = '';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    Assert.isNull(result, 'Should return null for empty response');

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(0, resultList.size(), 'getJsonList should return empty list for null JSON');
  }

  @IsTest
  public static void testNullResponse() {
    String jsonText = null;
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    Assert.isNull(result, 'Should return null for null response');
  }

  @IsTest
  public static void testInvalidJson() {
    String jsonText = 'This is not JSON at all';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    Assert.isNull(result, 'Should return null for invalid JSON');

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(0, resultList.size(), 'getJsonList should return empty list for invalid JSON');
  }

  @IsTest
  public static void testMalformedJson() {
    String jsonText = '[{"name":"Test",}]'; // Extra comma
    EinsteinPromptResponse response = createMockResponse(jsonText);

    Object result = response.getJson();
    // Malformed JSON should fail to parse
    Assert.isNull(result, 'Should return null for malformed JSON');
  }

  @IsTest
  public static void testJsonListWithNonListResponse() {
    String jsonText = '{"name":"Test"}'; // Object, not array
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(0, resultList.size(), 'getJsonList should return empty list for non-list JSON');
  }

  @IsTest
  public static void testMultipleJsonBlocksInText() {
    // Should extract the first JSON array it finds
    String jsonText = 'Here are two arrays: [{"first":"array"}] and [{"second":"array"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract first JSON array');

    Map<String, Object> item = (Map<String, Object>) resultList[0];
    Assert.areEqual('array', item.get('first'), 'Should extract the first array');
  }

  @IsTest
  public static void testJsonWithNewlinesAndWhitespace() {
    String jsonText = '[\n  {\n    "name": "Test",\n    "value": 123\n  }\n]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should handle JSON with newlines and whitespace');
  }

  @IsTest
  public static void testRealWorldConversationalResponse() {
    String jsonText =
      'I will analyze the relationships and return the refined results.\n\n' +
      '```json\n' +
      '[\n' +
      '  {\n' +
      '    "entityName": "Microsoft Corporation",\n' +
      '    "entityType": "Organization",\n' +
      '    "predicate": "Competitor of",\n' +
      '    "context": "Direct competitor in cloud services and enterprise software",\n' +
      '    "citation": "Industry analysis report",\n' +
      '    "citationURL": "https://example.com",\n' +
      '    "confidenceScore": 0.95,\n' +
      '    "importanceScore": 0.9\n' +
      '  }\n' +
      ']\n' +
      '```\n\n' +
      'This relationship has high confidence based on multiple sources.';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should extract JSON from real-world conversational response');

    Map<String, Object> entity = (Map<String, Object>) resultList[0];
    Assert.areEqual('Microsoft Corporation', entity.get('entityName'));
    Assert.areEqual('Organization', entity.get('entityType'));
    Assert.areEqual('Competitor of', entity.get('predicate'));
    Assert.areEqual(0.95, entity.get('confidenceScore'));
  }

  @IsTest
  public static void testCachedParsing() {
    String jsonText = '[{"name":"Test"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    // Call getJson() multiple times - should use cached result
    Object result1 = response.getJson();
    Object result2 = response.getJson();

    Assert.areEqual(result1, result2, 'Should return same cached result');
  }

  @IsTest
  public static void testUnfenceJsonStaticMethod() {
    // Test the static unfenceJson method directly
    String fencedJson = '```json\n[{"test":"value"}]\n```';
    String unfenced = EinsteinPromptResponse.unfenceJson(fencedJson);

    Assert.isNotNull(unfenced, 'Should unfence JSON');
    Assert.isTrue(unfenced.startsWith('['), 'Should start with array bracket');
    Assert.isTrue(unfenced.endsWith(']'), 'Should end with array bracket');
  }

  @IsTest
  public static void testParseJsonStaticMethod() {
    // Test the static parseJson method directly
    String jsonText = '{"name":"Test"}';
    Object result = EinsteinPromptResponse.parseJson(jsonText);

    Assert.isNotNull(result, 'Should parse JSON');
    Assert.isTrue(result instanceof Map<String, Object>, 'Should return map');
  }

  @IsTest
  public static void testParseJsonWithType() {
    // Test parsing with a specific Apex type
    String jsonText = '[{"name":"Test"}]';
    // When passing null as type, it should use deserializeUntyped
    Object result = EinsteinPromptResponse.parseJson(jsonText, null);

    Assert.isNotNull(result, 'Should parse JSON with type');
    Assert.isTrue(result instanceof List<Object>, 'Should return a list');
  }

  @IsTest
  public static void testComplexEscapedJson() {
    // Test JSON with multiple escape sequences
    String jsonText = '[{"path":"C:\\\\Users\\\\test","quote":"\\"quoted\\"","newline":"line1\\nline2"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should handle complex escape sequences');

    Map<String, Object> item = (Map<String, Object>) resultList[0];
    Assert.isTrue(
      ((String) item.get('path')).contains('Users'),
      'Should parse path with escaped backslashes'
    );
  }

  @IsTest
  public static void testJsonArrayPrioritization() {
    // When both object and array are present, array should be extracted first
    String jsonText = 'Result: {"meta":"data"} [{"actual":"result"}]';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(1, resultList.size(), 'Should prioritize array extraction');

    Map<String, Object> item = (Map<String, Object>) resultList[0];
    Assert.areEqual('result', item.get('actual'), 'Should extract array, not object');
  }

  @IsTest
  public static void testExtremelyLongJson() {
    // Test with a large JSON structure
    List<String> items = new List<String>();
    for (Integer i = 0; i < 100; i++) {
      items.add('{"id":' + i + ',"name":"Item' + i + '"}');
    }
    String jsonText = '[' + String.join(items, ',') + ']';
    EinsteinPromptResponse response = createMockResponse(jsonText);

    List<Object> resultList = response.getJsonList();
    Assert.areEqual(100, resultList.size(), 'Should handle large JSON arrays');
  }
}

