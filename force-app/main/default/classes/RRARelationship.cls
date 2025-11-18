/**
 * DEPRECATED: RRARelationship has been removed in favor of the
 * RelationshipInsightsEnvelope
 *
 * Do not use this class.  It remains only to avoid compile-time failures.
 */
public with sharing class RRARelationship {
  public RRARelationship() {
    System.debug(
      'RRARelationship is deprecated. Use RelationshipInsightsEnvelope.RelatedEntity instead.'
    );
  }
}
