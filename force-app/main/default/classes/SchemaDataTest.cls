@IsTest
public class SchemaDataTest {
  @IsTest
  public static void verifyEntityMatcherCacheConsistency() {
    SchemaData schemaData1 = SchemaData.getCachedSchemaData();
    Assert.isNotNull(schemaData1.schemaObjects);
    SchemaData schemaData2 = SchemaData.getCachedSchemaData();
    Assert.isNotNull(schemaData2.schemaObjects);
    Assert.isTrue(schemaData1.schemaObjects == schemaData2.schemaObjects);
  }
}
