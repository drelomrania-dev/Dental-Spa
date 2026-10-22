import React, { useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, CalendarDays, CreditCard, Mail, Phone, ShieldAlert, UserRound, WalletCards } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'
import { loadPatientMedical, loadPatientTimeline } from '../services/patients'
import { supabaseEnabled } from '../services/supabase'

export default function PatientProfile(){
  const { patientId } = useParams()
  const { patients, appointments, payments, visits, treatmentPlans, balances, loading, doctorName, treatmentName, clinic, update, can } = useData()
  const [medical,setMedical]=useState(null);const [medicalError,setMedicalError]=useState('')
  const [timeline,setTimeline]=useState(null);const [timelineError,setTimelineError]=useState('')
  const [editingBasic,setEditingBasic]=useState(false),[basicForm,setBasicForm]=useState({}),[basicError,setBasicError]=useState(''),[savingBasic,setSavingBasic]=useState(false)
  const patient = patients.find(p => p.id === patientId)
  const patientAppointments = useMemo(() => appointments
    .filter(a => a.patientId === patientId)
    .sort((a,b) => `${b.date} ${b.time}`.localeCompare(`${a.date} ${a.time}`)), [appointments, patientId])
  const patientPayments = useMemo(() => payments
    .filter(p => p.patientId === patientId)
    .sort((a,b) => `${b.date} ${b.reference}`.localeCompare(`${a.date} ${a.reference}`)), [payments, patientId])
  useEffect(()=>{let live=true;if(!supabaseEnabled||!can('patients.medical.view'))return()=>{live=false};loadPatientMedical(patientId).then(value=>{if(live)setMedical(value)}).catch(()=>{if(live)setMedicalError('Les informations médicales ne sont pas disponibles.')});return()=>{live=false}},[patientId,can])
  useEffect(()=>{let live=true;if(!supabaseEnabled)return()=>{live=false};setTimeline(null);setTimelineError('');loadPatientTimeline(patientId).then(value=>{if(live)setTimeline(value)}).catch(()=>{if(live)setTimelineError('La chronologie du patient n’est pas disponible.')});return()=>{live=false}},[patientId])

  if (loading) return <Topbar title="Chargement du profil…" subtitle="Récupération des informations du patient."/>

  if (!patient) return <>
    <Topbar title="Patient introuvable" subtitle="Ce dossier n’est pas disponible dans la base actuelle."/>
    <Link className="ghost-btn profile-back" to="/patients"><ArrowLeft size={16}/> Retour aux patients</Link>
  </>

  const fullName = `${patient.firstName} ${patient.lastName}`
  const visibleAppointments=timeline?.appointments??patientAppointments
  const visiblePayments=timeline?.payments??patientPayments
  const visibleVisits=timeline?.visits??visits.filter(v=>v.patientId===patientId)
  const visiblePlans=timeline?.plans??treatmentPlans.filter(p=>p.patientId===patientId)
  const canSeePayments=can('payments.view.all')||can('payments.view.own')
  const canSeeClinical=can('clinical.view')
  const upcoming = visibleAppointments.filter(a => a.date >= todayISO())
  const totalPaid = visiblePayments.reduce((sum,p) => sum + Number(p.paid || 0), 0)
  const totalRemaining = balances.filter(b=>b.patientId===patientId).reduce((sum,p) => sum + Number(p.remaining || 0), 0)
  async function saveBasic(e){e.preventDefault();setSavingBasic(true);setBasicError('');try{await update('patients',patientId,basicForm);setEditingBasic(false)}catch(err){setBasicError(err.message||'Le profil n’a pas pu être mis à jour.')}finally{setSavingBasic(false)}}

  return <>
    <Topbar title={fullName} subtitle="Profil patient et historique des interactions au cabinet."/>
    <div className="profile-toolbar">
      <Link className="ghost-btn" to="/patients"><ArrowLeft size={15}/> Tous les patients</Link>
      <div>{can('patients.edit')&&<button className="ghost-btn" onClick={()=>{setBasicForm({firstName:patient.firstName,lastName:patient.lastName,phone:patient.phone||'',email:patient.email||'',address:patient.address||''});setBasicError('');setEditingBasic(true)}}>Modifier les coordonnées</button>}{can('appointments.create')&&<Link className="ghost-btn" to="/appointments"><CalendarDays size={15}/> Nouveau rendez-vous</Link>}{can('payments.collect')&&<Link className="primary-btn" to="/payments"><CreditCard size={15}/> Nouveau paiement</Link>}</div>
    </div>
    <section className="profile-hero panel">
      <div className="profile-identity"><div className="profile-avatar"><UserRound size={25}/></div><div><span className="soft-badge">{patient.status || 'Patient'}</span><h2>{fullName}</h2><p>Patient depuis le {patient.createdAt || '—'}</p></div></div>
      <div className="profile-contact">
        <div><Phone size={16}/><span>{patient.phone || 'Téléphone non renseigné'}</span></div>
        <div><Mail size={16}/><span>{patient.email || 'Email non renseigné'}</span></div>
      </div>
    </section>
    {can('patients.medical.view')&&<section className="panel patient-medical-summary"><div><ShieldAlert size={18}/><span><strong>Alertes médicales</strong><small>Visible uniquement par les profils cliniques autorisés</small></span></div>{medicalError?<p className="danger-text">{medicalError}</p>:<p>{medical?.medicalAlerts||'Aucune alerte médicale enregistrée.'}</p>}</section>}
    {timelineError&&<div className="form-error" role="alert">{timelineError}</div>}
    <div className="profile-stats">
      <div className="panel"><span><CalendarDays size={15}/> Rendez-vous à venir</span><strong>{upcoming.length}</strong></div>
      {canSeePayments&&<div className="panel"><span><CreditCard size={15}/> Paiements visibles</span><strong>{money(totalPaid,clinic.currency)}</strong></div>}
      {can('payments.view.all')&&<div className="panel"><span><WalletCards size={15}/> Solde restant</span><strong>{money(totalRemaining,clinic.currency)}</strong></div>}
    </div>
    <div className="profile-columns">
      <section className="panel">
        <div className="panel-head"><div><h3>Rendez-vous</h3><p>Visites passées et planifiées</p></div>{can('appointments.view')&&<Link to="/appointments">Voir le planning</Link>}</div>
        {visibleAppointments.length ? <div className="profile-list">{visibleAppointments.map(a=><div className="profile-list-row" key={a.id}>
          <div className="profile-date"><strong>{a.date}</strong><span>{a.time}</span></div>
          <div><strong>{a.reason || 'Consultation'}</strong><span>{doctorName(a.doctorId)} · {a.duration} min</span></div>
          <span className={`status ${a.status === 'Confirmé' ? 'ok' : a.status === 'Annulé' ? 'bad' : 'wait'}`}>{a.status}</span>
        </div>)}</div> : <div className="empty-state">Aucun rendez-vous enregistré.</div>}
      </section>
      {canSeePayments&&<section className="panel">
        <div className="panel-head"><div><h3>Paiements</h3><p>Références des encaissements autorisés</p></div>{can('payments.view.all')&&<Link to="/payment-history">Historique complet</Link>}</div>
        {visiblePayments.length ? <div className="profile-list">{visiblePayments.map(p=><div className="profile-list-row" key={p.id}>
          <div className="profile-date"><strong>{p.date}</strong><span>{p.reference}</span></div>
          <div><strong>{treatmentName(p.treatmentId)}</strong><span>{p.method} · payé {money(p.paid,clinic.currency)}</span></div>
          <span className="status ok">{p.reference}</span>
        </div>)}</div> : <div className="empty-state">Aucun paiement enregistré.</div>}
      </section>}
    </div>
    {canSeeClinical&&<div className="profile-columns"><section className="panel"><div className="panel-head"><div><h3>Consultations</h3><p>Notes cliniques autorisées</p></div><Link to="/clinical">Clinique</Link></div>{visibleVisits.length?<div className="profile-list">{visibleVisits.map(v=><div className="profile-list-row" key={v.id}><div className="profile-date"><strong>{v.date}</strong><span>{doctorName(v.doctorId)}</span></div><div><strong>{v.appointmentId?'Liée au rendez-vous':'Sans rendez-vous lié'}</strong><span>{v.notes}</span>{v.followUp&&<small>Suivi : {v.followUp}</small>}</div></div>)}</div>:<div className="empty-state">Aucune consultation.</div>}</section><section className="panel"><div className="panel-head"><div><h3>Plans de traitement</h3><p>Étapes et prix décidés</p></div></div>{visiblePlans.length?<div className="profile-list">{visiblePlans.map(p=><div className="profile-list-row" key={p.id}><div className="profile-date"><strong>{p.date}</strong><span>{p.status}</span></div><div><strong>{money(p.total,clinic.currency)}</strong><span>{p.items?.map(i=>`${i.name} · ${money(i.effectivePrice,clinic.currency)}`).join(', ')}</span></div></div>)}</div>:<div className="empty-state">Aucun plan.</div>}</section></div>}
    <Modal open={editingBasic} onClose={()=>setEditingBasic(false)} title="Modifier les coordonnées" subtitle="Informations administratives du patient uniquement."><form className="form-grid" onSubmit={saveBasic}><label>Prénom<input required value={basicForm.firstName||''} onChange={e=>setBasicForm({...basicForm,firstName:e.target.value})}/></label><label>Nom<input required value={basicForm.lastName||''} onChange={e=>setBasicForm({...basicForm,lastName:e.target.value})}/></label><label>Téléphone<input value={basicForm.phone||''} onChange={e=>setBasicForm({...basicForm,phone:e.target.value})}/></label><label>Email<input type="email" value={basicForm.email||''} onChange={e=>setBasicForm({...basicForm,email:e.target.value})}/></label><label className="full">Adresse<input value={basicForm.address||''} onChange={e=>setBasicForm({...basicForm,address:e.target.value})}/></label>{basicError&&<div className="form-error full" role="alert">{basicError}</div>}<div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setEditingBasic(false)}>Annuler</button><button className="primary-btn" disabled={savingBasic}>{savingBasic?'Enregistrement…':'Enregistrer'}</button></div></form></Modal>
  </>
}
