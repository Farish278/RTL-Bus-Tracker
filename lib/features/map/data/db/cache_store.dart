abstract class CacheStore {
  Future<void> put(String key, Object value);
  Future<Map<String, dynamic>?> get(String key);
  Future<void> clear();
}
