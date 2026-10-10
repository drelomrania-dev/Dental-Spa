import React, { createContext, useContext, useEffect, useState } from 'react'
import { clearRemoteClinicCache, ensureRemoteClinic, loadCurrentAccessContext, seedRemoteData, supabase, supabaseEnabled } from './services/supabase'

const AuthContext = createContext(null)
const staffInvitationKey='dentalflow:staff-invitation-token'

export function AuthProvider({children}){
  const [session,setSession]=useState(null); const [loading,setLoading]=useState(supabaseEnabled); const [ready,setReady]=useState(!supabaseEnabled); const [error,setError]=useState(''); const [setupError,setSetupError]=useState(''); const [access,setAccess]=useState(null);const [bootstrapAvailable,setBootstrapAvailable]=useState(false)
  useEffect(()=>{
    if(!supabaseEnabled){setLoading(false);return}
    let live=true
    Promise.all([supabase.auth.getSession(),supabase.rpc('public_bootstrap_available')]).then(([{data,error:sessionError},{data:canBootstrap}])=>{if(live){if(sessionError)setError(sessionError.message);setSession(data.session);setBootstrapAvailable(Boolean(canBootstrap));setLoading(false)}})
    const {data:listener}=supabase.auth.onAuthStateChange((_event,next)=>{if(live)setSession(next)})
    return ()=>{live=false;listener.subscription.unsubscribe()}
  },[])
  async function claimPendingInvitation(){const token=localStorage.getItem(staffInvitationKey);if(!token)return null;const {data,error:claimError}=await supabase.rpc('claim_staff_invitation',{p_token:token});if(claimError)throw claimError;localStorage.removeItem(staffInvitationKey);return data}
  async function prepare(user){ await claimPendingInvitation(); const clinicId=await ensureRemoteClinic(user.user_metadata?.full_name || user.email?.split('@')[0] || 'Administrateur'); await seedRemoteData(); const nextAccess=await loadCurrentAccessContext(); setAccess(nextAccess); return clinicId }
  useEffect(()=>{
    if(!supabaseEnabled||!session?.user){clearRemoteClinicCache();setAccess(null);setReady(!supabaseEnabled);setSetupError('');return}
    let live=true
    clearRemoteClinicCache();setReady(false);setSetupError('')
    prepare(session.user).then(()=>{if(live)setReady(true)}).catch(err=>{console.error('Supabase clinic setup failed',err);if(live)setSetupError(err.message||'Impossible de préparer le cabinet Supabase.')})
    return ()=>{live=false}
  },[session?.user?.id])
  async function signIn(email,password){setError('');const {data,error:authError}=await supabase.auth.signInWithPassword({email,password});if(authError){setError(authError.message);throw authError}setSession(data.session);return data}
  async function signUp(name,email,password){setError('');const {data,error:authError}=await supabase.auth.signUp({email,password,options:{data:{full_name:name}}});if(authError){setError(authError.message);throw authError}if(data.session)setSession(data.session);return data}
  async function resendConfirmation(email){setError('');const {error:authError}=await supabase.auth.resend({type:'signup',email});if(authError){setError(authError.message);throw authError}return true}
  async function acceptStaffInvitation(token){localStorage.setItem(staffInvitationKey,token);const claimed=await claimPendingInvitation();clearRemoteClinicCache();const nextAccess=claimed||await loadCurrentAccessContext();setAccess(nextAccess);setSetupError('');setReady(true);return nextAccess}
  async function signOut(){clearRemoteClinicCache();await supabase.auth.signOut()}
  return <AuthContext.Provider value={{session,access,loading,ready,error,setupError,bootstrapAvailable,signIn,signUp,resendConfirmation,acceptStaffInvitation,signOut,supabaseEnabled}}>{children}</AuthContext.Provider>
}

export function useAuth(){return useContext(AuthContext)}
