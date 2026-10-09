import { supabase, supabaseEnabled } from './supabase'

function requireRemote(){if(!supabaseEnabled)throw new Error('Le dossier patient Supabase n’est pas activé.')}
function unwrap(result){if(result.error)throw result.error;return result.data}

export async function loadPatients(){requireRemote();const data=unwrap(await supabase.rpc('patients_snapshot'));return Array.isArray(data)?data:[]}
export async function createPatient(payload){requireRemote();return unwrap(await supabase.rpc('create_patient_record',{p_payload:payload}))}
export async function updatePatient(id,payload){requireRemote();return unwrap(await supabase.rpc('update_patient_record',{p_app_id:id,p_payload:payload}))}
export async function deletePatient(id){requireRemote();return unwrap(await supabase.rpc('delete_patient_record',{p_app_id:id}))}
export async function loadPatientMedical(id){requireRemote();return unwrap(await supabase.rpc('patient_medical_snapshot',{p_app_id:id}))}
export async function updatePatientMedical(id,medicalAlerts,emergencyContact={}){requireRemote();return unwrap(await supabase.rpc('update_patient_medical_record',{p_app_id:id,p_medical_alerts:medicalAlerts||null,p_emergency_contact:emergencyContact}))}
