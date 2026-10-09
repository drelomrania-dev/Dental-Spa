import { remoteClinicId, supabase, supabaseEnabled } from './supabase'

export const permissionCatalog=[
  ['Rendez-vous',['appointments.view','appointments.create','appointments.edit','appointments.cancel']],
  ['Patients',['patients.basic.view','patients.create','patients.edit','patients.medical.view']],
  ['Clinique',['clinical.view','clinical.edit','plans.create']],
  ['Services & prix',['services.view','services.manage','priceRequests.create','priceRequests.approve']],
  ['Paiements',['payments.collect','payments.receipt','payments.view.own','payments.view.all','payments.correct']],
  ['Caisse & rapports',['sessions.own','sessions.manage','reports.finance','reports.export']],
  ['Acquisition',['acquisition.view','acquisition.manage']],
  ['Administration',['settings.manage','staff.manage','permissions.manage','audit.view']]
]

export async function listRolePermissions(){
  if(!supabaseEnabled)return []
  const {data,error}=await supabase.from('role_permissions').select('role,permission,scope').order('role').order('permission')
  if(error)throw error
  return data
}

export async function setRolePermission(role,permission,enabled,scope='clinic'){
  if(!supabaseEnabled)return true
  const clinicId=await remoteClinicId()
  if(enabled){const {error}=await supabase.from('role_permissions').upsert({clinic_id:clinicId,role,permission,scope},{onConflict:'clinic_id,role,permission'});if(error)throw error}
  else{const {error}=await supabase.from('role_permissions').delete().eq('clinic_id',clinicId).eq('role',role).eq('permission',permission);if(error)throw error}
  return true
}
