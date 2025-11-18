public class CacheProvider {
  public interface ValueProvider {
    // computes default data and returns cachable part
    Object compute();
    Boolean restoreFromCache(Object cache);
  }

  // Platform cache. This won't always be available.
  private static final String CACHE_NAME = 'rrapicache';
  private static final Integer SCHEMA_CACHE_TTL = 3600;
  // in-memory cache, for one session.
  private static Map<String, Object> inMemoryCache = new Map<String, Object>();

  // creates a safe-to-use platform cache key. This might create
  private static String makeSafePlatformCacheKey(String raw) {
    // Compute SHA-512 hash of the raw input
    Blob hashBlob = Crypto.generateDigest('SHA-512', Blob.valueOf(raw));
    String hashHex = EncodingUtil.convertToHex(hashBlob);
    // removes any non-allowed characters
    String safe = hashHex + raw.replaceAll('[^a-zA-Z0-9]', '');
    if (safe.length() > 256) {
      safe = safe.substring(0, 256);
    }
    return safe;
  }

  // helper function to restore data from cache, or compute default data
  // and store it in cache.
  public static void populate(ValueProvider provider, String key) {
    // Try Platform Cache
    Cache.OrgPartition part = null;
    String platformCacheKey = makeSafePlatformCacheKey(key);
    try {
      part = Cache.Org.getPartition(CACHE_NAME);
      Object data = part.get(key);
      if (provider.restoreFromCache(data)) {
        System.debug('From Platform Cache ' + key);
        return;
      }
    } catch (Exception e) {
      // not a problem - platform cache will not be configured by default.
      System.debug('Platform Cache error: ' + e.getMessage());
    }

    // Try in-memory fallback
    if (inMemoryCache.containsKey(key)) {
      Object data = inMemoryCache.get(key);
      if (provider.restoreFromCache(data)) {
        System.debug('From In-Memory Cache ' + key);
        return;
      }
    }

    // Compute and store
    Object computedCache = provider.compute();
    inMemoryCache.put(key, computedCache);

    try {
      part.put(key, computedCache, SCHEMA_CACHE_TTL);
    } catch (Exception e) {
      // If platform cache is not available, which is the default,
      // we just log the error and move on.
      System.debug('Failed to store in Platform Cache: ' + e.getMessage());
    }
  }
}
