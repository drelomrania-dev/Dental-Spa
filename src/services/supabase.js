import { createClient } from '@supabase/supabase-js'
import { seedData } from '../data/seed'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY
export const supabaseEnabled = import.meta.env.VITE_DATA_BACKEND === 'supabase' && Boolean(url && key)
export const supabase = supabaseEnabled ? createClient(url, key, { auth:{ persistSession:true, autoRefreshToken:true, detectSessionInUrl:true } }) : null

let cachedClinicId = null

export function clearRemoteClinicCache(){
  cachedClinicId = null
}

export async function ensureRemoteClinic(displayName='Administrateur'){
  if(!supabaseEnabled) return null
  const { data, error } = await supabase.rpc('bootstrap_first_admin', { p_name:displayName })
  if(error) throw error
  cachedClinicId = data
  return data
}

export async function remoteClinicId(){
  if(cachedClinicId) return cachedClinicId
  const { data, error } = await supabase.rpc('current_clinic_id')
  if(error) throw error
  if(!data) throw new Error('Aucun profil de cabinet Supabase n’est associé à ce compte.')
  cachedClinicId = data
  return data
}

export async function seedRemoteData(){
  const clinicId = await remoteClinicId()
  const { count, error:countError } = await supabase.from('app_records').select('*',{count:'exact',head:true})
  if(countError) throw countError
  if(count) return false
  const rows = Object.entries(seedData).flatMap(([collection,items]) => items.map(item => ({clinic_id:clinicId,collection,id:item.id,data:item})))
  if(rows.length){ const { error } = await supabase.from('app_records').insert(rows); if(error) throw error }
  return true
}
