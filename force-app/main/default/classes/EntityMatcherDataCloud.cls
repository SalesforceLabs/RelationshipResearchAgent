public with sharing class EntityMatcherDataCloud {
  public final static string PROMPT_ENTITIES_DATACLOUD_SEARCH = 'RRA_EntitiesDatacloudSearch';

  class DataCloudEntityJSON {
    public String inputName; // input name that was searched for
    public String entityId;
    public String type;
    public String name;
    public String phone;
    public String email;
    public String accountId;
    public String contactId;
    public String note;
    public String description;
    public String title;
    public Double keywordSearchScore;
    public Double confidenceScore;
  }
  static Boolean DC_MATCH_RUN_FIRST_ONLY = false;
  public static void collectMatchesWithDataCloud(
    List<String> searchTexts,
    List<EntityMatcher.EntityInfo> infos
  ) {
    Set<String> seenIds = new Set<String>();
    // only one search text for now - "Provider rate exceeded" errors
    try {
      collectMatchesWithDataCloud(
        GetDataCloudFullSearchTerm(searchTexts, DC_MATCH_RUN_FIRST_ONLY),
        infos,
        seenIds
      );
    } catch (Exception ex) {
      if (DC_MATCH_RUN_FIRST_ONLY) {
        // no fallback - rethrow
        throw ex;
      }
      // fallback - try with the first search text only
      collectMatchesWithDataCloud(searchTexts[0], infos, seenIds);
    }
  }

  public static List<string> getDataCloudSearchText(
    SOSLTokenBuilder collectSosl,
    ICrmReferentialEntity crmContext
  ) {
    // todo: return better queries for DataCloud search, augmented with data
    // from CrmContext if available.
    // For extensibility, LLM call can be used to generate better queries.
    return new List<String>(collectSosl.getAllOriginalTokens());
  }

  static string GetDataCloudFullSearchTerm(List<string> searchTexts, Boolean firstOnly) {
    if (searchTexts == null || searchTexts.isEmpty()) {
      return null;
    }
    if (firstOnly) {
      return searchTexts[0];
    }
    List<String> quoted = new List<String>();

    for (String s : searchTexts) {
      if (s == null)
        continue;
      // Remove existing quotes
      String clean = s.replace('"', '').replace('\'', '');
      // Wrap in double quotes
      quoted.add('"' + clean + '"');
    }
    return String.join(searchTexts, ' OR ');
  }
  private static void collectMatchesWithDataCloud(
    String searchText,
    List<EntityMatcher.EntityInfo> infos,
    Set<String> seenIds
  ) {
    // looking for all variants of the name. This will give us better keywordSearchScore.
    Map<String, Object> promptInput = new Map<String, Object>{ 'Input:Text' => searchText };

    // DataCloud search prompts cannot be called directly in 258 orgs, so we use flow method.
    // Note that this requires a configured flow to be available in the target org.
    EinsteinPromptResponse response = EinsteinPromptService.flow(
      PROMPT_ENTITIES_DATACLOUD_SEARCH,
      promptInput
    );
    List<DataCloudEntityJSON> resolvedEntities = (List<DataCloudEntityJSON>) response.getJson(
      List<DataCloudEntityJSON>.class
    );
    if (resolvedEntities == null) {
      String flowError = response.getText();
      if (!String.isBlank(flowError)) {
        System.debug('DataCloud search flow returned error: ' + flowError);
        throw new FlowException(flowError);
      }
      System.debug('DataCloud search returned no results for: ' + searchText);
      return;
    }
    System.debug('output from DataCloud search:');
    System.debug(resolvedEntities);
    for (DataCloudEntityJSON item : resolvedEntities) {
      if (seenIds.contains(item.entityId)) {
        continue;
      }
      seenIds.add(item.entityId);
      EntityMatcher.EntityInfo info = new EntityMatcher.EntityInfo();
      info.id = item.entityId;
      info.objectTypeName = item.type;
      info.objectTypeLabel = 'Data Cloud ' + item.type;
      info.name = item.name;
      info.phone = item.phone;
      info.email = item.email;
      info.accountId = item.accountId;
      info.contactId = item.contactId;
      info.Note = item.note;
      info.Description = item.description;
      info.Title = item.title;
      info.keywordSearchScore = scoreToInteger(item.keywordSearchScore);
      info.confidenceScore = scoreToInteger(item.confidenceScore);
      // ignoring inputName for now
      infos.add(info);
    }
  }
  public static Integer scoreToInteger(Double score) {
    if (score == null || score <= 0) {
      return 0;
    }
    if (score < 1) {
      score *= 100;
    }
    if (score > 100) {
      return 100;
    }
    // special case: low scores with decimal part => 100%, e.g. 1.5 -> 100,
    // because indexes return such scores.
    if (score != Math.floor(score)) {
      return 100;
    }
    return Math.round(score);
  }
}
