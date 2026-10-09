import { supabase, supabaseEnabled } from './supabase'

function requireRemote(){if(!supabaseEnabled)throw new Error('Les ressources Supabase ne sont pas activées.')}
function unwrap(result){if(result.error)throw result.error;return result.data}

export async function loadResources(){
  requireRemote()
  const data=unwrap(await supabase.rpc('clinic_resources_snapshot'))
  return Array.isArray(data)?data:[]
}

export async function saveResource(payload){
  requireRemote()
  return unwrap(await supabase.rpc('upsert_clinic_resource',{
    p_app_id:payload.id||null,p_name:payload.name,p_resource_type:payload.type,p_active:payload.active!==false
  }))
}
