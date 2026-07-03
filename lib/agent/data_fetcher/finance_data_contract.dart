enum FinanceDataContractStepId {
  dataClass,
  cachePolicy,
  providerPolicy,
  normalizer,
  persistTarget,
  readbackAction,
  failureSink,
  uiSurface,
}

class FinanceDataContractStep {
  final FinanceDataContractStepId id;
  final int order;

  const FinanceDataContractStep({required this.id, required this.order});
}

const financeDataContractSteps = <FinanceDataContractStep>[
  FinanceDataContractStep(id: FinanceDataContractStepId.dataClass, order: 1),
  FinanceDataContractStep(id: FinanceDataContractStepId.cachePolicy, order: 2),
  FinanceDataContractStep(
    id: FinanceDataContractStepId.providerPolicy,
    order: 3,
  ),
  FinanceDataContractStep(id: FinanceDataContractStepId.normalizer, order: 4),
  FinanceDataContractStep(
    id: FinanceDataContractStepId.persistTarget,
    order: 5,
  ),
  FinanceDataContractStep(
    id: FinanceDataContractStepId.readbackAction,
    order: 6,
  ),
  FinanceDataContractStep(id: FinanceDataContractStepId.failureSink, order: 7),
  FinanceDataContractStep(id: FinanceDataContractStepId.uiSurface, order: 8),
];

List<FinanceDataContractStepId> financeDataContractStepOrder() =>
    financeDataContractSteps.map((step) => step.id).toList(growable: false);
