import React, { useState } from 'react'
import { ClipboardPlus, FileText, Plus } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money } from '../utils'

const blank={appointmentId:'',patientId:'',doctorId:'',notes:'',followUp:'',treatmentId:'',createPlan:true}

export default function Clinical(){
  const { patients, doctors, treatments, appointments, visits, treatmentPlans, createClinicalVisit, updateClinicalVisit, updateTreatmentPlanStatus, patientName, doctorName, clinic, can } = useData()
  const canEdit=can('clinical.edit'),canCreatePlan=can('plans.create')
  const [form,setForm]=useState(blank),[open,setOpen]=useState(false),[editing,setEditing]=useState(''),[error,setError]=useState(''),[saving,setSaving]=useState(false)
  const eligible=appointments.filter(a=>!['Annulé','No-show'].includes(a.status)&&!visits.some(v=>v.appointmentId===a.id))
  function chooseAppointment(id){const a=eligible.find(row=>row.id===id);setForm(f=>({...f,appointmentId:id,patientId:a?.patientId||f.patientId,doctorId:a?.doctorId||f.doctorId,treatmentId:a?.treatmentId||f.treatmentId}))}
  async function submit(e){e.preventDefault();setSaving(true);setError('');try{
    if(editing)await updateClinicalVisit(editing,form.notes,form.followUp)
    else await createClinicalVisit({...form,createPlan:canCreatePlan&&form.createPlan})
    setOpen(false);setEditing('');setForm(blank)
  }catch(err){setError(err.message||'La consultation n’a pas pu être enregistrée.')}finally{setSaving(false)}}
  async function changePlan(plan,status){setError('');try{await updateTreatmentPlanStatus(plan.id,status)}catch(err){setError(err.message||'Le plan n’a pas pu être mis à jour.')}}
  return <>
    <Topbar title="Clinique" subtitle="Consultations, notes et plans de traitement — accès réservé aux profils autorisés."/>
    <div className="dashboard-toolbar"><span>{visits.length} consultation(s) · {treatmentPlans.length} plan(s)</span>{canEdit&&<button className="primary-btn" onClick={()=>{setForm(blank);setEditing('');setError('');setOpen(true)}}><Plus size={16}/> Ouvrir une consultation</button>}</div>
    {error&&!open&&<div className="form-error" role="alert">{error}</div>}
    <div className="dashboard-bottom-grid">
      <section className="panel"><div className="panel-head"><div><h3>Consultations récentes</h3><p>Notes cliniques et suivi</p></div><span className="soft-badge"><FileText size={13}/> Clinique</span></div>
        {visits.length?<div className="profile-list">{visits.map(v=><div className="profile-list-row" key={v.id}><div className="profile-date"><strong>{v.date}</strong><span>{doctorName(v.doctorId)}</span></div><div><strong>{patientName(v.patientId)}</strong><span>{v.appointmentId?`Rendez-vous lié · ${v.notes}`:v.notes||'Aucune note'}</span>{v.followUp&&<small>Suivi : {v.followUp}</small>}</div>{canEdit&&<button className="ghost-btn" onClick={()=>{setEditing(v.id);setForm({...blank,notes:v.notes,followUp:v.followUp||''});setError('');setOpen(true)}}>Modifier</button>}</div>)}</div>:<div className="empty-state">Aucune consultation enregistrée.</div>}
      </section>
      <section className="panel"><div className="panel-head"><div><h3>Plans de traitement</h3><p>Plans liés aux consultations</p></div><ClipboardPlus size={18}/></div>
        {treatmentPlans.length?<div className="profile-list">{treatmentPlans.map(p=><div className="profile-list-row" key={p.id}><div className="profile-date"><strong>{p.status}</strong><span>{p.date}</span></div><div><strong>{patientName(p.patientId)}</strong><span>{money(p.total,clinic.currency)} · {p.items?.length||0} étape(s)</span><small>{p.visitId?'Consultation liée':'Plan sans consultation liée'}</small></div>{canCreatePlan&&<select aria-label={`Statut du plan de ${patientName(p.patientId)}`} value={p.status} onChange={e=>changePlan(p,e.target.value)}><option>Proposé</option><option>Accepté</option><option>Rejeté</option></select>}</div>)}</div>:<div className="empty-state">Les plans créés depuis une consultation apparaîtront ici.</div>}
      </section>
    </div>
    {canEdit&&<Modal open={open} onClose={()=>setOpen(false)} title={editing?'Modifier la consultation':'Ouvrir une consultation'} subtitle="Les notes cliniques restent séparées des informations d’accueil."><form onSubmit={submit} className="form-grid">
      {!editing&&<><label className="full">Rendez-vous lié<select value={form.appointmentId} onChange={e=>chooseAppointment(e.target.value)}><option value="">Consultation sans rendez-vous</option>{eligible.map(a=><option key={a.id} value={a.id}>{a.date} {a.time} · {patientName(a.patientId)} · {doctorName(a.doctorId)}</option>)}</select></label><label>Patient<select required disabled={Boolean(form.appointmentId)} value={form.patientId} onChange={e=>setForm({...form,patientId:e.target.value})}><option value="">Choisir</option>{patients.map(p=><option key={p.id} value={p.id}>{p.firstName} {p.lastName}</option>)}</select></label><label>Praticien<select required disabled={Boolean(form.appointmentId)} value={form.doctorId} onChange={e=>setForm({...form,doctorId:e.target.value})}><option value="">Choisir</option>{doctors.filter(d=>d.active!==false).map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label><label className="full">Service effectué<select value={form.treatmentId} onChange={e=>setForm({...form,treatmentId:e.target.value})}><option value="">Aucun pour l’instant</option>{treatments.filter(t=>t.active!==false).map(t=><option key={t.id} value={t.id}>{t.name} · {money(t.price,clinic.currency)}</option>)}</select></label>{form.treatmentId&&canCreatePlan&&<label className="full check-label"><input type="checkbox" checked={form.createPlan} onChange={e=>setForm({...form,createPlan:e.target.checked})}/> Créer aussi un plan de traitement proposé</label>}</>}
      <label className="full">Notes cliniques<textarea required minLength="2" value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label><label className="full">Instructions de suivi<textarea value={form.followUp} onChange={e=>setForm({...form,followUp:e.target.value})}/></label>{error&&<div className="form-error full" role="alert">{error}</div>}<div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn" disabled={saving}><ClipboardPlus size={15}/> {saving?'Enregistrement…':'Enregistrer la consultation'}</button></div>
    </form></Modal>}
  </>
}
