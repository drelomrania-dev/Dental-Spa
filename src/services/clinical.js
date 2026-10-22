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
      priceTargets:Array.isArray(data?.priceTargets)?data.priceTargets:[],
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
    p_create_plan:Boolean(payload.createPlan),
    p_appointment_app_id:payload.appointmentId||null
  }))
  invalidateClinicalSnapshot()
  return data
}

export async function updateClinicalVisit(id,notes,followUp){
  requireRemote()
  const data=unwrap(await supabase.rpc('update_clinical_visit',{p_visit_app_id:id,p_notes:notes,p_follow_up:followUp||null}))
  invalidateClinicalSnapshot()
  return data
}

export async function updateTreatmentPlanStatus(id,status){
  requireRemote()
  const data=unwrap(await supabase.rpc('update_treatment_plan_status',{p_plan_app_id:id,p_status:status}))
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
