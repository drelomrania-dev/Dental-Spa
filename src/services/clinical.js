import { supabase, supabaseEnabled } from './supabase'

let snapshotPromise=null

function requireRemote(){if(!supabaseEnabled)throw new Error('Les workflows cliniques Supabase ne sont pas activés.')}
function unwrap(result){if(result.error)throw result.error;return result.data}
export function invalidateClinicalSnapshot(){snapshotPromise=null}

export async function loadClinicalSnapshot(){
  requireRemote()
  if(!snapshotPromise)snapshotPromise=supabase.rpc('clinical_snapshot').then(result=>{
    const data=unwrap(result)
    return {
      visits:Array.isArray(data?.visits)?data.visits:[],
      treatmentPlans:Array.isArray(data?.plans)?data.plans:[],
      priceRequests:Array.isArray(data?.priceRequests)?data.priceRequests:[]
    }
  }).catch(error=>{snapshotPromise=null;throw error})
  return snapshotPromise
}

export async function recordClinicalVisit(payload){
  requireRemote()
  const data=unwrap(await supabase.rpc('record_clinical_visit',{
    p_patient_app_id:payload.patientId,
    p_practitioner_app_id:payload.doctorId,
    p_notes:payload.notes,
    p_follow_up:payload.followUp||null,
    p_service_app_id:payload.treatmentId||null,
    p_create_plan:Boolean(payload.createPlan)
  }))
  invalidateClinicalSnapshot()
  return data
}

export async function requestClinicalPrice(payload){
  requireRemote()
  const data=unwrap(await supabase.rpc('create_clinical_price_request',{
    p_patient_app_id:payload.patientId,
    p_service_app_id:payload.treatmentId,
    p_plan_app_id:payload.planId||null,
    p_plan_item_app_id:payload.planItemId||null,
    p_proposed_price:Number(payload.proposedPrice),
    p_reason:payload.reason
  }))
  invalidateClinicalSnapshot()
  return data
}

export async function decideClinicalPrice(requestId,status,reason){
  requireRemote()
  const data=unwrap(await supabase.rpc('decide_clinical_price_request',{
    p_request_app_id:requestId,p_status:status,p_reason:reason||null
  }))
  invalidateClinicalSnapshot()
  return data
}
