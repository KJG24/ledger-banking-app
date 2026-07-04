import { TransactionForm } from "./features/transactions/TransactionForm";
import { TransactionReceipt } from "./features/transactions/TransactionReceipt";
import { TransactionJournal } from "./features/transactions/TransactionJournal";
import { API_BASE_URL } from "./api/transactions";

export function App() {
  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-header__brand">
          <h1 className="wordmark">
            Ledger<span className="wordmark-mark">.</span>
          </h1>
          <p className="app-header__subtitle">A typed transaction processor</p>
        </div>
        <div className="app-header__meta">
          API <strong>{API_BASE_URL}</strong>
          <br />
          Validated server-side, returned as formatted JSON
        </div>
      </header>

      <main>
        <div className="workspace">
          <TransactionForm />
          <TransactionReceipt />
        </div>
        <TransactionJournal />
      </main>

      <footer className="app-footer">
        <span>
          Haskell · Scotty · Aeson · WAI/Warp — React · TypeScript · Redux
          Toolkit
        </span>
        <span>
          Backend on <code>:8080</code>, frontend on <code>:5173</code>
        </span>
      </footer>
    </div>
  );
}
