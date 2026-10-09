import { supabase, supabaseEnabled } from './supabase'

let snapshotPromise=null
function requireRemote(){if(!supabaseEnabled)throw new Error('L’agenda Supabase n’est pas activé.')}
function unwrap(result){if(result.error)throw result.error;return result.data}
export function invalidateAppointments(){snapshotPromise=null}

export async function loadAppointments(){
  requireRemote()
  if(!snapshotPromise)snapshotPromise=supabase.rpc('appointments_snapshot').then(unwrap).then(data=>Array.isArray(data)?data:[]).catch(error=>{snapshotPromise=null;throw error})
  return snapshotPromise
}

export async function createAppointment(payload){
  requireRemote()
  const data=unwrap(await supabase.rpc('create_internal_appointment',{
    p_patient_app_id:payload.patientId,p_practitioner_app_id:payload.doctorId,p_service_app_id:payload.treatmentId||null,
    p_date:payload.date,p_time:payload.time,p_duration:Number(payload.duration),p_reason:payload.reason,p_status:payload.status||'Confirmé',
    p_estimated_amount:payload.estimatedAmount===''?null:Number(payload.estimatedAmount),p_room_id:payload.roomId||null
  }))
  invalidateAppointments();return data
}

export async function updateAppointment(id,payload){
  requireRemote()
  const data=unwrap(await supabase.rpc('update_internal_appointment',{
    p_app_id:id,p_patient_app_id:payload.patientId,p_practitioner_app_id:payload.doctorId,p_service_app_id:payload.treatmentId||null,
    p_date:payload.date,p_time:payload.time,p_duration:Number(payload.duration),p_reason:payload.reason,p_status:payload.status,
    p_estimated_amount:payload.estimatedAmount===''?null:Number(payload.estimatedAmount),p_room_id:payload.roomId||null
  }))
  invalidateAppointments();return data
}

export async function loadPublicBookingManagement(token){requireRemote();return unwrap(await supabase.rpc('public_booking_manage',{p_token:token}))}
export async function reschedulePublicBooking(token,date,time){requireRemote();return unwrap(await supabase.rpc('public_reschedule_booking',{p_token:token,p_date:date,p_time:time}))}
export async function cancelPublicBooking(token,reason){requireRemote();return unwrap(await supabase.rpc('public_cancel_booking',{p_token:token,p_reason:reason||null}))}
