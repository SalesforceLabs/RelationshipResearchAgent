/**
 * RecordWebSearchContext - Extracts relevant keywords from CRM records to enhance web search queries
 *
 * This class analyzes record fields to identify meaningful keywords that can improve
 * the relevance of web search results. It extracts keywords from various record types
 * including Account, Contact, Opportunity, and Lead.
 *
 * TODO: Use a prompt to extract relevant search terms from description fields instead of
 * simple keyword extraction, as descriptions can be noisy and may contain irrelevant text.
 */
public with sharing class RecordWebSearchContext {
  public static String extractKeywords(ICrmReferentialEntity entity) {
    if (entity == null) {
      return '';
    }

    Map<String, Object> entityMap = (Map<String, Object>) JSON.deserializeUntyped(
      entity.serialize()
    );

    List<String> keywords = new List<String>();

    switch on entity.getSobjectType() {
      when 'Account' {
        keywords.addAll(extractAccountKeywords(entityMap));
      }
      when 'Contact' {
        keywords.addAll(extractContactKeywords(entityMap));
      }
      when 'Opportunity' {
        keywords.addAll(extractOpportunityKeywords(entityMap));
      }
      when 'Lead' {
        keywords.addAll(extractLeadKeywords(entityMap));
      }
    }

    return String.join(keywords, ' ');
  }

  private static List<String> extractAccountKeywords(Map<String, Object> accountMap) {
    List<String> keywords = new List<String>();

    String industry = (String) accountMap.get('industry');
    if (String.isNotBlank(industry)) {
      keywords.addAll(extractFromText(industry));
    }

    String website = (String) accountMap.get('website');
    if (String.isNotBlank(website)) {
      String domain = extractDomain(website);
      if (String.isNotBlank(domain)) {
        keywords.add(domain.toLowerCase());
      }
    }

    List<String> locationFields = new List<String>{ 'city', 'country' };
    for (String fieldName : locationFields) {
      String value = (String) accountMap.get(fieldName);
      if (String.isNotBlank(value)) {
        keywords.add(value.toLowerCase());
      }
    }

    return keywords;
  }

  private static List<String> extractContactKeywords(Map<String, Object> contactMap) {
    List<String> keywords = new List<String>();

    // Extract from text fields in priority order
    List<String> textFields = new List<String>{
      'accountName',
      'accountIndustry',
      'department',
      'title'
    };
    for (String fieldName : textFields) {
      String value = (String) contactMap.get(fieldName);
      if (String.isNotBlank(value)) {
        keywords.addAll(extractFromText(value));
      }
    }

    return keywords;
  }

  private static List<String> extractOpportunityKeywords(Map<String, Object> optyMap) {
    List<String> keywords = new List<String>();

    // Extract from text fields in priority order
    List<String> textFields = new List<String>{ 'accountName', 'accountIndustry', 'name' };
    for (String fieldName : textFields) {
      String value = (String) optyMap.get(fieldName);
      if (String.isNotBlank(value)) {
        keywords.addAll(extractFromText(value));
      }
    }

    return keywords;
  }

  private static List<String> extractLeadKeywords(Map<String, Object> leadMap) {
    List<String> keywords = new List<String>();

    List<String> textFields = new List<String>{ 'company', 'industry', 'title' };
    for (String fieldName : textFields) {
      String value = (String) leadMap.get(fieldName);
      if (String.isNotBlank(value)) {
        keywords.addAll(extractFromText(value));
      }
    }

    List<String> locationFields = new List<String>{ 'city', 'state', 'country' };
    for (String fieldName : locationFields) {
      String value = (String) leadMap.get(fieldName);
      if (String.isNotBlank(value)) {
        keywords.add(value.toLowerCase());
      }
    }

    return keywords;
  }

  // Tokenizes text and filters out short words and numbers
  private static List<String> extractFromText(String text) {
    List<String> keywords = new List<String>();
    Set<String> seen = new Set<String>();

    if (String.isBlank(text)) {
      return keywords;
    }

    String cleanText = text.replaceAll('[^a-zA-Z0-9\\s]', ' ');
    List<String> words = cleanText.split('\\s+');

    for (String word : words) {
      String cleanWord = word.trim().toLowerCase();

      // Filter: must be 2+ characters, not a number, not already seen
      if (cleanWord.length() >= 2 && !cleanWord.isNumeric() && !seen.contains(cleanWord)) {
        keywords.add(cleanWord);
        seen.add(cleanWord);
      }
    }

    // Limit to top 10 keywords to avoid overwhelming the search
    if (keywords.size() > 10) {
      List<String> limitedKeywords = new List<String>();
      for (Integer i = 0; i < 10; i++) {
        limitedKeywords.add(keywords[i]);
      }
      return limitedKeywords;
    }

    return keywords;
  }

  // Extracts base domain name from URL (removes protocol, www, and TLD)
  private static String extractDomain(String url) {
    if (String.isBlank(url)) {
      return '';
    }

    String domain = url.toLowerCase();

    domain = domain.replaceAll('^(https?://)?(www\\.)?', '');

    Integer slashIndex = domain.indexOf('/');
    if (slashIndex > 0) {
      domain = domain.substring(0, slashIndex);
    }

    domain = domain.replaceAll('\\.(com|org|net|io|co|ai|edu|gov)$', '');

    return domain;
  }
}
