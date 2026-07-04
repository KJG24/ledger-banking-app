import { useAppDispatch, useAppSelector } from "../../app/hooks";
import { clearHistory, viewEntry } from "./transactionsSlice";

function formatTime(iso: string): string {
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return iso;
  return parsed.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function TransactionJournal() {
  const dispatch = useAppDispatch();
  const history = useAppSelector((s) => s.transactions.history);
  const current = useAppSelector((s) => s.transactions.current);

  return (
    <section className="panel journal">
      <div className="panel__header">
        <span className="panel__eyebrow">Journal</span>
        <span className="panel__title">Transaction history</span>
        {history.length > 0 && (
          <button
            type="button"
            className="btn btn-ghost btn-tiny"
            onClick={() => dispatch(clearHistory())}
          >
            Clear
          </button>
        )}
      </div>

      <div className="journal__body">
        {history.length === 0 ? (
          <p className="journal__empty">
            Nothing posted yet this session. Every transaction you submit
            above will appear here, most recent first — click a row to
            bring it back up in the ledger entry panel.
          </p>
        ) : (
          <>
            <div className="journal__row journal__row--header">
              <span>#</span>
              <span>Account</span>
              <span className="journal__cell--wide-only">Type</span>
              <span>Amount</span>
              <span>Status</span>
              <span className="journal__cell--wide-only">Time</span>
            </div>
            {history.map((txn, index) => (
              <button
                key={txn.transactionId}
                type="button"
                className="journal__row"
                onClick={() => dispatch(viewEntry(txn.transactionId))}
                aria-current={current?.transactionId === txn.transactionId}
              >
                <span className="journal__num">{history.length - index}</span>
                <span className="journal__cell--truncate">
                  {txn.accountId ?? "—"}
                </span>
                <span className="journal__cell--wide-only journal__cell--truncate">
                  {txn.type ?? "—"}
                </span>
                <span>{txn.amountFormatted ?? "—"}</span>
                <span className="journal__status">
                  <span
                    className={
                      "status-dot " +
                      (txn.status === "APPROVED"
                        ? "status-dot--approved"
                        : "status-dot--declined")
                    }
                  />
                  {txn.status}
                </span>
                <span className="journal__cell--wide-only">
                  {formatTime(txn.receivedAt)}
                </span>
              </button>
            ))}
          </>
        )}
      </div>
    </section>
  );
}
