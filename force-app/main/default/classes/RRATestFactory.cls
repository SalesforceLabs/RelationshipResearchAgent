public with sharing class RRATestFactory {
  private static Integer orgCounter = 1;
  private static Integer personCounter = 1;

  public static RelationshipInsightsEnvelope generateSyntheticDataEnvelope(
    ICrmReferentialEntity entity
  ) {
    RelationshipInsightsEnvelope envelope = new RelationshipInsightsEnvelope();
    envelope.anchorEntity = RelationshipInsightsEnvelope.anchorFromCrm(entity);

    // Generate 3-8 random relationships
    Integer count = Math.mod(Math.abs(Crypto.getRandomInteger()), 6) + 3;

    for (Integer i = 0; i < count; i++) {
      Boolean isOrg = Math.mod(Math.abs(Crypto.getRandomInteger()), 2) == 0;
      RelationshipInsightsEnvelope.RelatedEntity rel = isOrg
        ? generateOrgEntity()
        : generatePersonEntity();
      envelope.relatedEntities.add(rel);
    }

    return envelope;
  }

  private static RelationshipInsightsEnvelope.RelatedEntity generateOrgEntity() {
    RelationshipInsightsEnvelope.RelatedEntity rel = new RelationshipInsightsEnvelope.RelatedEntity();

    String testName = 'Test Org ' + orgCounter++;

    rel.uuid = String.valueOf(UUID.randomUUID());
    rel.entityName = testName;
    rel.canonicalName = testName;
    rel.entityType = 'Organization';
    rel.predicate = 'has a relationship with';
    rel.source = RelationshipInsightsEnvelope.SOURCE_WEB;
    rel.citation = 'Synthetic test data - timestamp: ' + System.now().format();
    rel.citationURL = 'https://example.com';
    rel.context = 'Synthetic relationship for testing';
    rel.confidenceScore = 0.8;
    rel.importanceScore = 0.7;
    rel.isCrmConfirmed = false;

    return rel;
  }

  private static RelationshipInsightsEnvelope.RelatedEntity generatePersonEntity() {
    RelationshipInsightsEnvelope.RelatedEntity rel = new RelationshipInsightsEnvelope.RelatedEntity();

    String testName = 'Test Person ' + personCounter++;

    rel.uuid = String.valueOf(UUID.randomUUID());
    rel.entityName = testName;
    rel.canonicalName = testName;
    rel.entityType = 'Person';
    rel.predicate = 'has a relationship with';
    rel.source = RelationshipInsightsEnvelope.SOURCE_WEB;
    rel.citation = 'Synthetic test data - timestamp: ' + System.now().format();
    rel.citationURL = 'https://example.com';
    rel.context = 'Synthetic relationship for testing';
    rel.confidenceScore = 0.8;
    rel.importanceScore = 0.7;
    rel.isCrmConfirmed = false;

    return rel;
  }
}
