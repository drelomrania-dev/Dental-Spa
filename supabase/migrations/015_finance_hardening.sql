-- Make the RPC-only finance boundary explicit and address database-linter
-- findings introduced by the normalized ledger.

alter function finance_effect(text,numeric) set search_path=public;
alter function reject_finance_ledger_mutation() set search_path=public;

drop policy if exists finance_accounts_rpc_only on finance_accounts;
create policy finance_accounts_rpc_only on finance_accounts for all to public using(false) with check(false);
drop policy if exists finance_sessions_rpc_only on finance_collection_sessions;
create policy finance_sessions_rpc_only on finance_collection_sessions for all to public using(false) with check(false);
drop policy if exists finance_transactions_rpc_only on finance_transactions;
create policy finance_transactions_rpc_only on finance_transactions for all to public using(false) with check(false);
drop policy if exists finance_receipts_rpc_only on finance_receipts;
create policy finance_receipts_rpc_only on finance_receipts for all to public using(false) with check(false);

create index if not exists finance_sessions_opened_by_idx on finance_collection_sessions(opened_by);
create index if not exists finance_sessions_validated_by_idx on finance_collection_sessions(validated_by) where validated_by is not null;
create index if not exists finance_transactions_collected_by_idx on finance_transactions(collected_by,occurred_at desc);
create index if not exists finance_transactions_reversal_idx on finance_transactions(reverses_transaction_id) where reverses_transaction_id is not null;
