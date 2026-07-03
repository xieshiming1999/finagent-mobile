class ApiFailureClass {
  final String classification;
  final int count;
  final List<String> examples;

  const ApiFailureClass({
    required this.classification,
    required this.count,
    required this.examples,
  });

  Map<String, dynamic> toJson() => {
    'classification': classification,
    'count': count,
    'examples': examples,
  };
}

List<Map<String, dynamic>> classifyApiFailures(
  List<Map<String, dynamic>> rows,
) {
  final groups = <String, ApiFailureClass>{};
  for (final row in rows) {
    final classification = classifyApiFailure(row);
    final existing = groups[classification];
    final examples = [...?existing?.examples];
    if (examples.length < 3) {
      final endpoint = (row['endpoint'] ?? row['url'] ?? row['action'] ?? '-')
          .toString();
      final rawError =
          (row['error'] ?? row['status'] ?? row['statusCode'] ?? '').toString();
      final error = rawError.length > 120
          ? rawError.substring(0, 120)
          : rawError;
      examples.add(error.isEmpty ? endpoint : '$endpoint: $error');
    }
    groups[classification] = ApiFailureClass(
      classification: classification,
      count: (existing?.count ?? 0) + 1,
      examples: examples,
    );
  }
  final values = groups.values.toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  return values.map((row) => row.toJson()).toList();
}

String classifyApiFailure(Map<String, dynamic> row) {
  final explicit = _explicitFailureClass(
    row['failureClass'] ?? row['failure_class'] ?? row['classification'],
  );
  if (explicit != null) return explicit;
  final status = _status(row);
  if (status == 401 || status == 403) return 'auth_permission';
  if (status == 429) return 'quota_rate_limit';
  if (status == 400 || status == 422) return 'invalid_parameters';
  if (status == 0) return 'transport';
  if (status != null && status >= 500) return 'provider_outage';
  return 'unknown';
}

bool shouldStopProviderRetries(Map<String, dynamic> row) {
  final classification = classifyApiFailure(row);
  return classification == 'auth_permission' ||
      classification == 'quota_rate_limit';
}

bool isFinanceApiFailure(Map<String, dynamic> row) {
  final domain = (row['domain'] ?? row['category'] ?? '')
      .toString()
      .toLowerCase()
      .trim();
  if (domain == 'finance' || domain == 'market_data') return true;
  final source = (row['source'] ?? '').toString().toLowerCase().trim();
  const financeSources = {
    'akshare',
    'data_task',
    'eastmoney',
    'gotdx',
    'sidecar',
    'tdx',
    'tradingview',
    'tushare',
    'wind',
    'windmcp',
    'yahoo',
    'yfinance',
  };
  if (financeSources.contains(source)) return true;
  final tool = (row['tool'] ?? '').toString().trim();
  if (const {'DataStore', 'MarketData', 'WindMcp'}.contains(tool)) return true;
  final endpoint = (row['endpoint'] ?? row['url'] ?? '').toString();
  return Uri.tryParse(endpoint)?.path.startsWith('/api/finance/') == true;
}

String? _explicitFailureClass(Object? value) {
  final wire = value?.toString().trim().toLowerCase();
  return switch (wire) {
    'auth_permission' || 'credential-or-permission' => 'auth_permission',
    'quota_rate_limit' || 'quota-or-rate-limit' => 'quota_rate_limit',
    'contract_mismatch' || 'schema-or-contract' => 'contract_mismatch',
    'invalid_parameters' || 'invalid-parameters' => 'invalid_parameters',
    'transport' || 'timeout' || 'transport-unstable' => 'transport',
    'provider_outage' ||
    'provider-error' ||
    'provider_unavailable' => 'provider_outage',
    'unknown' => 'unknown',
    _ => null,
  };
}

int? _status(Map<String, dynamic> row) {
  final value = row['status'] ?? row['statusCode'];
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
