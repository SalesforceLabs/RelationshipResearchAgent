@IsTest(SeeAllData=false)
public class EntityMatcherTest {
  // Helper: create basic data + register mock executor with default name
  // variants
  private static EinsteinPromptService.MockExecutor setMockDataForMike() {
    EinsteinPromptService.MockExecutor exec = new EinsteinPromptService.MockExecutor();
    exec.setResults(RRAPromptTemplates.COMMON_NAME_VARIANTS, '["Mike","Michael"]');
    EinsteinPromptService.setExecutorForTest(exec);

    // Seed simple graph (Account + two matching Contacts)
    Account acc = new Account(Name = 'Test');
    insert acc;

    Contact c1 = new Contact(FirstName = 'Mike', LastName = 'Test', AccountId = acc.Id);
    Contact c2 = new Contact(FirstName = 'Michael', LastName = 'Test', AccountId = acc.Id);
    insert new List<Contact>{ c1, c2 };

    // Make SOSL deterministic for the Contacts above
    Id[] fsr = new Id[2];
    fsr[0] = c1.Id;
    fsr[1] = c2.Id;
    Test.setFixedSearchResults(fsr);

    return exec;
  }

  private static EntityMatcher.InputName newInputName(String name) {
    EntityMatcher.InputName s = new EntityMatcher.InputName();
    s.name = name;
    return s;
  }

  @IsTest(SeeAllData=false)
  public static void runEntityMatchingTest() {
    EinsteinPromptService.MockExecutor mock = setMockDataForMike();

    // Case 1: simulate an error/empty-body from consolidation prompt, expecting
    //         null.
    mock.setResults(RRAPromptTemplates.COMMON_NAME_VARIANTS, null);
    final EntityMatcher.MatchedEntity me = EntityMatcher.findMatchesSingle(
      'mike',
      EntityMatcher.EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK
    );
    Assert.isNotNull(me);
    Assert.isNull(me.matches);

    // Case 2: return proper consolidated JSON, expecting two matches back
    mock.setResults(
      RRAPromptTemplates.COMMON_NAME_VARIANTS,
      '[{"inputName":"mike","Id":"003SB00000lKdwbYAC","Name":"Michael Jones","confidenceScore":100},{"inputName":"mike","Id":"003SB00000lKduzYAC","Name":"Mike Jones","confidenceScore":80}]'
    );

    EntityMatcher.MatchedEntity data = EntityMatcher.findMatchesSingle(
      'mike',
      EntityMatcher.EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK
    );
    Assert.isNotNull(data);
    Assert.areEqual(2, data.matches.size());

    EinsteinPromptService.setExecutorForTest(null);
  }

  @IsTest(SeeAllData=false)
  public static void runEntityMatchingMulti() {
    EinsteinPromptService.MockExecutor mock = setMockDataForMike();

    String resolvedJson =
      '[\n' +
      '  {"inputName":"mike","name":"Mike Jones","id":"003SB00000lKduzYAC","email":"supercool@hotmail.com","phone":"(403)123-2233, (888)111-2233","confidenceScore":100},\n' +
      '  {"inputName":"mike","name":"Michael Jones","id":"003SB00000lKdwbYAC","email":"mike@ms.com","phone":"555-555-2389","confidenceScore":90},\n' +
      '  {"inputName":"jones","name":"Mike Jones","id":"003SB00000lKduzYAC","email":"supercool@hotmail.com","phone":"(403)123-2233, (888)111-2233","confidenceScore":80},\n' +
      '  {"inputName":"jones","name":"Michael Jones","id":"003SB00000lKdwbYAC","email":"mike@ms.com","phone":"555-555-2389","confidenceScore":80},\n' +
      '  {"inputName":"bolt","confidenceScore":0}\n' +
      ']';

    mock.setResults(RRAPromptTemplates.COMMON_NAME_VARIANTS, resolvedJson);

    List<EntityMatcher.InputName> names = new List<EntityMatcher.InputName>{
      newInputName('mike'),
      newInputName('jones'),
      newInputName('bolt')
    };

    List<EntityMatcher.MatchedEntity> data = EntityMatcher.findMatchesMulti(names);
    Assert.isNotNull(data);
    Assert.areEqual(3, data.size());
    Assert.areEqual(names[0].name, data[0].term);
    Assert.areEqual(names[1].name, data[1].term);
    Assert.areEqual(names[2].name, data[2].term);

    Assert.areEqual(2, data[0].matches.size());
    Assert.areEqual(2, data[1].matches.size());
    Assert.areEqual(100, data[0].matches[0].confidence);
    Assert.areEqual('003SB00000lKduzYAC', data[0].matches[0].info.id);
    Assert.areEqual(90, data[0].matches[1].confidence);
    Assert.areEqual('003SB00000lKdwbYAC', data[0].matches[1].info.id);

    Assert.areEqual(80, data[1].matches[0].confidence);
    Assert.areEqual('003SB00000lKduzYAC', data[1].matches[0].info.id);
    Assert.areEqual(80, data[1].matches[1].confidence);
    Assert.areEqual('003SB00000lKdwbYAC', data[1].matches[1].info.id);

    Assert.isTrue(data[2].matches == null || data[2].matches.size() == 0);

    EinsteinPromptService.setExecutorForTest(null);
  }

