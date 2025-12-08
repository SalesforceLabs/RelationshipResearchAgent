public with sharing class CrmRelationshipInsightsProcessor {
  private static final Integer MAX_CHARS_PER_CHUNK = 80000; // ~20k tokens

  private ICrmReferentialEntity targetEntity;
  private final CrmDataDtos.CrmDataPayload payload;

  public CrmRelationshipInsightsProcessor(ICrmReferentialEntity entity) {
    this.targetEntity = entity;
  }

  // Extracts and ranks relationship insights from CRM data using a multi-step
  // prompt-based pipeline.
  //
  // Process Overview:
  //
  // 1. Chunking:
  //    Splits the serialized CRM payload into size-limited JSON chunks to
  //    conform to prompt input limits.
  //
  // 2. Extraction:
  //    For each chunk, sends a prompt to an LLM to identify potential
  //    relationships involving the target entity.
  //
  // 3. Ranking:
  //    Aggregates all extracted relationships and passes them to another prompt
  //    to consolidate and rank them as insights.
  //
  // Returns:
  // A list of ranked relationship insight objects, ready for further processing
  // or persistence.
  // Returns ranked RelatedEntity items (not legacy relationships).
  public List<RelationshipInsightsEnvelope.RelatedEntity> generateInsights(
    CrmDataDtos.CrmDataPayload payload
  ) {
    List<String> chunks = JsonChunker.chunkJsonArray(payload.toObjectList(), MAX_CHARS_PER_CHUNK);

    if (chunks.isEmpty()) {
      System.debug('No chunks to process');
      return new List<RelationshipInsightsEnvelope.RelatedEntity>();
    }

    // 1st pass: extract relationships
    List<RelationshipInsightsEnvelope.RelatedEntity> extracted = new List<RelationshipInsightsEnvelope.RelatedEntity>();
    for (String chunk : chunks) {
      extracted.addAll(extract(chunk));
    }

    System.debug('Identified the following related entities:');
    RelationshipInsightsEnvelope.dump(extracted);

    // 2nd pass: rank/consolidate
    List<RelationshipInsightsEnvelope.RelatedEntity> insights = rank(extracted);

    System.debug('Ranked related entities:');
    RelationshipInsightsEnvelope.dump(insights);

    return insights;
  }

  private List<RelationshipInsightsEnvelope.RelatedEntity> extract(String chunk) {
    Map<String, Object> params = new Map<String, Object>();
    params.put('Input:TargetEntity', (Object) targetEntity.serialize());
    params.put('Input:CRMData', (Object) chunk);

    EinsteinPromptResponse response = EinsteinPromptService.prompt(
      RRAPromptTemplates.ENTITIES_FROM_CRM,
      params
    );
    return RelationshipInsightsEnvelope.fromObjectList(
      response.getJsonList(),
      RelationshipInsightsEnvelope.SOURCE_CRM
    );
  }

  private List<RelationshipInsightsEnvelope.RelatedEntity> rank(
    List<RelationshipInsightsEnvelope.RelatedEntity> relationships
  ) {
    if (relationships == null || relationships.isEmpty()) {
      System.debug('No extracted relationships to rank');
      return new List<RelationshipInsightsEnvelope.RelatedEntity>();
    }

    Map<String, Object> params = new Map<String, Object>();
    params.put('Input:TargetEntity', (Object) targetEntity.serialize());
    params.put('Input:ExtractedInsights', (Object) JSON.serialize(relationships));

    final EinsteinPromptResponse response = EinsteinPromptService.prompt(
      RRAPromptTemplates.CONSOLIDATE_INSIGHTS,
      params
    );
    return RelationshipInsightsEnvelope.fromObjectList(
      response.getJsonList(),
      RelationshipInsightsEnvelope.SOURCE_CRM
    );
  }
}
