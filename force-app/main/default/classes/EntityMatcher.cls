public with sharing class EntityMatcher {
  public final static string PROMPT_ENTITIES_DATACLOUD_SEARCH = 'RRA_EntitiesDatacloudSearch';
  // The following two constants are here due to an Apex limitation that
  // prevents nested classes from having their own static properties.
  // --
  // The name of the prompt template used to resolve entities.
  public final static String PROMPT_TEMPLATE_NAME = 'RRA_EntityMatcher';
  // Maximum number of matches to process in a single batch.
  public final static Integer MAX_MATCHES_BATCH = 500;

  public enum EntityMatcherMode {
    SOSL_ONLY, // SOSL search only
    DATACLOUD_ONLY, // Datacloud only, error in DC aborts the process
    DATACLOUD_AND_SOSL, // Datacloud then SOSL, error in DC aborts the process
    DATACLOUD_AND_SOSL_FALLBACK, // Datacloud then SOSL, error in DC continues with SOSL
    DATACLOUD_FALLBACK_SOSL // Datacloud only, unless error in DC -> continues with SOSL
  }

  public class EntityMatcherSettings implements CacheProvider.ValueProvider {
    public EntityMatcherMode mode;

    public EntityMatcherSettings() {
      this.mode = EntityMatcherMode.DATACLOUD_AND_SOSL;
    }

    public EntityMatcherSettings(EntityMatcherMode mode) {
      this.mode = mode;
    }

    public Object compute() {
      return mode;
    }

    public Boolean restoreFromCache(Object cache) {
      if (!(cache instanceof EntityMatcherMode)) {
        return false;
      }
      this.mode = (EntityMatcherMode) cache;
      return true;
    }
  }

  // A name is matched to an entity in database with the following steps:
  //
  // 1. We execute SOSL search for one or more entities, with an optional
  // LLM callout step to get all synonims for the tokens (eg Microsoft->MSFT).
  //
  // 2. SOSL search is not confined to Accounts/Contacts, but is executed
  // against all possible relevant objects in the database, including
  // custom objects (may require further tweaking/development).
  //
  // 3. Extracted data is supplied to LLM along with list of original
  // names to match and get confidence scores.
  //
  // 4. We currently use the best match only, as long as the confidence
  // score is high enough. The confidence score is arbitrary set to 68/100
  // (see implementation in RelationshipInsightsService).
  //
  // The matching process is implemented to be used with APEX flows, which would
  // batch up to 200 records. With batch resolutions, as long as the batch
  // conditions are satisfied (eg SOSL call is not too large etc), we use 1 SOSL
  // call and N+1 LLM calls for N distinct names: one call each to get synonims
  // via LLM, and one call to perform cross-matching at the end.  However, the
  // current matching process for POC is less efficient as we loop through
  // relationships individually. To leverage APEX flows, we need to move the
  // records from JSON in RRARelationships into separate records in a table
  // designed specifically for names resolution (eg with name as the primary
  // key), and then use flow there. This is outside POC.
  public class EntityInfo implements ICrmReferentialEntity {
    @InvocableVariable
    public String id; // Can be entity id from SSOT, eg. "SFDC-12345"
    @InvocableVariable
    public String objectTypeName; // API name, eg Account - do we need it?
    @InvocableVariable
    public String objectTypeLabel;
    @InvocableVariable
    public String name;
    @InvocableVariable
    public String phone;
    @InvocableVariable
    public String email;
    @InvocableVariable
    public String accountId; // optional but if exists it's CRM ID
    @InvocableVariable
    public String contactId; // optional but if exists it's CRM ID
    @InvocableVariable
    public String note; // matching notes, if any
    @InvocableVariable
    public string description; // not necessarily matching, can contain additional data. from SSOT
    @InvocableVariable
    public string title;

    // We have seen that DataCloud can return scores beyond 1.0, so we keep them as Double.
    // I have not been able to locate documentation on score ranges.
    // https://engineering.salesforce.com/how-data-cloud-hybrid-search-combines-keyword-and-vector-retrieval-to-elevate-the-search-experience/
    // This article implies that the score is normalized, but in reality it can go beyond 1.0.
    // The consumers should be careful as not to assume that the score is bounded with 1.0.
    @InvocableVariable
    public Double keywordSearchScore; // ranking metric from DataCloud, unbounded, may ignore name variants
    @InvocableVariable
    public Double confidenceScore; // from LLM, 0.0-1.0, considers name variants
    public String getSobjectType() {
      // This might need to be changed due to datacloud config. TBD.
      // Currently, relying on prompts to return correct objectTypeName from DataCloud searches.
      return objectTypeName;
    }
    public String getId() {
      // Note that objects coming from DataCloud might have different ID.
      return id;
    }
    public String getName() {
      return name;
    }
    public String serialize() {
      return JSON.serialize(this);
    }
    public string getAccountId() {
      return accountId;
    }
    public string getContactId() {
      return contactId;
    }
  }

  public class EntityInfoMatch {
    @InvocableVariable
    public EntityInfo info;
    @InvocableVariable
    public Double confidence;
  }

  public class MatchedEntity {
    @InvocableVariable
    public string term;
    @InvocableVariable
    public EntityInfoMatch[] matches;
  }

  // JSON representation returned by LLM
  class MatchedEntityJSON {
    public ID id;
    public String objectTypeName;
    public String objectTypeLabel;
    public String name;
    public String phone;
    public String email;
    public Double confidenceScore;
    public string inputName;
  }

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

  @TestVisible
  class Processor {
    private final SOSLTokenBuilder sosl = new SOSLTokenBuilder();
    private final List<MatchedEntity> listOfEntities = new List<MatchedEntity>();
    private final List<String> listOfNames = new List<String>();
    private final Map<String, MatchedEntity> termToEntityMap = new Map<String, MatchedEntity>();
    public EntityMatcherSettings settings = new EntityMatcherSettings();

    private String normalizeName(String name) {
      return String.isBlank(name) ? null : name.trim();
    }

    private String getNormalizedKey(String name) {
      return String.isBlank(name) ? null : name.trim().toLowerCase();
    }

    public void add(string name) {
      name = normalizeName(name);
      if (String.isBlank(name)) {
        System.debug('Skipping blank/empty name');
        return;
      }

      final String key = getNormalizedKey(name);
      // Shouldn't be the case if `name` is valid, but it _can_ return null.
      if (key == null) {
        System.debug('Skipping blank/empty name: ' + name);
        return;
      }

      if (termToEntityMap.containsKey(key)) {
        System.debug('Skipping duplicate name: ' + name + '. Already processed.');
        return;
      }

      sosl.addWithVariants(name);
      MatchedEntity entity = new MatchedEntity();
      entity.term = name;
      listOfEntities.add(entity);
      listOfNames.add(name);
      termToEntityMap.put(key, entity);
    }

    public ICrmReferentialEntity CrmContext { get; set; }

    public List<MatchedEntity> match() {
      List<EntityInfo> collectedEntities = new List<EntityInfo>();
      if (settings.mode == EntityMatcherMode.SOSL_ONLY) {
        collectMatchesWithSosl(sosl, collectedEntities);
        return match(collectedEntities);
      }
      // DataCloud mode
      try {
        EntityMatcherDataCloud.collectMatchesWithDataCloud(
          EntityMatcherDataCloud.getDataCloudSearchText(sosl, CrmContext),
          collectedEntities
        );
        System.debug(
          'DataCloud match for ' +
            JSON.serialize(listOfNames) +
            ': ' +
            JSON.serialize(collectedEntities)
        );
        // continue to SOSL collection only when explicitly specified.
        if (
          settings.mode != EntityMatcherMode.DATACLOUD_AND_SOSL &&
          settings.mode != EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK
        ) {
          return match(collectedEntities);
        }
      } catch (Exception ex) {
        // Data cloud search can fail for a variety of reasons, including
        // permissions, misconfiguration, or service issues. We log the error
        // and proceed with SOSL-based matching.
        System.debug('DataCloud search failed: ' + ex.getMessage());
        // rethrow only if no fallback is allowed.
        if (
          settings.mode != EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK &&
          settings.mode != EntityMatcherMode.DATACLOUD_FALLBACK_SOSL
        ) {
          throw ex;
        }
        // Note that `collectedEntities` is not necessarily empty here.
      }

      // Otherwise, combine with SOSL results.
      collectMatchesWithSosl(sosl, collectedEntities);
      return match(collectedEntities);
    }

    @TestVisible
    private List<MatchedEntity> match(List<EntityInfo> allMatches) {
      // null result means no query, likely no input tokens
      // if names are empty, we cannot match, abort early.
      if (allMatches == null || listOfNames.isEmpty()) {
        return null;
      }

      // if there are no matches, return the original list. No need to call LLM
      if (allMatches.isEmpty()) {
        return listOfEntities;
      }

      Map<String, Object> promptInput = new Map<String, Object>{
        'Input:Names' => JSON.serialize(listOfNames)
      };

      // Batch allMatches in fixed-size windows without mutating the input list
      Integer total = allMatches.size();

      Map<String, EntityMatcher.MatchedEntity> termToEntityMap = new Map<String, EntityMatcher.MatchedEntity>();
      for (EntityMatcher.MatchedEntity e : listOfEntities) {
        termToEntityMap.put(getNormalizedKey(e.term), e);
      }
      Map<String, EntityInfo> idToEntityMap = new Map<String, EntityInfo>();
      for (EntityInfo info : allMatches) {
        if (!String.isBlank(info.id)) {
          idToEntityMap.put(info.id, info);
        }
      }

      for (Integer start = 0; start < total; start += MAX_MATCHES_BATCH) {
        Integer endExclusive = Math.min(start + MAX_MATCHES_BATCH, total);

        // Build the current batch
        List<EntityMatcher.EntityInfo> matches = new List<EntityMatcher.EntityInfo>();
        for (Integer i = start; i < endExclusive; i++) {
          matches.add(allMatches[i]);
        }

        promptInput.put('Input:CRMData', JSON.serialize(matches));
        EinsteinPromptResponse response = EinsteinPromptService.prompt(
          EntityMatcher.PROMPT_TEMPLATE_NAME,
          promptInput
        );
        List<EntityMatcher.MatchedEntityJSON> resolvedEntities = (List<EntityMatcher.MatchedEntityJSON>) response.getJson(
          List<EntityMatcher.MatchedEntityJSON>.class
        );
        if (resolvedEntities == null || resolvedEntities.isEmpty()) {
          System.debug('LLM did not return any matches: skipping');
          continue;
        }

        for (EntityMatcher.MatchedEntityJSON item : resolvedEntities) {
          // We do not attempt to use the entity’s canonical name (item.name) as
          // a fallback key since it can misattach results if the LLM returns a
          // canonicalized value that wasn't in the original inputs; e.g. input
          // “MSFT” -> LLM returns name = "Microsoft Corporation".
          if (String.isBlank(item.inputName)) {
            System.debug('Skipping blank/empty input name');
            continue;
          }

          final String key = getNormalizedKey(item.inputName);
          if (!termToEntityMap.containsKey(key)) {
            // Should not be here, but logging and moving on.
            System.debug('term ' + item.inputName + ' is not present in the input');
            System.debug(JSON.serialize(item, true));
            continue;
          }

          // LLM model will also return empty entityinfo when there are no
          // matches Search term will be returned to indicate that the term has
          // been processed by LLM.
          //
          // To account for this, check item's ID. if it's empty, there' not a
          // valid match, so we just continue.
          if (String.isBlank(item.id)) {
            // This is normal situation: term has been considered but no
            // matches found. we do not need to log this unless debugging.
            continue;
          }
          EntityMatcher.EntityInfo info;
          if (!idToEntityMap.containsKey(item.id)) {
            System.debug('LLM returned entity ID that was not in the input: ' + item.id);
            System.debug(JSON.serialize(item, true));
            info = new EntityMatcher.EntityInfo();
            info.id = item.id;
          } else {
            info = idToEntityMap.get(item.id).clone();
          }
          info.objectTypeName = item.objectTypeName;
          info.objectTypeLabel = item.objectTypeLabel;
          info.name = item.name;
          info.phone = item.phone;
          info.email = item.email;
          info.confidenceScore = item.confidenceScore;

          EntityMatcher.EntityInfoMatch match = new EntityMatcher.EntityInfoMatch();
          match.info = info;
          match.confidence = item.confidenceScore;
          EntityMatcher.MatchedEntity entity = termToEntityMap.get(key);
          if (entity.matches == null) {
            entity.matches = new List<EntityMatcher.EntityInfoMatch>();
          }
          entity.matches.add(match);
        }
      }

      return listOfEntities;
    }
  }

  public class InputName {
    @InvocableVariable(required=true)
    public String name;
  }

  // Returns array of text data from the fields, eg "all phones", "all emails".
  private static List<String> extractFieldValues(SObject data, List<String> fields) {
    if (data == null || fields == null || fields.isEmpty()) {
      return null;
    }

    Set<String> seen = new Set<String>();
    List<String> values = new List<String>();

    for (String field : fields) {
      if (String.isBlank(field)) {
        continue;
      }

      Object raw;
      try {
        raw = data.get(field);
      } catch (Exception ex) {
        System.debug('unable to get field ' + field);
        System.debug(ex.getMessage());
        continue;
      }

      if (raw == null) {
        System.debug('skipping null field ' + field);
        continue;
      } else if (!(raw instanceof String)) {
        System.debug('skipping non-string field ' + field);
        continue;
      }

      String value = ((String) raw).trim();
      if (String.isBlank(value)) {
        System.debug('skipping blank value for field ' + field);
        continue;
      } else if (seen.contains(value)) {
        System.debug('skipping duplicate value ' + value + ' for field ' + field);
        continue;
      }

      seen.add(value);
      values.add(value);
    }

    return values.isEmpty() ? null : values;
  }

  private static String stringJoin(List<String> fields, String separator) {
    if (fields == null || fields.size() == 0) {
      return null;
    }

    return String.join(fields, separator);
  }

  public static MatchedEntity findMatchesSingle(String name) {
    return findMatchesSingle(name, EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK);
  }

  public static MatchedEntity findMatchesSingle(String name, EntityMatcherMode entityMatcherMode) {
    Processor p = new Processor();
    p.settings = new EntityMatcherSettings(entityMatcherMode);
    p.add(name);
    List<MatchedEntity> l = p.match();
    return (l == null || l.isEmpty()) ? null : l[0];
  }

  @InvocableMethod(label='Find matches in Salesforce')
  // @AuraEnabled(cacheable=false)
  public static List<MatchedEntity> findMatchesMulti(List<InputName> names) {
    if (names == null) {
      return null;
    }
    Processor p = new Processor();
    for (InputName snippet : names) {
      p.add(snippet.name);
    }
    return p.match();
  }

  public static List<MatchedEntity> findMatchesMulti(List<String> names) {
    if (names == null) {
      return null;
    }
    Processor p = new Processor();
    for (String name : names) {
      p.add(name);
    }
    return p.match();
  }

  private static void collectMatchesWithSosl(SOSLTokenBuilder collectSosl, List<EntityInfo> infos) {
    String soslTextQuery = collectSosl.collectedTokens;
    if (String.isBlank(soslTextQuery)) {
      System.debug('sosl query cannot be constructed');
      return;
    }

    SchemaData schemaData = SchemaData.getCachedSchemaData();

    for (;;) {
      String sosl = schemaData.buildFindSOSL(soslTextQuery);
      System.Debug(sosl);
      // Execute the SOSL query dynamically
      List<List<SObject>> queryResults = Search.query(sosl);
      System.Debug(queryResults);

      Integer idxData = 0;
      for (List<SObject> dataArray : queryResults) {
        if (dataArray != null && dataArray.size() > 0) {
          SchemaData.SchemaTableData d = schemaData.schemaObjects[idxData];
          String objectTypeName = d.apiName;
          String objectTypeLabel = d.label;
          for (SObject obj : dataArray) {
            EntityInfo newInfo = new EntityInfo();
            newInfo.objectTypeName = objectTypeName;
            newInfo.objectTypeLabel = objectTypeLabel;
            newInfo.id = obj.id.toString();
            newInfo.name = (String) obj.get(d.nameFields[0]);
            newInfo.phone = stringJoin(extractFieldValues(obj, d.phoneFields), ', ');
            newInfo.email = stringJoin(extractFieldValues(obj, d.emailFields), ', ');
            infos.add(newInfo);
          }
        }
        idxData++;
      }

      if (!collectSosl.moveNext()) {
        break;
      }

      soslTextQuery = collectSosl.collectedTokens;
    }
  }
}
