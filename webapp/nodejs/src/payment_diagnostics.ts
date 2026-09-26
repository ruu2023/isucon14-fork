type PaymentOperation =
  | "evaluation_handler"
  | "gateway_post"
  | "gateway_confirm_get"
  | "ride_reconciliation"
  | "fare_calculation";

type PaymentDiagnosticOutcome =
  | "gateway_post_accepted"
  | "gateway_post_non204"
  | "gateway_post_network_error"
  | "confirmation_get_200"
  | "confirmation_get_non200"
  | "confirmation_get_network_error"
  | "retry_count_0"
  | "retry_count_1"
  | "retry_count_2_plus"
  | "confirmation_checks_1"
  | "confirmation_checks_2_3"
  | "confirmation_checks_4_5"
  | "reconciliation_equal"
  | "reconciliation_mismatch";

type PaymentDurationBucket =
  | "le_10ms"
  | "gt_10_le_50ms"
  | "gt_50_le_100ms"
  | "gt_100_le_250ms"
  | "gt_250_le_500ms"
  | "gt_500_le_1000ms"
  | "gt_1000ms";

type OperationAggregate = {
  count: number;
  totalMs: number;
  maxMs: number;
  elapsedBuckets: Record<PaymentDurationBucket, number>;
};

const enabled = process.env.ISUCON_DIAG_PAYMENT === "1";
const aggregates = enabled
  ? new Map<PaymentOperation, OperationAggregate>()
  : undefined;
const outcomes = enabled
  ? new Map<PaymentDiagnosticOutcome, number>()
  : undefined;

const createElapsedBuckets = (): Record<PaymentDurationBucket, number> => ({
  le_10ms: 0,
  gt_10_le_50ms: 0,
  gt_50_le_100ms: 0,
  gt_100_le_250ms: 0,
  gt_250_le_500ms: 0,
  gt_500_le_1000ms: 0,
  gt_1000ms: 0,
});

const bucketElapsedTime = (elapsedMs: number): PaymentDurationBucket => {
  if (elapsedMs <= 10) return "le_10ms";
  if (elapsedMs <= 50) return "gt_10_le_50ms";
  if (elapsedMs <= 100) return "gt_50_le_100ms";
  if (elapsedMs <= 250) return "gt_100_le_250ms";
  if (elapsedMs <= 500) return "gt_250_le_500ms";
  if (elapsedMs <= 1000) return "gt_500_le_1000ms";
  return "gt_1000ms";
};

const incrementOutcome = (outcome: PaymentDiagnosticOutcome): void => {
  if (!outcomes) return;
  outcomes.set(outcome, (outcomes.get(outcome) ?? 0) + 1);
};

export const recordPaymentDiagnosticOutcome = (
  outcome: PaymentDiagnosticOutcome,
): void => {
  if (!enabled) return;
  incrementOutcome(outcome);
};

export const recordPaymentRetryCount = (retryCount: number): void => {
  if (!enabled) return;
  const outcome: PaymentDiagnosticOutcome =
    retryCount === 0
      ? "retry_count_0"
      : retryCount === 1
        ? "retry_count_1"
        : "retry_count_2_plus";
  incrementOutcome(outcome);
};

export const recordPaymentConfirmationChecks = (checkCount: number): void => {
  if (!enabled || checkCount === 0) return;
  const outcome: PaymentDiagnosticOutcome =
    checkCount === 1
      ? "confirmation_checks_1"
      : checkCount <= 3
        ? "confirmation_checks_2_3"
        : "confirmation_checks_4_5";
  incrementOutcome(outcome);
};

export const flushPaymentDiagnostics = (): void => {
  if (!enabled) return;
  const operationAggregates = aggregates;
  const outcomeAggregates = outcomes;
  if (
    !operationAggregates ||
    !outcomeAggregates ||
    (operationAggregates.size === 0 && outcomeAggregates.size === 0)
  )
    return;
  const snapshot = {
    operations: Object.fromEntries(operationAggregates),
    outcomes: Object.fromEntries(outcomeAggregates),
  };
  operationAggregates.clear();
  outcomeAggregates.clear();
  console.info("payment_diagnostics", JSON.stringify(snapshot));
};

export const measurePaymentOperation = <T>(
  operation: PaymentOperation,
  task: () => Promise<T>,
): Promise<T> => (enabled ? measureEnabled(operation, task) : task());

export const measurePaymentFetch = (
  operation: PaymentOperation,
  task: () => Promise<Response>,
  expectedStatus: number,
  acceptedOutcome: PaymentDiagnosticOutcome,
  otherStatusOutcome: PaymentDiagnosticOutcome,
  networkErrorOutcome: PaymentDiagnosticOutcome,
): Promise<Response> => {
  if (!enabled) return task();
  return measureEnabled(operation, () =>
    task().then(
      (response) => {
        recordPaymentDiagnosticOutcome(
          response.status === expectedStatus
            ? acceptedOutcome
            : otherStatusOutcome,
        );
        return response;
      },
      (err: unknown) => {
        recordPaymentDiagnosticOutcome(networkErrorOutcome);
        throw err;
      },
    ),
  );
};

const measureEnabled = async <T>(
  operation: PaymentOperation,
  task: () => Promise<T>,
): Promise<T> => {
  const startedAt = performance.now();
  try {
    return await task();
  } finally {
    const elapsedMs = performance.now() - startedAt;
    if (aggregates) {
      const aggregate = aggregates.get(operation) ?? {
        count: 0,
        totalMs: 0,
        maxMs: 0,
        elapsedBuckets: createElapsedBuckets(),
      };
      aggregate.count++;
      aggregate.totalMs += elapsedMs;
      aggregate.maxMs = Math.max(aggregate.maxMs, elapsedMs);
      aggregate.elapsedBuckets[bucketElapsedTime(elapsedMs)]++;
      aggregates.set(operation, aggregate);
    }
  }
};

if (enabled) {
  const timer = setInterval(() => {
    flushPaymentDiagnostics();
  }, 60_000);
  timer.unref();
}
