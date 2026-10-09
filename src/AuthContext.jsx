import React, { createContext, useContext, useEffect, useState } from 'react'
import { clearRemoteClinicCache, ensureRemoteClinic, loadCurrentAccessContext, seedRemoteData, supabase, supabaseEnabled } from './services/supabase'

const AuthContext = createContext(null)

export function AuthProvider({children}){
  const [session,setSession]=useState(null); const [loading,setLoading]=useState(supabaseEnabled); const [ready,setReady]=useState(!supabaseEnabled); const [error,setError]=useState(''); const [setupError,setSetupError]=useState(''); const [access,setAccess]=useState(null)
  useEffect(()=>{
    if(!supabaseEnabled){setLoading(false);return}
    let live=true
    supabase.auth.getSession().then(({data,error:sessionError})=>{if(live){if(sessionError)setError(sessionError.message);setSession(data.session);setLoading(false)}})
    const {data:listener}=supabase.auth.onAuthStateChange((_event,next)=>{if(live)setSession(next)})
    return ()=>{live=false;listener.subscription.unsubscribe()}
  },[])
  async function prepare(user){ const clinicId=await ensureRemoteClinic(user.user_metadata?.full_name || user.email?.split('@')[0] || 'Administrateur'); await seedRemoteData(); const nextAccess=await loadCurrentAccessContext(); setAccess(nextAccess); return clinicId }
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
  async function signOut(){clearRemoteClinicCache();await supabase.auth.signOut()}
  return <AuthContext.Provider value={{session,access,loading,ready,error,setupError,signIn,signUp,resendConfirmation,signOut,supabaseEnabled}}>{children}</AuthContext.Provider>
}

export function useAuth(){return useContext(AuthContext)}
