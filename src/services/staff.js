import { supabase, supabaseEnabled } from './supabase'

function requireRemote(){if(!supabaseEnabled)throw new Error('La gestion du personnel nécessite Supabase.')}
function unwrap(result){if(result.error)throw result.error;return result.data}

export async function loadStaffManagement(){requireRemote();return unwrap(await supabase.rpc('staff_management_snapshot'))}

export async function createStaffAccess({email,name,role}){
  requireRemote()
  const invitation=unwrap(await supabase.rpc('create_staff_invitation',{p_email:email,p_display_name:name,p_role:role,p_expires_days:7}))
  const redirectTo=`${window.location.origin}${invitation.path}`
  const {data,error}=await supabase.functions.invoke('staff-invite-link',{body:{token:invitation.token,redirectTo}})
  if(error||!data?.actionLink){await supabase.rpc('revoke_staff_invitation',{p_invitation_id:invitation.id});throw error||new Error('Lien d’accès indisponible.')}
  return {...invitation,actionLink:data.actionLink}
}

export async function revokeStaffAccess(id){requireRemote();return unwrap(await supabase.rpc('revoke_staff_invitation',{p_invitation_id:id}))}
export async function loadPublicStaffInvitation(token){requireRemote();return unwrap(await supabase.rpc('public_staff_invitation',{p_token:token}))}
