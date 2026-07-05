import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import '../repositories/raw_payload_repository.dart';

class RawPayloadQueryService {
  final RawPayloadRepository _repository;

  RawPayloadQueryService({DataManager? dataManager})
    : _repository = RawPayloadRepository(dataManager ?? DataManager());

  Map<String, dynamic> query(
    ToolContext context,
    Map<String, dynamic> input, {
    int limit = 20,
  }) {
    final rows = _repository.queryRawPayload(
      context,
      source: input['source'] as String?,
      endpoint: input['endpoint'] as String?,
      limit: limit,
    );
    return {
      'action': 'query_raw_payload',
      'interfaceId': 'provider.raw_payload_audit',
      'provider': 'local',
      'capabilityId': 'local.raw_payload_audit',
      'canonicalSchema': 'raw_api_payload',
      'canonicalTable': 'raw_api_payload',
      'cacheStatus': 'diagnostic-readback',
      'cacheDecision':
          'diagnostic-only readback returned raw provider payload evidence; these rows are not reusable business data and must not bypass governed interfaces',
      'persistencePolicy': 'diagnostic-only',
      'normalWorkflowAllowed': false,
      'nextAction':
          'Use governed interfaces and query/readback actions for normal data; use raw payload rows only to inspect legacy or explicit diagnostic evidence before adding a normalizer/interface.',
      'count': rows.length,
      'source': 'local raw_api_payload',
      'data': rows,
    };
  }
}