  @IsTest
  public static void verifyMatchBatch() {
    EinsteinPromptService.MockExecutor mock = new EinsteinPromptService.MockExecutor();
    mock.setResultsEmptyArray(RRAPromptTemplates.COMMON_NAME_VARIANTS);
    EinsteinPromptService.setExecutorForTest(mock);

    EntityMatcher.Processor p = new EntityMatcher.Processor();
    p.add('name'); // triggers one common_name_variants prompt

    List<EntityMatcher.EntityInfo> allMatches = new List<EntityMatcher.EntityInfo>();
    final Integer lastPageSize = 100;
    System.assert(EntityMatcher.MAX_MATCHES_BATCH > lastPageSize, 'last page must be < MAX');

    final Integer fullBatches = 2;
    Set<Id> allIds = new Set<Id>();
    Integer total = EntityMatcher.MAX_MATCHES_BATCH * fullBatches + lastPageSize;

    for (Integer i = 0; i < total; i++) {
      EntityMatcher.EntityInfo info = new EntityMatcher.EntityInfo();
      // build a valid-looking 15-char Account Id, cast to Id for consistency
      String fifteen = '001' + String.valueOf(i).leftPad(12, '0');
      info.id = (Id) fifteen;
      allIds.add(info.id);
      info.name = 'Name ' + info.id;
      allMatches.add(info);
    }

    p.match(allMatches);

    // Assert: #calls = (1x name variants) + #batches, where
    //         #batches = ceil(total / MAX_BATCH)
    Integer expectedBatches = (Integer) Math.ceil(
      (Decimal) total / EntityMatcher.MAX_MATCHES_BATCH
    );
    System.assertEquals(1 + expectedBatches, mock.calls.size(), 'unexpected call count');

    // First call should be to the name-variants template
    System.assert(
      mock.calls.get(0).promptId.equalsIgnoreCase(RRAPromptTemplates.COMMON_NAME_VARIANTS),
      'First prompt should resolve ' + RRAPromptTemplates.COMMON_NAME_VARIANTS
    );

    // Remaining calls should be to match_resolved_entities, and together
    // include all IDs
    Integer matchedCount = 0;
    for (Integer c = 1; c < mock.calls.size(); c++) {
      System.assert(
        mock.calls.get(c).promptId.equalsIgnoreCase(RRAPromptTemplates.COMMON_NAME_VARIANTS),
        'Subsequent prompts should be match_resolved_entities'
      );

      for (List<String> kv : mock.calls.get(c).calledInputs) {
        if (kv.get(0) != 'json_resolved') {
          continue;
        }

        List<EntityMatcher.EntityInfo> batch = (List<EntityMatcher.EntityInfo>) JSON.deserialize(
          kv.get(1),
          List<EntityMatcher.EntityInfo>.class
        );
        for (EntityMatcher.EntityInfo info : batch) {
          System.assert(allIds.remove(info.id), 'unknown id: ' + info.id);
          matchedCount++;
        }
      }
    }

    System.assertEquals(total, matchedCount, 'not all matches were passed through batches');
    System.assertEquals(0, allIds.size(), 'some ids were not batched: ' + JSON.serialize(allIds));

    EinsteinPromptService.setExecutorForTest(null);
  }
}
