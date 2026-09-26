import { setTimeout } from "node:timers/promises";
import { ErroredUpstream } from "./common.js";
import {
  measurePaymentFetch,
  measurePaymentOperation,
  recordPaymentConfirmationChecks,
  recordPaymentDiagnosticOutcome,
  recordPaymentRetryCount,
} from "./payment_diagnostics.js";
import type { Ride } from "./types/models.js";

type PaymentGatewayPostPaymentRequest = {
  amount: number;
};

export const requestPaymentGatewayPostPayment = async (
  paymentGatewayURL: string,
  token: string,
  param: PaymentGatewayPostPaymentRequest,
  retrieveRidesOrderByCreatedAtAsc: () => Promise<Ride[]>,
): Promise<ErroredUpstream | Error | undefined> => {
  // 失敗したらとりあえずリトライ
  // FIXME: 社内決済マイクロサービスのインフラに異常が発生していて、同時にたくさんリクエストすると変なことになる可能性あり
  let retry = 0;
  try {
    while (true) {
      try {
        const res = await measurePaymentFetch(
          "gateway_post",
          () =>
            fetch(`${paymentGatewayURL}/payments`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${token}`,
              },
              body: JSON.stringify(param),
            }),
          204,
          "gateway_post_accepted",
          "gateway_post_non204",
          "gateway_post_network_error",
        );

        if (res.status !== 204) {
          // エラーが返ってきても成功している場合があるので、社内決済マイクロサービスに問い合わせ
          // 決済ゲートウェイ側の反映遅延を考慮し、POSTは再送せずGETだけ確認する
          let checkCount = 0;
          try {
            for (let checkRetry = 0; checkRetry < 5; checkRetry++) {
              checkCount++;
              const getRes = await measurePaymentFetch(
                "gateway_confirm_get",
                () =>
                  fetch(`${paymentGatewayURL}/payments`, {
                    method: "GET",
                    headers: {
                      Authorization: `Bearer ${token}`,
                    },
                  }),
                200,
                "confirmation_get_200",
                "confirmation_get_non200",
                "confirmation_get_network_error",
              );

              // GET /payments は障害と関係なく200が返るので、200以外は回復不能なエラーとする
              if (getRes.status !== 200) {
                return new Error(
                  `[GET /payments] unexpected status code (${getRes.status})`,
                );
              }
              const payments = await getRes.json();
              const rides = await measurePaymentOperation(
                "ride_reconciliation",
                retrieveRidesOrderByCreatedAtAsc,
              );
              if (rides.length === payments.length) {
                recordPaymentDiagnosticOutcome("reconciliation_equal");
                break;
              }
              recordPaymentDiagnosticOutcome("reconciliation_mismatch");
              if (checkRetry === 4) {
                return new ErroredUpstream(
                  `unexpected number of payments: ${rides.length} != ${payments.length}`,
                );
              }
              await setTimeout(100);
            }
          } finally {
            recordPaymentConfirmationChecks(checkCount);
          }
        }
        break;
      } catch (err) {
        if (retry < 5) {
          retry++;
          await setTimeout(100);
        } else {
          throw err;
        }
      }
    }
  } finally {
    recordPaymentRetryCount(retry);
  }
};
