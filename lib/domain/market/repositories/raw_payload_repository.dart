import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class RawPayloadRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  RawPayloadRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  List<Map<String, dynamic>> queryRawPayload(
    ToolContext context, {
    String? source,
    String? endpoint,
    int limit = 20,
  }) {
    return _storeForContext(context)?.queryRawApiPayload(
          source: source,
          endpoint: endpoint,
          limit: limit,
        ) ??
        _dataManager.queryRawApiPayload(
          source: source,
          endpoint: endpoint,
          limit: limit,
        );
  }
}
