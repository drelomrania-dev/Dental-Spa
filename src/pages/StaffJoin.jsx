import React, { useEffect, useState } from 'react'
import { CheckCircle2, LockKeyhole, UserRoundCheck } from 'lucide-react'
import { useParams } from 'react-router-dom'
import { useAuth } from '../AuthContext'
import { loadPublicStaffInvitation } from '../services/staff'
import { supabase } from '../services/supabase'

const inviteKey='dentalflow:staff-invitation-token'

export default function StaffJoin(){
  const {token}=useParams();const {session,loading:authLoading,signIn,signOut,acceptStaffInvitation}=useAuth()
  useState(()=>{localStorage.setItem(inviteKey,token);return true})
  const [invitation,setInvitation]=useState(null);const [loading,setLoading]=useState(true);const [error,setError]=useState('');const [password,setPassword]=useState('');const [busy,setBusy]=useState(false);const [message,setMessage]=useState('')
  useEffect(()=>{let live=true;loadPublicStaffInvitation(token).then(data=>{if(live)setInvitation(data)}).catch(err=>{if(live)setError(err.message||'Invitation indisponible.')}).finally(()=>{if(live)setLoading(false)});return()=>{live=false}},[token])
  const emailMatches=session?.user?.email?.toLowerCase()===invitation?.email?.toLowerCase()
  async function login(e){e.preventDefault();setBusy(true);setError('');try{await signIn(invitation.email,password)}catch(err){setError(err.message||'Connexion impossible.')}finally{setBusy(false)}}
  async function accept(e){e.preventDefault();setBusy(true);setError('');try{const {error:updateError}=await supabase.auth.updateUser({password});if(updateError)throw updateError;await acceptStaffInvitation(token);setMessage('Accès activé. Ouverture du cabinet…');window.setTimeout(()=>window.location.replace('/'),700)}catch(err){setError(err.message||'Activation impossible.')}finally{setBusy(false)}}
  if(loading||authLoading)return <main className="auth-page"><div className="auth-card"><LockKeyhole size={30}/><h1>Vérification de l’invitation…</h1></div></main>
  if(!invitation)return <main className="auth-page"><section className="auth-card"><LockKeyhole size={30}/><h1>Lien indisponible</h1><p>{error||'Cette invitation est expirée, révoquée ou déjà utilisée.'}</p></section></main>
  return <main className="auth-page"><section className="auth-card staff-join-card"><div className="public-brand"><UserRoundCheck size={20}/><span>{invitation.clinicName}</span></div><h1>Rejoindre le cabinet</h1><p>Votre accès <strong>{invitation.role==='practitioner'?'Praticien':'Assistant / accueil'}</strong> est réservé à <strong>{invitation.email}</strong>.</p>{session&&!emailMatches?<div className="form-error">Vous êtes connecté avec {session.user.email}. Déconnectez-vous pour utiliser le compte invité.</div>:null}{error&&<div className="form-error">{error}</div>}{message&&<div className="success-strip"><CheckCircle2 size={16}/>{message}</div>}{!session?<form className="auth-form" onSubmit={login}><label>Email<input value={invitation.email} readOnly/></label><label>Mot de passe existant<input required type="password" minLength="8" value={password} onChange={e=>setPassword(e.target.value)}/></label><button className="primary-btn large" disabled={busy}>{busy?'Connexion…':'Se connecter et accepter'}</button><p className="staff-invite-help">Pour une première connexion, ouvrez le lien sécurisé complet fourni par l’administrateur.</p></form>:emailMatches?<form className="auth-form" onSubmit={accept}><label>Choisir un mot de passe<input required type="password" minLength="8" autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)}/></label><button className="primary-btn large" disabled={busy}>{busy?'Activation…':'Activer mon accès'}</button></form>:<button className="ghost-btn full-btn" onClick={signOut}>Se déconnecter</button>}</section></main>
}
