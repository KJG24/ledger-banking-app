import type { TransactionRequest, TransactionResponse } from "../features/transactions/types";

export const API_BASE_URL: string =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ??
  "http://localhost:8080";

/** Raised when the backend couldn't even parse the request — a malformed
 * body or a missing/mis-typed field. This is distinct from a *declined*
 * transaction, which is a well-formed, well-understood API response (see
 * `postTransaction` below) and not an error at all from the UI's point
 * of view. */
export class ApiRequestError extends Error {}

/** POST a transaction to the backend and return its response.
 *
 * The backend answers 200 for an approved transaction and 400 for both
 * a *declined* transaction (validation failed) and a genuinely malformed
 * request. We tell those two 400 cases apart by shape: a declined
 * transaction is still a full TransactionResponse (it has a
 * transactionId and a status); a malformed request is just `{ error }`.
 * Only the latter is treated as an exception here — a decline is a
 * normal, displayable result.
 */
export async function postTransaction(
  request: TransactionRequest,
): Promise<TransactionResponse> {
  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}/api/transactions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(request),
    });
  } catch {
    throw new ApiRequestError(
      `Could not reach the backend at ${API_BASE_URL}. Is it running?`,
    );
  }

  let body: unknown;
  try {
    body = await res.json();
  } catch {
    throw new ApiRequestError(
      `The backend returned a response that wasn't JSON (HTTP ${res.status}).`,
    );
  }

  if (isTransactionResponse(body)) {
    return body;
  }

  const message =
    typeof body === "object" && body !== null && "error" in body
      ? String((body as { error: unknown }).error)
      : `Unexpected response from the backend (HTTP ${res.status}).`;
  throw new ApiRequestError(message);
}

function isTransactionResponse(value: unknown): value is TransactionResponse {
  return (
    typeof value === "object" &&
    value !== null &&
    "transactionId" in value &&
    "status" in value &&
    "riskFlags" in value &&
    "errors" in value
  );
}
