public class SOSLTokenBuilder {
  public final static String PROMPT_TEMPLATE_NAME = 'RRA_CommonNameVariants';

  public static List<String> computeNameVariants(String name) {
    System.debug('Computing name variants for: ' + name);
    Map<String, Object> input = new Map<String, Object>{ 'Input:Name' => name };
    final List<Object> variants = EinsteinPromptService.promptListSafe(
      SOSLTokenBuilder.PROMPT_TEMPLATE_NAME,
      input
    );

    if (variants == null || variants.isEmpty()) {
      return null;
    }

    List<String> names = new List<String>();
    for (Object obj : variants) {
      if (!(obj instanceof String)) {
        System.debug('Unexpected type in name variants result:');
        System.debug(obj);
        continue;
      }

      String s = ((String) obj).trim();
      if (String.isNotBlank(s)) {
        names.add(s);
      }
    }

    return names.isEmpty() ? null : names;
  }

  private static final String cacheKeyNameVariantPrefix = 'NameVariant';

  // Caching computed variations of entity name, so we do not repeatedly
  // call a LLM to get the same variation results for us.
  public class FindNameVariantsCache implements CacheProvider.ValueProvider {
    public List<String> computedVariants { get; set; }
    public string name { get; set; }

    private Boolean hasData() {
      return computedVariants != null && !computedVariants.isEmpty();
    }

    public Object compute() {
      this.computedVariants = computeNameVariants(name);
      return this;
    }

    public Boolean restoreFromCache(Object cache) {
      if (!(cache instanceof FindNameVariantsCache)) {
        return false;
      }

      FindNameVariantsCache d = (FindNameVariantsCache) cache;
      if (this.name != d.name) {
        return false;
      }

      this.computedVariants = d.computedVariants;
      this.name = d.name;
      return hasData();
    }
  }

  // all collected tokens eg [AAA,BBB,CCC]. Tracking to ensure uniqueness.
  final Set<String> allTokens = new Set<String>();

  final Set<String> allOriginalTokens = new Set<String>();
  public List<string> getAllOriginalTokens() {
    return new List<String>(allOriginalTokens);
  }
  // SOSL statement to execute, in form of AAA OR BBB OR CCC
  public String collectedTokens { get; private set; }
  private Integer collectedTokensCount = 0;

  void resetCollectedTokens() {
    collectedTokensCount = 0;
    collectedTokens = '';
  }

  public SOSLTokenBuilder() {
    resetCollectedTokens();
  }

  // if we go beyond max allowed tokens, overflows will be stored here
  final List<String> overflowTokens = new List<String>();

  public Boolean moveNext() {
    if (overflowTokens.size() == 0) {
      return false;
    }
    this.collectedTokens = this.overflowTokens.remove(0);
    return true;
  }

  // Adds all variations of the token, tracking uniqueness.
  public Integer addWithVariants(String token) {
    Integer count = 0;
    if (add(token)) {
      count++;
    }

    FindNameVariantsCache cache = new FindNameVariantsCache();
    cache.name = token.toLowerCase();
    CacheProvider.populate(cache, cacheKeyNameVariantPrefix + token);
    if (cache.computedVariants != null) {
      for (String nameVariant : cache.computedVariants) {
        if (add(nameVariant)) {
          count++;
        }
      }
    }
    return count;
  }

  // Limits for SOSL interactions.
  // See https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_sosl_find.htm
  // Past 4000 characters, logical operators are ignored. We're using OR,
  // but we do not want to go past that anyway.
  @TestVisible
  final Integer SOSL_MAX_QUERY_LENGTH = 4000;
  // SOSL returns 2000 records max.
  final Integer SOSL_MAX_RETURNED_RECORDS = 2000;
  // Since this function is used in APEX flow, it looks like APEX's max batching
  // capability is batching in chunks of 200. The second parameter is how many
  // matches we can expect per a well-structured search term, which is arbitrary
  // and set to get the number to the same 200. We might want to adjust it in
  // future.
  @TestVisible
  final Integer SOSL_MAX_SEARCH_TERMS = Math.min(200, SOSL_MAX_RETURNED_RECORDS / 10);

  @TestVisible
  final String SOSL_JOIN = ' OR ';

  public Boolean add(String token) {
    String sanitizedToken = escapeAndSanitizeForSosl(token);
    if (string.isBlank(sanitizedToken) || !allTokens.add(sanitizedToken.toUpperCase())) {
      return false;
    }
    // for datacloud search, collect all original tokens.
    allOriginalTokens.add(token);
    if (
      this.collectedTokensCount >= SOSL_MAX_SEARCH_TERMS ||
      collectedTokens.length() + sanitizedToken.length() + SOSL_JOIN.length() >=
      SOSL_MAX_QUERY_LENGTH
    ) {
      if (string.isBlank(collectedTokens)) {
        // we should not be here, unless the token is too large
        System.debug('Discarding search token: ' + sanitizedToken);
        return false;
      }

      overflowTokens.add(collectedTokens);
      resetCollectedTokens();
    }

    if (!string.isBlank(collectedTokens)) {
      collectedTokens += SOSL_JOIN + sanitizedToken;
    } else {
      collectedTokens = sanitizedToken;
    }

    collectedTokensCount++;
    return true;
  }

  @TestVisible
  private static String escapeAndSanitizeForSosl(String input) {
    if (String.isBlank(input)) {
      return '';
    }

    // Remove SOSL reserved words if they appear as standalone tokens
    String sanitized = input
      .replaceAll('\\bAND\\b', ' ')
      .replaceAll('\\bOR\\b', ' ')
      .replaceAll('\\bNOT\\b', ' ');

    // replace apostrophe with an empty string, to avoid extra tokenization.
    // SOSL matches OHARA to O'Hara.
    sanitized = sanitized.replaceAll('\'', '');
    // The rest of the reserve characters are unlikely to show up in a valid
    // name, so just break into tokens.
    sanitized = sanitized.replaceAll('[*?"\\[\\](){}]', ' ');

    // Trim extra spaces
    sanitized = sanitized.trim();

    // Using quotes prevents SOSL from fuzzy matches.
    // Eg. Mike Jones will find "Michael Jones", but "Mike Jones" will not.
    if (sanitized.containsWhitespace()) {
      // Collapse multiple spaces to a single space
      sanitized = sanitized.replaceAll('\\s+', ' ');
    }

    return sanitized;
  }
}
