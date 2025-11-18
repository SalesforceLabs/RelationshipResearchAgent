/*
 * Utility class responsible solely for validating and persisting
 * relationship insights data.
 */
public with sharing class RelationshipInsightsPersister {
  /**
   * Validate payload & upsert.
   * Returns the JSON string of the persisted insights envelope.
   */
  public static String persist(
    RelationshipInsightsEnvelope envelope,
    RRARelationships__c rraRecord
  ) {
    if (envelope == null || !envelope.isValid()) {
      System.debug(LoggingLevel.WARN, 'Relationship insights envelope is null or invalid');
      return '';
    }

    String upsertString = envelope.serialize();
    RelationshipInsightsEnvelope.AnchorEntity ae = envelope.anchorEntity;

    if (rraRecord == null) {
      RRARelationships__c newObj = new RRARelationships__c();
      newObj.RecordId__c = ae.recordId;
      newObj.RecordType__c = ae.recordType;
      newObj.RelationshipJson__c = upsertString;
      newObj.Diagnostics__c = RRADiagnostics.getInstance().toJson();

      try {
        insert newObj;
        System.debug('Created RRA relationships object:');
        System.debug(newObj);
      } catch (Exception e) {
        System.debug('Error creating RRA relationships object:');
        System.debug(e.getMessage());
      }

      return upsertString;
    }

    rraRecord.RelationshipJson__c = upsertString;
    rraRecord.Diagnostics__c = RRADiagnostics.getInstance().toJson();

    try {
      update rraRecord;

      System.debug('Updated existing RRA relationships object:');
      System.debug(rraRecord);

      return upsertString;
    } catch (Exception e) {
      System.debug('Error updating RRA relationships object:');
      System.debug(e.getMessage());
    }

    return '';
  }
}
