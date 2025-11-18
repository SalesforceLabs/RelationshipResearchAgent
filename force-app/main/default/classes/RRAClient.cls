public with sharing class RRAClient {
  @AuraEnabled(cacheable=false)
  public static String createRelationships(
    String recordId,
    Boolean useDeepWebSearch,
    Boolean useRecordContext,
    Boolean isNewResearch
  ) {
    ICrmReferentialEntity targetEntity = CrmReferentialEntityResolver.resolveById(recordId);

    System.debug('Creating relationships for target entity: ' + targetEntity.serialize());

    System.debug('useDeepWebSearch:');
    System.debug(useDeepWebSearch);
    System.debug('useRecordContext:');
    System.debug(useRecordContext);

    RRARelationships__c rraRecord = CrmDatabaseSelectors.getRraRecord(
      targetEntity.getId(),
      targetEntity.getSobjectType()
    );

    RelationshipInsightsEnvelope insights = RelationshipInsightsService.getInsights(
      targetEntity,
      useDeepWebSearch,
      useRecordContext,
      isNewResearch,
      rraRecord
    );
    return RelationshipInsightsPersister.persist(insights, rraRecord);
  }

  // aura enabled + cacheable means that no DML/write operation can take place here
  // prompt engine execution is considered a DML even when not writing data
  @AuraEnabled(cacheable=true)
  public static String getRelationships(String recordId) {
    ICrmReferentialEntity entity;
    try {
      entity = CrmReferentialEntityResolver.resolveById(recordId);
    } catch (Exception e) {
      System.debug('Error resolving record ID: ' + recordId);
      System.debug(e.getMessage());
      return '[]';
    }

    String objectApiName = entity.getSobjectType();
    System.debug(
      String.format(
        'Fetching relationship data for recordId={0} ({1})',
        new List<String>{ recordId, objectApiName }
      )
    );

    RRARelationships__c record = CrmDatabaseSelectors.getRraRecord(recordId, objectApiName);

    if (record == null) {
      System.debug('no RRARelationships__c found');
      return '[]';
    }

    String jsonString = record.RelationshipJson__c;
    if (String.isBlank(jsonString)) {
      System.debug('RRARelationships__c.RelationshipJson__c is blank');
      return '[]';
    }

    String result = JSON.serialize(record);

    return result;
  }

  @AuraEnabled(cacheable=false)
  public static String confirmCrmMatch(String recordId, String entityUuid) {
    ICrmReferentialEntity entity = CrmReferentialEntityResolver.resolveById(recordId);
    String objectApiName = entity.getSobjectType();

    System.debug('Confirming CRM match for recordId=' + recordId + ', entityUuid=' + entityUuid);

    RRARelationships__c rraRecord = CrmDatabaseSelectors.getRraRecord(recordId, objectApiName);

    if (rraRecord == null || String.isBlank(rraRecord.RelationshipJson__c)) {
      throw new AuraHandledException('No relationship data found for this record');
    }

    RelationshipInsightsEnvelope envelope;
    try {
      envelope = (RelationshipInsightsEnvelope) JSON.deserialize(
        rraRecord.RelationshipJson__c,
        RelationshipInsightsEnvelope.class
      );
    } catch (Exception e) {
      System.debug('Error parsing relationship JSON: ' + e.getMessage());
      throw new AuraHandledException('Failed to parse relationship data: ' + e.getMessage());
    }

    if (envelope.relatedEntities == null) {
      throw new AuraHandledException('No related entities found in relationship data');
    }

    for (RelationshipInsightsEnvelope.RelatedEntity relatedEntity : envelope.relatedEntities) {
      if (relatedEntity.uuid != entityUuid) {
        continue;
      }

      relatedEntity.isCrmConfirmed = true;
      System.debug('Confirmed match for entity UUID: ' + entityUuid);

      rraRecord.RelationshipJson__c = envelope.serialize();
      try {
        update rraRecord;
      } catch (Exception e) {
        System.debug('Error updating record: ' + e.getMessage());
        throw new AuraHandledException('Failed to save confirmation: ' + e.getMessage());
      }

      return JSON.serialize(
        new Map<String, Object>{
          'success' => true,
          'message' => 'CRM match confirmed successfully'
        }
      );
    }

    throw new AuraHandledException('Entity not found in relationship data: ' + entityUuid);
  }
}
