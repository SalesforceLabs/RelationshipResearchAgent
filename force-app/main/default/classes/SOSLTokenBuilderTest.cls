@IsTest(SeeAllData=false)
public class SOSLTokenBuilderTest {
  @IsTest
  public static void runComputeNameVariantsLLM() {
    // This tests run LLM code through the orchestrator.
    // We expect this to pass but it might need to be adjusted.
    List<String> data = SOSLTokenBuilder.computeNameVariants('Mike');
    // we hope that the LLM will be sensible enough to follow instructions
    // and return both 'mike' and 'michael', in lowercase as requested.
    // However, LLM might not be available, in which case data will be null.
    if (data == null) {
      System.debug('LLM gateway not available, skipping test');
      return;
    }

    Assert.isTrue(data.size() >= 2);
    Assert.isTrue(data.contains('mike'));
    Assert.isTrue(data.contains('michael'));
  }

  @IsTest
  public static void verifySOSLEscape() {
    Assert.areEqual('OHara', SOSLTokenBuilder.escapeAndSanitizeForSosl('O\'Hara'));
    Assert.areEqual('JoOBrien', SOSLTokenBuilder.escapeAndSanitizeForSosl('Jo\'O\'Brien'));
    Assert.areEqual('abcdef', SOSLTokenBuilder.escapeAndSanitizeForSosl('abc\'def'));
    Assert.areEqual('MacDonald', SOSLTokenBuilder.escapeAndSanitizeForSosl('Mac\'Donald'));
    Assert.areEqual('MecDonald', SOSLTokenBuilder.escapeAndSanitizeForSosl('Mec\'Donald'));
  }

  @IsTest
  public static void verifySOSLBuilder() {
    String jsonSchema = '{"schemaObjects":[{"phoneFields":["phone","fax"],"nameFields":["name"],"label":"Account","emailFields":[],"apiName":"account"},{"phoneFields":["phone","fax","mobilephone","homephone","otherphone","assistantphone"],"nameFields":["name"],"label":"Contact","emailFields":["email"],"apiName":"contact"},{"phoneFields":["phone","mobilephone","fax"],"nameFields":["name"],"label":"Lead","emailFields":["email"],"apiName":"lead"},{"phoneFields":["phone__c","mobilephone__c","fax__c"],"nameFields":["name"],"label":"MyContact","emailFields":["email__c"],"apiName":"mycontact__t"}]}';

    SchemaData schemaData = (SchemaData) JSON.deserialize(jsonSchema, SchemaData.class);
    SOSLTokenBuilder sosl = new SOSLTokenBuilder();
    sosl.add('test');
    String test1 = schemaData.buildFindSOSL(sosl.collectedTokens);
    String expectedPattern = 'FIND \'%%%\' IN NAME FIELDS RETURNING account(Id,name,phone,fax),contact(Id,name,phone,fax,mobilephone,homephone,otherphone,assistantphone,email),lead(Id,name,phone,mobilephone,fax,email),mycontact__t(Id,name,phone__c,mobilephone__c,fax__c,email__c)';
    Assert.areEqual(expectedPattern.replace('%%%', 'test'), test1);

    SOSLTokenBuilder soslThreeNames = new SOSLTokenBuilder();
    soslThreeNames.add('AAA');
    soslThreeNames.add('BBB');
    soslThreeNames.add('CCC');
    Assert.areEqual('AAA OR BBB OR CCC', soslThreeNames.collectedTokens);
    String testThreeNames = schemaData.buildFindSOSL(soslThreeNames.collectedTokens);
    Assert.areEqual(expectedPattern.replace('%%%', 'AAA OR BBB OR CCC'), testThreeNames);
  }

  @IsTest
  public static void verifyCollectSOSLTokensVeryLargeToken() {
    // Test very large tokens: a long token must be ignored
    SOSLTokenBuilder soslVeryLargeToken = new SOSLTokenBuilder();
    Assert.isFalse(
      soslVeryLargeToken.add('0'.repeat(soslVeryLargeToken.SOSL_MAX_QUERY_LENGTH + 10))
    );
    Assert.areEqual('', soslVeryLargeToken.collectedTokens);
  }

