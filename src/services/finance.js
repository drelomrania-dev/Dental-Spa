import { supabase, supabaseEnabled } from './supabase'

let snapshotPromise=null

function requireRemote(){
  if(!supabaseEnabled) throw new Error('Le registre financier Supabase n’est pas activé.')
}

function unwrap(result){
  if(result.error) throw result.error
  return result.data
}

export async function loadFinanceSnapshot(){
  requireRemote()
  if(!snapshotPromise) snapshotPromise=supabase.rpc('finance_snapshot').then(result=>{
    const data=unwrap(result)
    return {payments:Array.isArray(data?.payments)?data.payments:[],sessions:Array.isArray(data?.sessions)?data.sessions:[]}
  }).catch(error=>{snapshotPromise=null;throw error})
  return snapshotPromise
}

export function invalidateFinanceSnapshot(){snapshotPromise=null}

export async function getFinanceBalance(patientId,treatmentId){
  requireRemote()
  const data=unwrap(await supabase.rpc('finance_account_balance',{p_patient_app_id:patientId,p_treatment_id:treatmentId}))
  return {total:Number(data?.total||0),paid:Number(data?.paid||0),remaining:Number(data?.remaining||0)}
}

export async function recordFinancePayment(payload){
  requireRemote()
  const data=unwrap(await supabase.rpc('record_finance_payment',{
    p_patient_app_id:payload.patientId,
    p_treatment_id:payload.treatmentId,
    p_doctor_id:payload.doctorId||'',
    p_amount:Number(payload.paid),
    p_plan:payload.plan||'Comptant',
    p_method:payload.method,
    p_idempotency_key:payload.idempotencyKey,
    p_session_id:payload.sessionId||null,
    p_expected_total:Number(payload.total||0)||null
  }))
  invalidateFinanceSnapshot()
  return data
}

export async function correctFinancePayment(transactionId,amount,reason){
  requireRemote()
  const data=unwrap(await supabase.rpc('correct_finance_payment',{
    p_transaction_id:transactionId,
    p_amount:Number(amount),
    p_reason:reason,
    p_idempotency_key:`correction:${transactionId}:${crypto.randomUUID()}`
  }))
  invalidateFinanceSnapshot()
  return data
}

export async function openFinanceSession(openingCash){
  requireRemote()
  const data=unwrap(await supabase.rpc('open_finance_session',{p_opening_cash:Number(openingCash||0)}))
  invalidateFinanceSnapshot()
  return data
}

export async function submitFinanceSession(sessionId,countedCash){
  requireRemote()
  const data=unwrap(await supabase.rpc('submit_finance_session',{p_session_id:sessionId,p_counted_cash:Number(countedCash)}))
  invalidateFinanceSnapshot()
  return data
}

export async function validateFinanceSession(sessionId){
  requireRemote()
  const data=unwrap(await supabase.rpc('validate_finance_session',{p_session_id:sessionId}))
  invalidateFinanceSnapshot()
  return data
}
