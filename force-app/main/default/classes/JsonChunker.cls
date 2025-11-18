/**
 * Utility for splitting a JSON *array* into smaller JSON-array chunks
 * that never exceed <maxChars> characters and always contain
 * **whole elements**.
 */
public with sharing class JsonChunker {
  public static List<String> chunkJsonArray(List<Object> elements, Integer maxChars) {
    List<String> chunks = new List<String>();
    List<Object> current = new List<Object>();
    Integer currentLen = 2; // accounts for "[" + "]" added by JSON.serialize

    for (Object elem : elements) {
      String elemStr = JSON.serialize(elem);

      // Include this element if > maxChars
      if (elemStr.length() >= maxChars) {
        if (!current.isEmpty()) {
          chunks.add(JSON.serialize(current));
          current.clear();
          currentLen = 2;
        }
        chunks.add('[' + elemStr + ']');
        continue;
      }

      Integer overhead = current.isEmpty() ? 0 : 1; // comma
      if (currentLen + overhead + elemStr.length() > maxChars) {
        chunks.add(JSON.serialize(current));
        current.clear();
        currentLen = 2;
      }

      current.add(elem);
      currentLen += overhead + elemStr.length();
    }

    if (!current.isEmpty()) {
      chunks.add(JSON.serialize(current));
    }

    return chunks;
  }
}
