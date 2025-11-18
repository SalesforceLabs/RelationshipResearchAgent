// The envelope centers all insights on a single, explicitly defined anchor
// entity, eliminating ambiguity about subject direction, and enabling
// deterministic de-duplication and validation.  It also simplifies
// persistence/retrieval by bundling metadata (for now, only schema version)
// with the anchor entity and its related entities.  This reduces downstream
// graph anomalies from flipped predicates and aligns the data model with how
// insights are queried, displayed, and matched to CRM records.
public with sharing class RelationshipInsightsEnvelope {
  public String schemaVersion { get; set; }
  public AnchorEntity anchorEntity { get; set; }
  public List<RelatedEntity> relatedEntities { get; set; }

  public static AnchorEntity anchorFromCrm(ICrmReferentialEntity e) {
    AnchorEntity a = new AnchorEntity();
    a.entityName = e.getName();
    a.canonicalName = e.getName();
    a.recordId = e.getId();
    a.recordType = e.getSobjectType();
    a.entityType = a.recordType == null ? null : a.recordType.toLowerCase();
    return a;
  }

  public static final String SOURCE_WEB = 'web';
  public static final String SOURCE_CRM = 'crm';

  public static RelatedEntity relatedFromObject(Object item, String source) {
    if (!(item instanceof Map<String, Object>)) {
      return null;
    }

    Map<String, Object> m = (Map<String, Object>) item;
    RelatedEntity r = new RelatedEntity();

    r.uuid = String.valueOf(UUID.randomUUID());
    r.entityName = (String) m.get('entityName');
    r.canonicalName = (String) m.get('canonicalName');
    r.entityType = (String) m.get('entityType');
    r.predicate = (String) m.get('predicate');
    r.context = (String) m.get('context');
    r.citation = (String) m.get('citation');
    r.citationURL = (String) m.get('citationURL');
    r.confidenceScore = (Decimal) m.get('confidenceScore');
    r.importanceScore = (Decimal) m.get('importanceScore');

    Object rid = m.get('recordId');
    r.recordId = (rid == null) ? null : String.valueOf(rid);
    r.recordType = (String) m.get('recordType');
    r.isCrmConfirmed = (Boolean) m.get('isCrmConfirmed');
    r.source = source;

    return r.isValid() ? r : null;
  }

  // Debugging utility to dump a list of RelatedEntity instances.
  public static void dump(List<RelatedEntity> rels) {
    for (Integer i = 0; i < rels.size(); i++) {
      System.debug('#' + i + ': ' + JSON.serialize(rels[i]));
    }
  }

  // Factory method to parse a list of generic objects into RelatedEntity
  // instances.
  public static List<RelatedEntity> fromObjectList(List<Object> items, String source) {
    if (items == null || items.isEmpty()) {
      return new List<RelatedEntity>();
    }

    List<RelatedEntity> result = new List<RelatedEntity>();

    for (Object item : items) {
      try {
        RelatedEntity rel = relatedFromObject(item, source);
        if (rel != null) {
          result.add(rel);
        }
      } catch (Exception e) {
        System.debug(
          System.LoggingLevel.ERROR,
          'Unexpected error while parsing RelatedEntity: ' + e.getMessage()
        );
      }
    }

    return normalize(result);
  }

  public static List<RelatedEntity> normalize(List<RelatedEntity> related) {
    Set<String> seen = new Set<String>();
    List<RelatedEntity> deduped = new List<RelationshipInsightsEnvelope.RelatedEntity>();

    for (RelatedEntity r : related) {
      if (r == null || !r.isValid()) {
        continue;
      }

      String key = (r.entityName + '||' + r.predicate).toLowerCase();
      if (seen.add(key)) {
        deduped.add(r);
      }
    }

    return deduped;
  }

  public RelationshipInsightsEnvelope() {
    this.schemaVersion = '2';
    this.relatedEntities = new List<RelatedEntity>();
  }

  // Build an envelope from a CRM entity plus related list
  public static RelationshipInsightsEnvelope fromCrmAnchor(
    ICrmReferentialEntity anchor,
    List<RelatedEntity> related
  ) {
    RelationshipInsightsEnvelope env = new RelationshipInsightsEnvelope();
    env.anchorEntity = anchorFromCrm(anchor);

    if (related != null) {
      related = normalize(related);

      for (RelatedEntity r : related) {
        env.relatedEntities.add(r);
      }
    }

    return env;
  }

  public Boolean isValid() {
    if (this.anchorEntity == null || !this.anchorEntity.isValid()) {
      return false;
    } else if (this.relatedEntities == null) {
      return false;
    } else if (this.schemaVersion != '2') {
      return false;
    }

    for (RelatedEntity r : this.relatedEntities) {
      if (r == null || !r.isValid()) {
        return false;
      }
    }

    return true;
  }

  public String serialize() {
    return JSON.serialize(this);
  }

  public class AnchorEntity {
    public String entityName;
    public String canonicalName;
    public String entityType;
    public String recordId;
    public String recordType;

    public Boolean isValid() {
      // Is there a scenario where an anchor entity is valid if it lacks a
      // record (id, type)?  Keeping it permissive for now.
      return !String.isBlank(entityName) && !String.isBlank(entityType);
    }
  }

  public class RelatedEntity {
    public String uuid;
    public String entityName;
    public String canonicalName;
    public String entityType;
    public String predicate;
    public String recordId;
    public String recordType;
    public Boolean isCrmConfirmed;
    public String source;
    public String citation;
    public String citationURL;
    public String context;

    public Decimal confidenceScore;
    public Decimal importanceScore;

    public Boolean isValid() {
      return !String.isBlank(entityName) &&
        !String.isBlank(entityType) &&
        !String.isBlank(predicate) &&
        !String.isBlank(citation);
    }
  }
}
