/**
 * DeepWebResearchEngine - Experimental class for advanced web research techniques
 *
 * Implements a 3-stage research workflow for comprehensive entity investigation:
 *
 * Stage 1 (Entity Discovery): Generates 5 search term sets covering overview, relationships, news, business,
 * and industry angles. Uses dynamic search generation to identify related entities from multiple perspectives,
 * extracts entity names from responses, and calculates confidence/strength scores for discovered relationships.
 *
 * Stage 2 (Deep Relationship Mapping): Takes top 5 discovered entities and creates 2-3 targeted searches per
 * entity, focusing on leadership/ownership connections, business partnerships/investments, and competitive
 * relationships. This will both add new l1 entites and augment the context of l1 relationships discovered in stage 1.
 *
 * Stage 3 (Validation & Synthesis): Consolidates and deduplicates relationship data from previous stages,
 * applies confidence scoring and filtering, then synthesizes all findings into final RRA-format JSON output.
 */
public with sharing class DeepWebResearchEngine {
  private static final RRADiagnostics diag = RRADiagnostics.getInstance();

  private static final List<String> DISCOVERY_SEARCH_TOPICS = new List<String>{
    'Company Overview & Leadership',
    'Partnerships & Investors',
    'Recent News & Executives',
    'Business Model & Customers',
    'Competitors & Market Position',
    'Record Context Search'
  };

  public class ResearchStage {
    public String stageName;
    public String promptTemplate;
    public String stageOutput;
    public List<String> resultEntities;

    public ResearchStage(String name, String template) {
      this.stageName = name;
      this.promptTemplate = template;
      this.resultEntities = new List<String>();
    }
  }

  public static String run(ICrmReferentialEntity targetEntity, String recordContextSearchTerms) {
    String entityName = targetEntity.getName();
    Benchmarker benchmark = new Benchmarker('DeepWebResearch for ' + entityName);
    benchmark.start();
    try {
      ResearchContext context = new ResearchContext(entityName, recordContextSearchTerms);

      ResearchStage discovery = executeDiscoveryStage(context);
      context.addStageResult(discovery);

      ResearchStage relationships = executeDeepRelationshipStage(context);
      context.addStageResult(relationships);

      ResearchStage synthesis = executeValidationSynthesisStage(context);
      context.addStageResult(synthesis);

      benchmark.stop();
      benchmark.report();
      return synthesis.stageOutput;
    } catch (Exception e) {
      benchmark.stop();
      benchmark.report();
      System.debug(LoggingLevel.ERROR, 'Deep research failed: ' + e.getMessage());
      return '[]';
    }
  }

  public class ResearchContext {
    public String targetEntity;
    public String recordContextSearchTerms;
    public Map<String, Object> globalContext;
    public Set<String> resultEntities;

    public ResearchContext(String target, String contextTerms) {
      this.targetEntity = target;
      this.recordContextSearchTerms = contextTerms;
      this.globalContext = new Map<String, Object>();
      this.resultEntities = new Set<String>();
      this.globalContext.put('TargetEntity', target);
    }

    public void addStageResult(ResearchStage stage) {
      this.globalContext.put(stage.stageName + '_Output', stage.stageOutput);
      this.resultEntities.addAll(stage.resultEntities);
    }
  }

  private static ResearchStage executeDiscoveryStage(ResearchContext context) {
    ResearchStage stage = new ResearchStage(
      'Stage1',
      RRAPromptTemplates.DEEP_WEB_RESEARCH_DISCOVERY
    );

    List<String> discoverySearchTerms = generateDiscoverySearchTerms(context.targetEntity);

    // Add record context search if available
    if (String.isNotBlank(context.recordContextSearchTerms)) {
      discoverySearchTerms.add(context.targetEntity + ' ' + context.recordContextSearchTerms);
    }

    List<String> allResults = new List<String>();
    Set<String> allEntities = new Set<String>();
    Integer searchCount = 0;

    RRADiagnostics.DiagnosticEntry stage1Diag = diag.get('DeepWebResearch').get('Stage1');
    stage1Diag.put('searchTarget', context.targetEntity);
    stage1Diag.put('recordContext', context.recordContextSearchTerms);

    Integer searchIndex = 1;
    for (String discoverySearchTerm : discoverySearchTerms) {
      Map<String, Object> searchInputs = new Map<String, Object>();
      searchInputs.put('Input:SearchTarget', context.targetEntity);
      searchInputs.put('Input:SearchTerms', discoverySearchTerm);

      Map<String, Object> stageContext = new Map<String, Object>(context.globalContext);
      stageContext.putAll(searchInputs);

      String searchKey = 'DiscoverySearch' + searchIndex;
      RRADiagnostics.DiagnosticEntry searchDiag = stage1Diag.get(searchKey);
      searchDiag.put('searchTopic', DISCOVERY_SEARCH_TOPICS[searchIndex - 1]);
      searchDiag.put('searchTerms', discoverySearchTerm);

      EinsteinPromptResponse response = EinsteinPromptService.prompt(
        stage.promptTemplate,
        stageContext
      );

      // Use getJsonList() which handles conversational responses and extraction
      List<Object> entityList = response.getJsonList();

      if (entityList != null && !entityList.isEmpty()) {
        allResults.add(JSON.serialize(entityList));
        searchDiag.put('searchResults', entityList);
        Integer entityCount = 0;

        // Extract entity names directly from parsed data
        for (Object entityObj : entityList) {
          Map<String, Object> entityMap = (Map<String, Object>) entityObj;
          String entityName = (String) entityMap.get('entityName');
          if (String.isNotBlank(entityName)) {
            allEntities.add(entityName);
            entityCount++;
          }
        }
        searchCount++;

        System.debug(
          'Discovery search "' + discoverySearchTerm + '" found ' + entityCount + ' entities'
        );
      }
      searchIndex++;
    }

    stage.stageOutput = aggregateStageResults(allResults);
    stage.resultEntities = new List<String>(allEntities);

    System.debug(
      'Discovery Stage completed. Found ' +
        stage.resultEntities.size() +
        ' entities from ' +
        searchCount +
        ' searches'
    );
    return stage;
  }

  private static ResearchStage executeDeepRelationshipStage(ResearchContext context) {
    ResearchStage stage = new ResearchStage(
      'Stage2',
      RRAPromptTemplates.DEEP_WEB_RESEARCH_DISCOVERY
    );

    // Focus on top entities with multiple search angles per entity
    // TODO: select top entities by importance score instead of discovery order
    List<String> topEntities = getTopEntitiesFromContext(context, 5);
    List<String> searchTerms = generateDeepRelationshipSearchTerms(
      context.targetEntity,
      topEntities
    );
    List<String> allResults = new List<String>();
    Set<String> allEntities = new Set<String>();
    Integer searchCount = 0;

    RRADiagnostics.DiagnosticEntry stage2Diag = diag.get('DeepWebResearch').get('Stage2');
    stage2Diag.put('searchTarget', context.targetEntity);
    stage2Diag.put('topEntities', topEntities);

    Integer searchIndex = 1;
    for (String searchTerm : searchTerms) {
      Map<String, Object> searchInputs = new Map<String, Object>();
      searchInputs.put('Input:SearchTarget', context.targetEntity);
      searchInputs.put('Input:SearchTerms', searchTerm);

      Map<String, Object> stageContext = new Map<String, Object>(context.globalContext);
      stageContext.putAll(searchInputs);

      String searchKey = 'RelationshipSearch' + searchIndex;
      RRADiagnostics.DiagnosticEntry searchDiag = stage2Diag.get(searchKey);
      searchDiag.put('searchTerms', searchTerm);

      EinsteinPromptResponse response = EinsteinPromptService.prompt(
        stage.promptTemplate,
        stageContext
      );

      // Use getJsonList() which handles conversational responses and extraction
      List<Object> entityList = response.getJsonList();
      if (entityList != null && !entityList.isEmpty()) {
        allResults.add(JSON.serialize(entityList));
        searchDiag.put('searchResults', entityList);
        // Extract entity names directly from parsed data
        Integer entityCount = 0;
        for (Object entityObj : entityList) {
          Map<String, Object> entityMap = (Map<String, Object>) entityObj;
          String entityName = (String) entityMap.get('entityName');
          if (String.isNotBlank(entityName)) {
            allEntities.add(entityName);
            entityCount++;
          }
        }
        searchCount++;
        System.debug(
          'Deep relationship search "' + searchTerm + '" found ' + entityCount + ' entities'
        );
      }
      searchIndex++;
    }

    stage.stageOutput = aggregateStageResults(allResults);
    stage.resultEntities = new List<String>(allEntities);

    System.debug(
      'Deep Relationship Stage completed. Mapped detailed relationships for ' +
        topEntities.size() +
        ' entities from ' +
        searchCount +
        ' searches'
    );
    return stage;
  }

  private static ResearchStage executeValidationSynthesisStage(ResearchContext context) {
    ResearchStage stage = new ResearchStage(
      'Stage3',
      RRAPromptTemplates.DEEP_WEB_RESEARCH_REFINEMENT
    );

    // Aggregate all relationship data from previous stages
    String aggregatedRelationships = aggregateAllStageData(context);

    System.debug(
      'Stage 3: Processing ' +
        (aggregatedRelationships != null ? aggregatedRelationships.length() : 0) +
        ' characters of relationship data'
    );

    RRADiagnostics.DiagnosticEntry stage3Diag = diag.get('DeepWebResearch').get('Stage3');
    stage3Diag.put('searchTarget', context.targetEntity);
    stage3Diag.put('recordContext', context.recordContextSearchTerms);
    stage3Diag.put('inputRelationships', JSON.deserializeUntyped(aggregatedRelationships));

    // Prepare input for refinement template
    Map<String, Object> refinementInputs = new Map<String, Object>();
    refinementInputs.put('Input:TargetEntity', context.targetEntity);
    refinementInputs.put('Input:WebRelationships', aggregatedRelationships);
    refinementInputs.put('Input:RecordContext', context.recordContextSearchTerms);

    Map<String, Object> stageContext = new Map<String, Object>(context.globalContext);
    stageContext.putAll(refinementInputs);

    // Single call to refinement template for consolidation and deduplication
    EinsteinPromptResponse response = EinsteinPromptService.prompt(
      stage.promptTemplate,
      stageContext
    );

    // Use EinsteinPromptResponse.getJson() which handles conversational responses and extraction
    Object refinedResultDeserialized = response.getJson();

    // Guard 1: No JSON parsed - likely conversational response
    if (refinedResultDeserialized == null) {
      String rawText = response.getText();
      System.debug(LoggingLevel.WARN, 'Stage 3: Failed to parse JSON from response: ' + rawText);
      stage.stageOutput = '[]';
      stage3Diag.put('refinedResults', null);
      return stage;
    }

    // Guard 2: Non-list format returned
    if (!(refinedResultDeserialized instanceof List<Object>)) {
      System.debug(
        LoggingLevel.ERROR,
        'Stage 3: Refinement returned non-list format: ' + refinedResultDeserialized
      );
      stage.stageOutput = JSON.serialize(refinedResultDeserialized);
      stage3Diag.put('refinedResults', refinedResultDeserialized);
      return stage;
    }

    List<Object> refinedList = (List<Object>) refinedResultDeserialized;
    // Store the clean JSON string for output
    stage.stageOutput = JSON.serialize(refinedResultDeserialized);
    stage3Diag.put('refinedResults', refinedList);
    System.debug('Stage 3: ' + refinedList.size() + ' relationships');
    return stage;
  }

  private static List<String> generateDiscoverySearchTerms(String targetEntity) {
    List<String> searchTerms = new List<String>();

    // Multi-angle discovery searches
    searchTerms.add(targetEntity + ' company overview leadership team');
    searchTerms.add(targetEntity + ' partnerships investors board members');
    searchTerms.add(targetEntity + ' recent news announcements executives');
    searchTerms.add(targetEntity + ' business model revenue clients customers');
    searchTerms.add(targetEntity + ' competitors industry analysis market position');

    return searchTerms;
  }

  /**
   * Generate enhanced deep relationship searches (2-3 searches per entity for higher quality)
   */
  private static List<String> generateDeepRelationshipSearchTerms(
    String targetEntity,
    List<String> entities
  ) {
    List<String> searchTerms = new List<String>();

    // Generate multiple focused searches per entity (up to 3 entities to stay within limits)
    for (Integer i = 0; i < Math.min(entities.size(), 3); i++) {
      String entity = entities[i];

      // Search 1: Leadership/ownership relationships
      searchTerms.add(
        targetEntity + ' ' + entity + ' CEO founder president chairman ownership subsidiary'
      );

      // Search 2: Business partnerships and investments
      searchTerms.add(
        targetEntity + ' ' + entity + ' partnership investment acquisition strategic alliance'
      );

      // Search 3: Operational and competitive relationships
      if (searchTerms.size() < 8) {
        // Keep total searches manageable
        searchTerms.add(
          targetEntity + ' ' + entity + ' competitor supplier customer business relationship'
        );
      }
    }

    return searchTerms;
  }

  /**
   * Aggregate multiple JSON results into a single consolidated result
   * Note: No deduplication here - Stage 3 will handle entity consolidation via prompt
   */
  private static String aggregateStageResults(List<String> results) {
    if (results.isEmpty()) {
      return '[]';
    }

    List<Object> aggregatedResults = new List<Object>();

    for (String result : results) {
      try {
        if (String.isNotBlank(result) && !result.equals('[]')) {
          List<Object> resultList = (List<Object>) JSON.deserializeUntyped(result);
          aggregatedResults.addAll(resultList);
        }
      } catch (Exception e) {
        System.debug('Failed to parse result for aggregation: ' + e.getMessage());
      }
    }

    return JSON.serialize(aggregatedResults);
  }

  /**
   * Get top entities from research context based on discovery order
   */
  private static List<String> getTopEntitiesFromContext(ResearchContext context, Integer maxCount) {
    List<String> topEntities = new List<String>();

    Integer count = 0;
    for (String entity : context.resultEntities) {
      if (count >= maxCount)
        break;
      topEntities.add(entity);
      count++;
    }

    return topEntities;
  }

  /**
   * Aggregate all relationship data from previous stages for Stage 3 refinement
   */
  private static String aggregateAllStageData(ResearchContext context) {
    List<String> stageOutputs = new List<String>();

    // Collect outputs from Stage 1 and Stage 2
    String stage1Output = (String) context.globalContext.get('Stage1_Output');
    String stage2Output = (String) context.globalContext.get('Stage2_Output');

    if (String.isNotBlank(stage1Output) && !stage1Output.equals('[]')) {
      stageOutputs.add(stage1Output);
    }

    if (String.isNotBlank(stage2Output) && !stage2Output.equals('[]')) {
      stageOutputs.add(stage2Output);
    }

    System.debug('Aggregating data from ' + stageOutputs.size() + ' previous stages');

    if (stageOutputs.isEmpty()) {
      return '[]';
    }

    // Use existing aggregation method to combine all stage data
    return aggregateStageResults(stageOutputs);
  }
}
