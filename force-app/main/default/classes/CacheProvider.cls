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
  private static final String BASE62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  private static Integer parseHexPair(String hex) {
    Integer val = 0;
    for (Integer i = 0; i < 2; i++) {
      val *= 16;
      String c = hex.substring(i, i + 1);
      if (c >= '0' && c <= '9') {
        val += Integer.valueOf(c);
      } else if (c >= 'A' && c <= 'F') {
        val += 10 + c.charAt(0) - 'A'.charAt(0);
      } else if (c >= 'a' && c <= 'f') {
        val += 10 + c.charAt(0) - 'a'.charAt(0);
      }
    }
    return val;
  }
  private static String getBase62Hash(String input, Integer length) {
    if (String.isBlank(input) || length <= 0)
      return null;

    // 1. Compute SHA-256 hash
    Blob hashBlob = Crypto.generateDigest('SHA-256', Blob.valueOf(input));
    String hashHex = EncodingUtil.convertToHex(hashBlob);
    // 2. Map each byte to Base62
    String text = '';
    for (Integer i = 0; i < hashHex.length() - 1; i += 2) {
      String hexPair = hashHex.substring(i, i + 2);
      Integer val = parseHexPair(hexPair); // convert hex to 0-255
      Integer idx = Math.mod(val, 62); // safe modulo
      text += BASE62.substring(idx, idx + 1);
      if (text.length() >= length)
        break;
    }

    return text;
  }

  // Creates a safe-to-use platform cache key. A valid cache key can only contain
  // alphanumeric characters and be at most 50 characters long.
  private static String makeSafePlatformCacheKey(String raw) {
    String safe = getBase62Hash(raw, 50);
    // removes any non-allowed characters
    safe = safe + raw.replaceAll('[^a-zA-Z0-9]', '');
    if (safe.length() > 50) {
      safe = safe.substring(0, 50);
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
      Object data = part.get(platformCacheKey);
      if (provider.restoreFromCache(data)) {
        System.debug('From Platform Cache ' + key);
        return;
      }
    } catch (Exception e) {
      // not a problem - platform cache will not be configured by default.
      String errHeader = 'Platform Cache error for key ' + key + ' in partition ' + CACHE_NAME;
      System.debug(errHeader + ': ' + e.getMessage());
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
      if (part != null) {
        part.put(platformCacheKey, computedCache, SCHEMA_CACHE_TTL);
      }
    } catch (Exception e) {
      // If platform cache is not available, which is the default,
      // we just log the error and move on.
      System.debug('Failed to store in Platform Cache with key :' + key + ': ' + e.getMessage());
    }
    storeInCache (provider, part, key, platformCacheKey);
  }

  private static void storeInCache(ValueProvider provider, Cache.OrgPartition part ,String key, string platformCacheKey) {
   // Compute and store
    Object computedCache = provider.compute();
    inMemoryCache.put(key, computedCache);

    try {
      if (part != null) {
        part.put(platformCacheKey, computedCache, SCHEMA_CACHE_TTL);
      }
    } catch (Exception e) {
      // If platform cache is not available, which is the default,
      // we just log the error and move on.
      System.debug('Failed to store in Platform Cache with key :' + key + ': ' + e.getMessage());
    }
  }

  // This is a helper method to help us debug. Would not be used in production.
  public static void storeInCache(ValueProvider provider, String key) {
    Cache.OrgPartition part = null;
     try {
      part = Cache.Org.getPartition(CACHE_NAME);

    } catch (Exception e) {
      // not a problem - platform cache will not be configured by default.
      String errHeader = 'Platform Cache error for partition ' + CACHE_NAME;
      System.debug(errHeader + ': ' + e.getMessage());
      part = null;
    }
    storeInCache(provider, part, key, makeSafePlatformCacheKey(key));
  }
}
