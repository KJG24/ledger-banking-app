import { useState } from "react";
import { useAppSelector } from "../../app/hooks";
import { RISK_FLAG_LABELS } from "./types";

export function TransactionReceipt() {
  const current = useAppSelector((s) => s.transactions.current);
  const status = useAppSelector((s) => s.transactions.status);
  const error = useAppSelector((s) => s.transactions.error);
  const [copied, setCopied] = useState(false);

  async function copyJson() {
    if (!current) return;
    try {
      await navigator.clipboard.writeText(JSON.stringify(current, null, 2));
      setCopied(true);
      setTimeout(() => setCopied(false), 1400);
    } catch {
      // Clipboard permission can be denied by the browser; the JSON is
      // still fully visible and selectable in the panel either way.
    }
  }

  return (
    <section className="panel receipt">
      <div className="panel__header">
        <span className="panel__eyebrow">Ledger entry</span>
        <span className="panel__title">Response</span>
      </div>

      <div className="receipt__body" aria-busy={status === "loading"}>
        {status === "loading" && !current && (
          <p className="receipt__loading">Posting to the ledger…</p>
        )}

        {status === "failed" && error && (
          <p className="receipt__network-error">{error}</p>
        )}

        {status === "idle" && !current && (
          <p className="receipt__empty">
            Post a transaction and its formatted, validated JSON will
            appear here — stamped APPROVED or DECLINED, the same way a
            teller marks a slip.
          </p>
        )}

        {current && (
          <div
            className="receipt__content"
            style={{
              opacity: status === "loading" ? 0.45 : 1,
              transition: "opacity 150ms ease",
              display: "flex",
              flexDirection: "column",
              gap: 16,
            }}
          >
            <div className="receipt__top-row">
              <span className="receipt__id">
                <span className="receipt__id-label">Transaction ID</span>
                {current.transactionId}
              </span>
              <span
                key={current.transactionId + current.status}
                className={
                  "stamp " +
                  (current.status === "APPROVED"
                    ? "stamp--approved"
                    : "stamp--declined")
                }
              >
                {current.status}
              </span>
            </div>

            {current.riskFlags.length > 0 && (
              <div className="receipt__flags">
                {current.riskFlags.map((flag) => (
                  <span key={flag} className="flag-pill">
                    {RISK_FLAG_LABELS[flag]}
                  </span>
                ))}
              </div>
            )}

            {current.errors.length > 0 && (
              <ul className="receipt__errors">
                {current.errors.map((message, i) => (
                  <li key={i}>{message}</li>
                ))}
              </ul>
            )}

            <div className="receipt__json-wrap">
              <button
                type="button"
                className="btn btn-ghost btn-tiny receipt__copy"
                onClick={copyJson}
              >
                {copied ? "Copied" : "Copy JSON"}
              </button>
              <pre className="receipt__json">
                {JSON.stringify(current, null, 2)}
              </pre>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
