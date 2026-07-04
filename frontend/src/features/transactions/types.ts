// These mirror the JSON shapes produced by the Haskell backend
// (see backend/src/Banking/Types.hs). Kept as string literal unions
// rather than enums so a value the backend rejects (e.g. a typo'd
// currency code) still round-trips through the UI instead of crashing it.

export type CurrencyCode = "USD" | "EUR" | "GBP" | "JPY";

export type TransactionTypeCode =
  | "DEPOSIT"
  | "WITHDRAWAL"
  | "TRANSFER"
  | "PAYMENT";

export type TransactionStatus = "APPROVED" | "DECLINED";

export type RiskFlag = "LARGE_AMOUNT" | "SELF_TRANSFER" | "ROUND_NUMBER";

/** What we send. Deliberately loose (strings, not the unions above) so
 * that whatever a person types is sent as-is and the backend's validator
 * is the single source of truth on what counts as valid — the UI doesn't
 * duplicate that logic, it just displays what comes back. */
export interface TransactionRequest {
  accountId: string;
  type: string;
  amount: number;
  currency: string;
  description: string;
  counterparty?: string;
}

/** What we get back. Every field but transactionId/status/riskFlags/errors
 * is optional because a declined transaction omits the normalized fields
 * entirely (aeson's `omitNothingFields` on the Haskell side). */
export interface TransactionResponse {
  transactionId: string;
  status: TransactionStatus;
  accountId?: string;
  type?: string;
  amountMinorUnits?: number;
  amountFormatted?: string;
  currency?: string;
  description?: string;
  counterparty?: string;
  riskFlags: RiskFlag[];
  errors: string[];
  receivedAt: string;
}

export const CURRENCIES: readonly CurrencyCode[] = ["USD", "EUR", "GBP", "JPY"];

export const TRANSACTION_TYPES: readonly TransactionTypeCode[] = [
  "DEPOSIT",
  "WITHDRAWAL",
  "TRANSFER",
  "PAYMENT",
];

export const RISK_FLAG_LABELS: Record<RiskFlag, string> = {
  LARGE_AMOUNT: "Large amount",
  SELF_TRANSFER: "Self transfer",
  ROUND_NUMBER: "Round number",
};
