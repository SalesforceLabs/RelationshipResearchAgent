// SchemaData stores all information we need about the DB schema and other
// related information.  Specifically, we extract this information once and then
// cache it, possibly using PlatformCache.  We then use the extracted metadata
// to perform SOSL searches while using generated statements, tailored to the DB
// schema.  Caching the schema saves lots of APEX resources since we can assume
// that the schema changes rarely if ever.
public without sharing class SchemaData implements CacheProvider.ValueProvider {
  // Cacheable schema.
  public class SchemaTableData {
    public String apiName;
    public String label;
    public List<String> nameFields;
    public List<String> phoneFields;
    public List<String> emailFields;
    // todo: add relationships
  }

  public List<SchemaTableData> schemaObjects;

  public Object compute() {
    this.schemaObjects = getSchemaObjectsWithNames(false);
    return this;
  }

  private Boolean hasData() {
    return schemaObjects != null && !schemaObjects.isEmpty();
  }

  public Boolean restoreFromCache(Object cache) {
    if (!(cache instanceof SchemaData)) {
      return false;
    }

    SchemaData d = (SchemaData) cache;
    this.schemaObjects = d.schemaObjects;
    this.soslFindReturn = d.soslFindReturn;
    return hasData();
  }

  private List<SchemaTableData> getSchema() {
    if (!hasData()) {
      compute();
    }

    return schemaObjects;
  }

  // caching SOSL clause to return field data (e.g. schema-dependent)
  private String soslFindReturn = '';

  // ToDo:
  public String buildFindSOSL(String collectedTokens) {
    if (String.isEmpty(collectedTokens)) {
      return '';
    }

    final String findReturn = buildFindReturnSOSL();
    if (String.isBlank(findReturn)) {
      return null;
    }

    String soslQuery = 'FIND \'' + collectedTokens + '\' IN NAME FIELDS RETURNING ' + findReturn;
    return soslQuery;
  }

  private String buildFindReturnSOSL() {
    if (!String.isBlank(soslFindReturn)) {
      return soslFindReturn;
    }

    List<SchemaTableData> cachedData = this.getSchema();
    soslFindReturn = '';

    for (SchemaTableData tableData : cachedData) {
      if (soslFindReturn.length() > 0) {
        soslFindReturn += ',';
      }

      soslFindReturn += tableData.apiName + '(Id';

      for (String nameField : tableData.nameFields) {
        soslFindReturn += ',' + nameField;
      }

      for (String nameField : tableData.phoneFields) {
        soslFindReturn += ',' + nameField;
      }

      for (String nameField : tableData.emailFields) {
        soslFindReturn += ',' + nameField;
      }

      // todo: add phone and email
      soslFindReturn += ')';
    }

    return soslFindReturn;
  }

  private static final String cacheKeySchemaData = 'SchemaData';

  public static SchemaData getCachedSchemaData() {
    SchemaData schemaData = new SchemaData();
    CacheProvider.populate(schemaData, cacheKeySchemaData);
    return schemaData;
  }

  // dump schema informtion into debug logs.
  static void debugObject(Schema.DescribeSObjectResult describeResult) {
    Map<String, Object> describeInfo = new Map<String, Object>{
      'Name' => describeResult.getName(),
      'Label' => describeResult.getLabel(),
      'LabelPlural' => describeResult.getLabelPlural(),
      'APIName' => describeResult.getName(),
      'Custom' => describeResult.isCustom(),
      'Queryable' => describeResult.isQueryable(),
      'Searchable' => describeResult.isSearchable(),
      'Creatable' => describeResult.isCreateable(),
      'Deletable' => describeResult.isDeletable(),
      'Updatable' => describeResult.isUpdateable(),
      'FeedEnabled' => describeResult.isFeedEnabled(),
      'Mergeable' => describeResult.isMergeable(),
      'Undeletable' => describeResult.isUndeletable(),
      'DeprecatedAndHidden' => describeResult.isDeprecatedAndHidden(),
      'KeyPrefix' => describeResult.getKeyPrefix()
    };
    String jsonOutput = JSON.serializePretty(describeInfo);
    System.debug('Collected searchable object info: ' + jsonOutput);
  }

  // We only care about customer-facing objects, which we can search.
  static Boolean isCustomerFacing(Schema.DescribeSObjectResult d) {
    // isQueryable() is defined per user, so we ignore it here,
    // as we'll want to cache the results for all users in the org.
    if (!d.isSearchable())
      return false;
    if (d.isCustomSetting())
      return false;
    String name = d.getName().toLowerCase();
    if (d.isCustom()) {
      // custom objects always have a Name
      if (name.startsWith('apex') || name.contains('history') || name.contains('log'))
        return false;
      if (name.startsWith('knowledge__'))
        return false;
      if (name.contains('share') || name.contains('feed') || name.contains('tag'))
        return false;
      debugObject(d);
      return true;
    }

    // for standard objects, we only look for predefined entities.
    return name == 'lead' || name == 'account' || name == 'contact';
  }

  // caching results of Schema.getGlobalDescribe in transaction
  static Map<String, Schema.SObjectType> allObjectsCache;

  static Map<String, Schema.SObjectType> getAllObjects() {
    if (allObjectsCache == null) {
      // we only want to execute this call once per transaction
      allObjectsCache = Schema.getGlobalDescribe();
    }
    return allObjectsCache;
  }

  // Collect schema information for all objects we're working with.
  // This method retrieves schema and then extracts fields we're interested in.
  // We do not cache full schema; particularly we ignore all possible
  // field-level security, unless checkUserAccess parameter is passed.
  public static List<SchemaTableData> getSchemaObjectsWithNames(Boolean checkUserAccess) {
    List<SchemaTableData> result = new List<SchemaTableData>();
    Map<String, Schema.SObjectType> allObjects = getAllObjects();
    for (String objName : allObjects.keySet()) {
      try {
        Schema.DescribeSObjectResult objDesc = allObjects.get(objName).getDescribe();
        if (!isCustomerFacing(objDesc))
          continue; // Skip non-queryable and other objects
        if (checkUserAccess && !objDesc.isAccessible()) {
          continue;
        }
        Map<String, Schema.SObjectField> fields = objDesc.fields.getMap();

        List<String> foundNameFields = new List<String>();
        List<String> foundPhoneFields = new List<String>();
        List<String> foundEmailFields = new List<String>();
        for (String fieldName : fields.keySet()) {
          Schema.DescribeFieldResult field = fields.get(fieldName).getDescribe();
          if (checkUserAccess && !field.isAccessible()) {
            continue;
          }
          if (field.isNameField()) {
            foundNameFields.add(fieldName);
          } else {
            Schema.DisplayType type = field.getType();
            if (type == Schema.DisplayType.Phone) {
              foundPhoneFields.add(fieldName);
            } else if (type == Schema.DisplayType.Email) {
              foundEmailFields.add(fieldName);
            }
          }
        }

        if (!foundNameFields.isEmpty()) {
          SchemaTableData tableData = new SchemaTableData();
          tableData.apiName = objName;
          tableData.label = objDesc.getLabel();
          tableData.nameFields = foundNameFields;
          tableData.phoneFields = foundPhoneFields;
          tableData.emailFields = foundEmailFields;
          result.add(tableData);
        }
      } catch (Exception e) {
        // Ignore inaccessible or problematic objects
        System.debug('Error with object ' + objName + ': ' + e.getMessage());
      }
    }

    return result;
  }
}
