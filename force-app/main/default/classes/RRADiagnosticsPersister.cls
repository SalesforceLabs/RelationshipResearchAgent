public with sharing class RRADiagnosticsPersister {
  private static final String FILE_TITLE = 'RRA_Diagnostics';
  private static final String FILE_PATH = 'RRA_Diagnostics.json';

  public static Id saveJSON(Id recordId, String jsonString) {
    if (recordId == null || String.isBlank(jsonString)) {
      throw new IllegalArgumentException('Record ID and JSON string cannot be null or empty');
    }

    // Check if file already exists for this record
    List<ContentDocumentLink> existingLinks = getExistingLinks(recordId);

    // Delete existing file if it exists (no version history)
    if (!existingLinks.isEmpty()) {
      deleteExistingFiles(existingLinks);
    }

    // Create new ContentVersion
    ContentVersion cv = new ContentVersion();
    cv.Title = FILE_TITLE;
    cv.PathOnClient = FILE_PATH;
    cv.VersionData = Blob.valueOf(jsonString);
    cv.FirstPublishLocationId = recordId;
    cv.ContentLocation = 'S'; // S = Salesforce

    try {
      insert cv;
      return cv.Id;
    } catch (DmlException e) {
      throw new StorageException('Failed to save JSON file: ' + e.getMessage(), e);
    }
  }

  public static String getJson(Id recordId) {
    if (recordId == null) {
      throw new IllegalArgumentException('Record ID cannot be null');
    }

    try {
      // Find the linked ContentDocument
      List<ContentDocumentLink> links = getExistingLinks(recordId);

      if (links.isEmpty()) {
        return null;
      }

      // Get the latest version
      ContentVersion cv = [
        SELECT VersionData
        FROM ContentVersion
        WHERE ContentDocumentId = :links[0].ContentDocumentId AND IsLatest = TRUE
        LIMIT 1
      ];

      return cv.VersionData.toString();
    } catch (QueryException e) {
      throw new StorageException('Failed to retrieve JSON file: ' + e.getMessage(), e);
    }
  }

  public static Boolean hasJSON(Id recordId) {
    if (recordId == null) {
      return false;
    }

    List<ContentDocumentLink> links = getExistingLinks(recordId);
    return !links.isEmpty();
  }

  public static Boolean deleteJSON(Id recordId) {
    if (recordId == null) {
      throw new IllegalArgumentException('Record ID cannot be null');
    }

    List<ContentDocumentLink> existingLinks = getExistingLinks(recordId);

    if (existingLinks.isEmpty()) {
      return false;
    }

    deleteExistingFiles(existingLinks);
    return true;
  }

  private static List<ContentDocumentLink> getExistingLinks(Id recordId) {
    return [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :recordId AND ContentDocument.Title = :FILE_TITLE
    ];
  }

  private static void deleteExistingFiles(List<ContentDocumentLink> links) {
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink link : links) {
      docIds.add(link.ContentDocumentId);
    }

    List<ContentDocument> docsToDelete = [
      SELECT Id
      FROM ContentDocument
      WHERE Id IN :docIds
    ];

    try {
      delete docsToDelete;
    } catch (DmlException e) {
      throw new StorageException('Failed to delete existing files: ' + e.getMessage(), e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static String getDiagnosticsLink(Id recordId) {
    if (recordId == null) {
      return null;
    }

    List<ContentDocumentLink> links = getExistingLinks(recordId);

    if (links.isEmpty()) {
      return null;
    }

    ContentVersion cv = [
      SELECT Id, ContentDocumentId
      FROM ContentVersion
      WHERE ContentDocumentId = :links[0].ContentDocumentId AND IsLatest = TRUE
      LIMIT 1
    ];

    return '/lightning/r/ContentDocument/' + cv.ContentDocumentId + '/view';
  }

  public class StorageException extends Exception {
  }
}
