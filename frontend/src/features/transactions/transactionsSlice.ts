import { createAsyncThunk, createSlice } from "@reduxjs/toolkit";
import type { PayloadAction } from "@reduxjs/toolkit";
import { ApiRequestError, postTransaction } from "../../api/transactions";
import type { TransactionRequest, TransactionResponse } from "./types";

export type RequestStatus = "idle" | "loading" | "succeeded" | "failed";

export interface TransactionsState {
  /** Every response so far, most recent first — the running ledger. */
  history: TransactionResponse[];
  /** The response the receipt panel should currently display. */
  current: TransactionResponse | null;
  status: RequestStatus;
  error: string | null;
}

const initialState: TransactionsState = {
  history: [],
  current: null,
  status: "idle",
  error: null,
};

export const submitTransaction = createAsyncThunk<
  TransactionResponse,
  TransactionRequest,
  { rejectValue: string }
>("transactions/submit", async (request, { rejectWithValue }) => {
  try {
    return await postTransaction(request);
  } catch (err) {
    const message =
      err instanceof ApiRequestError
        ? err.message
        : "Something went wrong submitting that transaction.";
    return rejectWithValue(message);
  }
});

const transactionsSlice = createSlice({
  name: "transactions",
  initialState,
  reducers: {
    dismissCurrent(state) {
      state.current = null;
      state.status = "idle";
      state.error = null;
    },
    clearHistory(state) {
      state.history = [];
      state.current = null;
      state.status = "idle";
    },
    viewEntry(state, action: PayloadAction<string>) {
      const entry = state.history.find(
        (t) => t.transactionId === action.payload,
      );
      if (entry) {
        state.current = entry;
        state.status = "succeeded";
        state.error = null;
      }
    },
  },
  extraReducers: (builder) => {
    builder
      .addCase(submitTransaction.pending, (state) => {
        state.status = "loading";
        state.error = null;
      })
      .addCase(
        submitTransaction.fulfilled,
        (state, action: PayloadAction<TransactionResponse>) => {
          state.status = "succeeded";
          state.current = action.payload;
          state.history.unshift(action.payload);
        },
      )
      .addCase(submitTransaction.rejected, (state, action) => {
        state.status = "failed";
        state.error = action.payload ?? "Something went wrong.";
      });
  },
});

export const { dismissCurrent, clearHistory, viewEntry } =
  transactionsSlice.actions;
export default transactionsSlice.reducer;
