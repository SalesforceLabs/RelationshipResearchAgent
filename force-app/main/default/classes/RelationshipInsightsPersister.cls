/*
 * Utility class responsible solely for validating and persisting
 * relationship insights data.
 */
public with sharing class RelationshipInsightsPersister {
  private static final RRADiagnostics diag = RRADiagnostics.getInstance();

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

      try {
        insert newObj;
        System.debug('Created RRA relationships object:');
        System.debug(newObj);
      } catch (Exception e) {
        System.debug('Error creating RRA relationships object:');
        System.debug(e.getMessage());
      }

      persistDiagnostics(newObj.Id);

      return upsertString;
    }

    rraRecord.RelationshipJson__c = upsertString;

    try {
      update rraRecord;

      System.debug('Updated existing RRA relationships object:');
      System.debug(rraRecord);
    } catch (Exception e) {
      System.debug('Error updating RRA relationships object:');
      System.debug(e.getMessage());

      return '';
    }

    persistDiagnostics(rraRecord.Id);
    return upsertString;
  }

  private static void persistDiagnostics(Id recordId) {
    try {
      rraDiagnosticsPersister.saveJSON(recordId, diag.toJson());
    } catch (RRADiagnosticsPersister.StorageException e) {
      System.debug(System.LoggingLevel.ERROR, 'Error: Persisting RRA diagnostics failed');
    }
  }
}
