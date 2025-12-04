public class RRAClientOptions {
  @AuraEnabled
  public Boolean useDeepWebSearch = true;
  @AuraEnabled
  public Boolean useRecordContext = true;
  @AuraEnabled
  public Boolean isNewResearch = true;
  @AuraEnabled
  public String entityMatcherMode;

  public EntityMatcher.EntityMatcherMode parseEntityMatcherMode() {
    switch on entityMatcherMode {
      when 'DATACLOUD_AND_SOSL' {
        return EntityMatcher.EntityMatcherMode.DATACLOUD_AND_SOSL;
      }
      when 'DATACLOUD_AND_SOSL_FALLBACK' {
        return EntityMatcher.EntityMatcherMode.DATACLOUD_AND_SOSL_FALLBACK;
      }
      when 'DATACLOUD_ONLY' {
        return EntityMatcher.EntityMatcherMode.DATACLOUD_ONLY;
      }
      when 'DATACLOUD_FALLBACK_SOSL' {
        return EntityMatcher.EntityMatcherMode.DATACLOUD_FALLBACK_SOSL;
      }
      when else {
        return EntityMatcher.EntityMatcherMode.SOSL_ONLY;
      }
    }
  }
}
