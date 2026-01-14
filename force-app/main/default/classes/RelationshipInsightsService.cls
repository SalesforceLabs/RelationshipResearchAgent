public with sharing class RelationshipInsightsService {
  private static final RRADiagnostics diag = RRADiagnostics.getInstance();

  // The confidence is returned by model and we might need to adjust.
  // We do not want to take answers with small confidence. 68% is 1 sigma.
  public static final Integer MIN_CRM_MATCH_CONFIDENCE = 68;

  // total of 20 is allowed per txn, reserve 1 for target entity search
  // breaching this limit will trigger non-catchable apex exception "FATAL_ERROR|System.LimitException: Too many SOSL queries: 21"
  public static final Integer MAX_SOSL_WEB = 19;

  public static RelationshipInsightsEnvelope getInsights(
    ICrmReferentialEntity targetEntity,
    RRARelationships__c rraRecord,
    RRAClientOptions options
  ) {
    RRATelemetryClient telemetryClient = RRATelemetryClient.startTelemetry('getWebInsights');
    List<RelationshipInsightsEnvelope.RelatedEntity> webInsights = null;
    try {
      webInsights = getWebInsights(
        targetEntity,
        options.useDeepWebSearch,
        options.useRecordContext,
        options.parseEntityMatcherMode()
      );
    } catch (Exception ex) {
      telemetryClient.error(ex);
      throw ex;
    } finally {
      telemetryClient.complete(webInsights);
    }

    if (options.appendToExistingResearch) {
      webInsights = appendWebInsights(targetEntity, webInsights, rraRecord);
    }

    List<RelationshipInsightsEnvelope.RelatedEntity> crmInsights = getCrmInsights(
      targetEntity,
      options.parseEntityMatcherMode()
    );

    // Consolidate web and CRM insights to eliminate duplicates and enrich relationships
    List<RelationshipInsightsEnvelope.RelatedEntity> consolidated = consolidateCrossSourceInsights(
      crmInsights,
      webInsights
    );

    return RelationshipInsightsEnvelope.fromCrmAnchor(targetEntity, consolidated);
  }

  // additional web search terms to produce more relevant results (for simple search only)
  static final String DEFAULT_WEB_SEARCH_TERMS = 'business associates';

  public static List<RelationshipInsightsEnvelope.RelatedEntity> getWebInsights(
    ICrmReferentialEntity targetEntity,
    Boolean useDeepWebSearch,
    Boolean useRecordContext,
    EntityMatcher.EntityMatcherMode entityMatcherMode
  ) {
    List<RelationshipInsightsEnvelope.RelatedEntity> rels;
    // Extract custom keywords from record to enhance search relevance
    String recordContextSearchTerms = useRecordContext
      ? RecordWebSearchContext.extractKeywords(targetEntity)
      : '';
    if (useDeepWebSearch) {
      System.debug('Using Deep Web Research Engine for entity: ' + targetEntity.getName());
      String deepWebResults = DeepWebResearchEngine.run(targetEntity, recordContextSearchTerms);
      // use our routines to unfence JSON into objects.
      List<Object> deepWebData = (List<Object>) EinsteinPromptResponse.parseJson(deepWebResults);
      rels = RelationshipInsightsEnvelope.fromObjectList(
        deepWebData,
        RelationshipInsightsEnvelope.SOURCE_WEB
      );
      System.debug('Related entities from deep web research:');
    } else {
      System.debug('Using simple web search for entity: ' + targetEntity.getName());
      String searchSuffix = String.join(
        new List<String>{ DEFAULT_WEB_SEARCH_TERMS, recordContextSearchTerms },
        ' '
      );
      Map<String, Object> inputs = new Map<String, Object>();

      inputs.put('Input:SearchTarget', targetEntity.getName());
      inputs.put('Input:SearchTerms', targetEntity.getName() + ' ' + searchSuffix);

      final EinsteinPromptResponse response = EinsteinPromptService.prompt(
        RRAPromptTemplates.DEEP_WEB_RESEARCH_DISCOVERY,
        inputs
      );

      rels = RelationshipInsightsEnvelope.fromObjectList(
        response.getJsonList(),
        RelationshipInsightsEnvelope.SOURCE_WEB
      );
      System.debug('Related entities from web extraction:');
    }

    RelationshipInsightsEnvelope.dump(rels);
    matchAgainstCrmEntities(rels, entityMatcherMode);
    return rels;
  }

  public static List<RelationshipInsightsEnvelope.RelatedEntity> getCrmInsights(
    ICrmReferentialEntity targetEntity,
    EntityMatcher.EntityMatcherMode entityMatcherMode
  ) {
    // check if we have anything in CRM that matches the target entity name.
    final List<EntityMatcher.EntityInfoMatch> rawMatches = EntityMatcher.findMatchesSingle(
        targetEntity.getName(),
        entityMatcherMode
      )
      .matches;
    String excludeId = targetEntity.getId();
    CrmRelationshipInsightsPayloadAssembler asm = new CrmRelationshipInsightsPayloadAssembler();
    asm.addEntity(targetEntity);
    if (rawMatches != null) {
      for (EntityMatcher.EntityInfoMatch entityMatch : rawMatches) {
        asm.addEntity(entityMatch.info);
      }
    }
    // this adds CRM data from detected database Ids.
    asm.build();
    Integer foundSize = asm.size();
    if (foundSize == 0) {
      System.debug('getCrmInsights found no matching records for: ' + targetEntity.getName());
    } else {
      System.debug(
        'getCrmInsights found ' +
          foundSize.toString() +
          ' matching records for: ' +
          targetEntity.getName()
      );
    }
    if (asm.size() < 3) {
      // CRM data insufficient, add more recent records in hope of getting something useful.
      System.debug('getCrmInsights will get newest records to try to find more insights');
      asm.buildWithNewestRecords();
    }

    CrmRelationshipInsightsProcessor proc = new CrmRelationshipInsightsProcessor(targetEntity);
    RRATelemetryClient telemetryClient = RRATelemetryClient.startTelemetry('getCrmInsights');
    List<RelationshipInsightsEnvelope.RelatedEntity> insights = null;
    try {
      insights = proc.generateInsights(asm.getPayload());
    } catch (Exception ex) {
      telemetryClient.error(ex);
      throw ex;
    } finally {
      telemetryClient.complete(insights);
    }
    return insights;
  }

  private static void matchAgainstCrmEntities(
    List<RelationshipInsightsEnvelope.RelatedEntity> rels,
    EntityMatcher.EntityMatcherMode entityMatcherMode
  ) {
    Integer soslCount = 1;
    for (RelationshipInsightsEnvelope.RelatedEntity rel : rels) {
      if (soslCount > MAX_SOSL_WEB) {
        System.debug(LoggingLevel.WARN, 'Error: Max SOSL calls reached in matchAgainstCrmEntities');
        return;
      }

      soslCount += 1;

      if (rel == null) {
        System.debug('Skipping null related entity');
        continue;
      } else if (String.isBlank(rel.entityName)) {
        System.debug('Skipping related entity with empty name: ' + JSON.serialize(rel));
        continue;
      } else if (!String.isBlank(rel.recordId)) {
        System.debug('Skipping related entity already linked: ' + JSON.serialize(rel));
        continue;
      }

      // TODO: use findMatchesMulti to optimize.
      EntityMatcher.MatchedEntity matchedEntity = EntityMatcher.findMatchesSingle(
        rel.entityName,
        entityMatcherMode
      );
      if (matchedEntity == null || matchedEntity.matches == null) {
        System.debug('No CRM match found for: ' + rel.entityName);
        continue;
      }

      EntityMatcher.EntityInfoMatch bestMatch = findBestSObjectMatch(matchedEntity.matches, true);
      if (bestMatch == null) {
        System.debug('No CRM match found for: ' + rel.entityName);
        continue;
      } else if (bestMatch.info.id == null || bestMatch.info.objectTypeName == null) {
        System.debug('Match missing id or objectTypeName for: ' + rel.entityName);
        continue;
      }

      System.debug('CRM match: ' + rel.entityName + ' -> ' + bestMatch.info.name);

      rel.recordId = String.valueOf(bestMatch.info.id);
      rel.recordType = bestMatch.info.objectTypeName;
    }
  }

  private static EntityMatcher.EntityInfoMatch findBestSObjectMatch(
    List<EntityMatcher.EntityInfoMatch> data,
    Boolean maxConfidence
  ) {
    if (data == null || data.size() == 0) {
      return null;
    }

    EntityMatcher.EntityInfoMatch selected = data.get(0);
    if (!maxConfidence) {
      return selected;
    }

    for (EntityMatcher.EntityInfoMatch m : data) {
      if (m.confidence > selected.confidence) {
        selected = m;
      }
    }

    if (selected.confidence < MIN_CRM_MATCH_CONFIDENCE) {
      return null;
    }

    return selected;
  }

  private static List<RelationshipInsightsEnvelope.RelatedEntity> appendWebInsights(
    ICrmReferentialEntity targetEntity,
    List<RelationshipInsightsEnvelope.RelatedEntity> newWebInsights,
    RRARelationships__c rraRecord
  ) {
    if (rraRecord == null || String.isBlank(rraRecord.RelationshipJson__c)) {
      return newWebInsights;
    }

    String newInsightsJson = JSON.serialize(newWebInsights);

    Map<String, Object> inputs = new Map<String, Object>();
    inputs.put('Input:ExistingRelationships', rraRecord.RelationshipJson__c);
    inputs.put('Input:NewRelationships', newInsightsJson);

    RRADiagnostics.getInstance()
      .data.put(
        'ContinueResearch',
        new Map<String, Object>{
          'existingRelationships' => JSON.deserializeUntyped(rraRecord.RelationshipJson__c),
          'newRelationships' => JSON.deserializeUntyped(newInsightsJson)
        }
      );

    EinsteinPromptResponse response = EinsteinPromptService.prompt(
      RRAPromptTemplates.APPEND_RELATIONSHIPS,
      inputs
    );

    List<RelationshipInsightsEnvelope.RelatedEntity> webInsights = RelationshipInsightsEnvelope.fromObjectList(
      response.getJsonList(),
      RelationshipInsightsEnvelope.SOURCE_WEB
    );
    System.debug('Append web relationships: ' + JSON.serialize(webInsights));

    return webInsights;
  }

  private static List<RelationshipInsightsEnvelope.RelatedEntity> consolidateCrossSourceInsights(
    List<RelationshipInsightsEnvelope.RelatedEntity> crmInsights,
    List<RelationshipInsightsEnvelope.RelatedEntity> webInsights
  ) {
    if (
      (crmInsights == null || crmInsights.isEmpty()) &&
      (webInsights == null || webInsights.isEmpty())
    ) {
      return new List<RelationshipInsightsEnvelope.RelatedEntity>();
    }

    if (crmInsights == null || crmInsights.isEmpty()) {
      return webInsights;
    }

    if (webInsights == null || webInsights.isEmpty()) {
      return crmInsights;
    }

    String crmJson = JSON.serialize(crmInsights);
    String webJson = JSON.serialize(webInsights);

    RRADiagnostics.DiagnosticEntry entry = diag.get('CrossSourceConsolidation');
    entry.put('crmInsightsCount', crmInsights.size());
    entry.put('webInsightsCount', webInsights.size());
    entry.put('crmInsights', JSON.deserializeUntyped(crmJson));
    entry.put('webInsights', JSON.deserializeUntyped(webJson));

    Map<String, Object> inputs = new Map<String, Object>();
    inputs.put('Input:CrmRelationships', crmJson);
    inputs.put('Input:WebRelationships', webJson);

    EinsteinPromptResponse response = EinsteinPromptService.prompt(
      RRAPromptTemplates.CONSOLIDATE_CROSS_SOURCE_INSIGHTS,
      inputs
    );

    List<RelationshipInsightsEnvelope.RelatedEntity> consolidated = RelationshipInsightsEnvelope.fromObjectList(
      response.getJsonList(),
      null
    );

    diag.put('consolidatedCount', consolidated.size());
    diag.put('consolidatedInsights', JSON.deserializeUntyped(JSON.serialize(consolidated)));

    return consolidated;
  }
}
