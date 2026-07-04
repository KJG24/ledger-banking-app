import { useState } from "react";
import type { FormEvent } from "react";
import { useAppDispatch, useAppSelector } from "../../app/hooks";
import { submitTransaction } from "./transactionsSlice";
import { CURRENCIES, TRANSACTION_TYPES } from "./types";
import type { CurrencyCode, TransactionTypeCode } from "./types";

interface FormState {
  accountId: string;
  type: TransactionTypeCode;
  amount: string;
  currency: CurrencyCode;
  description: string;
  counterparty: string;
}

const BLANK_FORM: FormState = {
  accountId: "",
  type: "DEPOSIT",
  amount: "",
  currency: "USD",
  description: "",
  counterparty: "",
};

// Three presets chosen to be reachable through the form exactly as a
// person would use it (no fields set to values the selects don't offer),
// so "Fill sample" is an honest demo of what typing them in would do:
// one clean approval, one that trips a risk flag without being rejected,
// and one that shows several validation errors coming back at once.
const SAMPLES: FormState[] = [
  {
    accountId: "acct12345",
    type: "DEPOSIT",
    amount: "2500.50",
    currency: "USD",
    description: "Paycheck deposit",
    counterparty: "",
  },
  {
    accountId: "acct98765432",
    type: "TRANSFER",
    amount: "15000",
    currency: "USD",
    description: "Move to savings",
    counterparty: "acct98765432",
  },
  {
    accountId: "bad id",
    type: "DEPOSIT",
    amount: "-5",
    currency: "USD",
    description: "",
    counterparty: "",
  },
];

export function TransactionForm() {
  const dispatch = useAppDispatch();
  const status = useAppSelector((state) => state.transactions.status);
  const [form, setForm] = useState<FormState>(BLANK_FORM);
  const [sampleIndex, setSampleIndex] = useState(0);

  const isTransfer = form.type === "TRANSFER";
  const isLoading = status === "loading";

  function update<K extends keyof FormState>(key: K, value: FormState[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    const amount = Number.parseFloat(form.amount);
    void dispatch(
      submitTransaction({
        accountId: form.accountId,
        type: form.type,
        amount: Number.isNaN(amount) ? 0 : amount,
        currency: form.currency,
        description: form.description,
        counterparty: form.counterparty.trim() || undefined,
      }),
    );
  }

  function fillSample() {
    const sample = SAMPLES[sampleIndex % SAMPLES.length];
    setForm(sample);
    setSampleIndex((i) => i + 1);
  }

  return (
    <section className="panel slip">
      <div className="panel__header">
        <span className="panel__eyebrow">Deposit slip</span>
        <span className="panel__title">New transaction</span>
      </div>

      <form className="slip__body" onSubmit={handleSubmit}>
        <div className="field">
          <label className="field__label" htmlFor="accountId">
            Account ID
          </label>
          <input
            id="accountId"
            className="field__control"
            value={form.accountId}
            onChange={(e) => update("accountId", e.target.value)}
            placeholder="ACCT12345"
            autoComplete="off"
          />
        </div>

        <div className="slip__row">
          <div className="field">
            <label className="field__label" htmlFor="type">
              Type
            </label>
            <select
              id="type"
              className="field__control"
              value={form.type}
              onChange={(e) =>
                update("type", e.target.value as TransactionTypeCode)
              }
            >
              {TRANSACTION_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label className="field__label" htmlFor="currency">
              Currency
            </label>
            <select
              id="currency"
              className="field__control"
              value={form.currency}
              onChange={(e) =>
                update("currency", e.target.value as CurrencyCode)
              }
            >
              {CURRENCIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="field">
          <label className="field__label" htmlFor="amount">
            Amount
          </label>
          <input
            id="amount"
            className="field__control"
            inputMode="decimal"
            value={form.amount}
            onChange={(e) => update("amount", e.target.value)}
            placeholder="0.00"
          />
        </div>

        {isTransfer && (
          <div className="field">
            <label className="field__label" htmlFor="counterparty">
              Counterparty account
            </label>
            <input
              id="counterparty"
              className="field__control"
              value={form.counterparty}
              onChange={(e) => update("counterparty", e.target.value)}
              placeholder="ACCT98765"
            />
            <span className="field__hint">Required for transfers.</span>
          </div>
        )}

        <div className="field">
          <label className="field__label" htmlFor="description">
            Description
          </label>
          <textarea
            id="description"
            className="field__control"
            value={form.description}
            onChange={(e) => update("description", e.target.value)}
            placeholder="What is this transaction for?"
            rows={2}
          />
        </div>

        <div className="slip__actions">
          <button
            type="button"
            className="btn btn-ghost"
            onClick={fillSample}
          >
            Fill sample
          </button>
          <button type="submit" className="btn" disabled={isLoading}>
            {isLoading ? "Posting…" : "Post transaction"}
          </button>
        </div>
      </form>
    </section>
  );
}