  @IsTest
  public static void verifyCollectSOSLTokensManyTokens() {
    // Test a lot of tokens: 200 tokens max
    SOSLTokenBuilder soslManyTokens = new SOSLTokenBuilder();
    final Integer lastBatchTerms = 10;
    Assert.isTrue(lastBatchTerms < soslManyTokens.SOSL_MAX_SEARCH_TERMS);
    final Integer fullSearchTokenPages = 2;
    final Integer tokenPadLeft = 3;
    final String expectedConcatenation = soslManyTokens.SOSL_JOIN;
    Assert.isTrue(
      (tokenPadLeft + 1 + expectedConcatenation.length() * soslManyTokens.SOSL_MAX_SEARCH_TERMS) <
      soslManyTokens.SOSL_MAX_QUERY_LENGTH
    );
    for (
      Integer i = 0;
      i < soslManyTokens.SOSL_MAX_SEARCH_TERMS * fullSearchTokenPages + lastBatchTerms;
      i++
    ) {
      String newSearchToken = 'T' + i.toString().leftPad(tokenPadLeft, '0');
      Assert.isTrue(
        soslManyTokens.add(newSearchToken),
        'unable to add token to search:' + newSearchToken
      );
    }
    List<Integer> returnedTokenResults = new List<Integer>();
    // note that we have an additional page
    for (Integer pageId = 0; pageId <= fullSearchTokenPages; pageId++) {
      returnedTokenResults.add(soslManyTokens.collectedTokens.split(expectedConcatenation).size());
      if (pageId == fullSearchTokenPages) {
        Assert.isFalse(soslManyTokens.moveNext());
      } else {
        Assert.isTrue(soslManyTokens.moveNext());
      }
    }
    // of collected results, one element will be partial page
    Integer partialCount = 0;
    for (Integer i = 0; i < returnedTokenResults.size(); i++) {
      Integer results = returnedTokenResults.get(i);
      if (results == lastBatchTerms) {
        partialCount++;
      } else {
        Assert.areEqual(soslManyTokens.SOSL_MAX_SEARCH_TERMS, results);
      }
    }
    Assert.areEqual(1, partialCount);
  }

  @IsTest
  public static void verifyCollectSOSLTokensOverCharacterLimits() {
    // test when tokens go beyond 4k limit.
    // Here we will add 100 search terms, 100 characters each.
    // We expect to see all 100 search terms after paging through the output,
    // and each concatenated SOSL search expression should be within limits.
    SOSLTokenBuilder soslManyTokens = new SOSLTokenBuilder();
    final Integer batchTerms = 100;
    Assert.isTrue(batchTerms < soslManyTokens.SOSL_MAX_SEARCH_TERMS);
    final Integer tokenPadLeft = 100;
    final String expectedConcatenation = soslManyTokens.SOSL_JOIN;
    // test that we expect overflow
    Assert.isTrue(
      (tokenPadLeft + 1 + expectedConcatenation.length()) * batchTerms >
      soslManyTokens.SOSL_MAX_QUERY_LENGTH
    );
    for (Integer i = 0; i < batchTerms; i++) {
      String newSearchToken = 'T' + i.toString().leftPad(tokenPadLeft, '0');
      Assert.isTrue(
        soslManyTokens.add(newSearchToken),
        'unable to add token to search:' + newSearchToken
      );
    }
    Integer capturedResults = 0;
    Integer capturedPages = 0;
    for (;;) {
      Assert.areNotEqual('', soslManyTokens.collectedTokens);
      capturedPages++;
      capturedResults += soslManyTokens.collectedTokens.split(expectedConcatenation).size();
      if (!soslManyTokens.moveNext()) {
        break;
      }
    }
    Assert.areEqual(batchTerms, capturedResults);
    Assert.isTrue(capturedPages > 1);
  }
}
