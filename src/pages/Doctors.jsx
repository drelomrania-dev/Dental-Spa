import React, { useState } from 'react'
import { Mail, Phone, Plus, Stethoscope } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'

const weekdays=[['1','Lun'],['2','Mar'],['3','Mer'],['4','Jeu'],['5','Ven'],['6','Sam'],['7','Dim']]
const emptyDoctor={name:'',specialty:'Dentisterie générale',phone:'',email:'',availabilityDays:[1,2,3,4,5,6],startTime:'09:00',endTime:'17:00',active:true,color:'#7357f6'}

export default function Doctors(){
  const { doctors,appointments,add,update,can }=useData()
  const [editing,setEditing]=useState(null);const [form,setForm]=useState(emptyDoctor);const [error,setError]=useState('');const [saving,setSaving]=useState(false)
  const canManage=can('settings.manage')||can('services.manage')
  function open(doctor=null){setEditing(doctor?.id||'new');setForm(doctor?{...emptyDoctor,...doctor}:emptyDoctor);setError('')}
  async function submit(e){
    e.preventDefault();setSaving(true);setError('')
    try{if(!form.availabilityDays.length||form.startTime>=form.endTime)throw new Error('Choisissez au moins un jour et une plage horaire valide.')
      if(editing==='new')await add('doctors',form);else await update('doctors',editing,form)
      setEditing(null)
    }catch(err){setError(err.message||'Enregistrement impossible.')}finally{setSaving(false)}
  }
  function toggleDay(day){const value=Number(day);setForm({...form,availabilityDays:form.availabilityDays.includes(value)?form.availabilityDays.filter(x=>x!==value):[...form.availabilityDays,value].sort()})}
  return <>
    <Topbar title="Praticiens" subtitle="Équipe médicale et plages disponibles pour les rendez-vous."/>
    {canManage&&<div className="toolbar page-toolbar"><div></div><button className="primary-btn" onClick={()=>open()}><Plus size={18}/> Ajouter un praticien</button></div>}
    {!doctors.length&&<section className="panel empty-state">Aucun praticien. Ajoutez le premier pour rendre les créneaux disponibles.</section>}
    <div className="doctor-grid">{doctors.map(d=><article className="doctor-card" key={d.id}><div className="doctor-top"><div className="doctor-avatar" style={{background:d.color||'#7357f6'}}><Stethoscope size={24}/></div><span className={`status ${d.active!==false?'ok':'wait'}`}>{d.active!==false?'Actif':'Inactif'}</span></div><h3>{d.name}</h3><p className="specialty">{d.specialty}</p><div className="doctor-info"><span><Phone size={15}/>{d.phone||'—'}</span><span><Mail size={15}/>{d.email||'—'}</span></div><div className="doctor-bottom"><div><small>Disponibilité</small><strong>{Array.isArray(d.availabilityDays)?d.availabilityDays.map(day=>weekdays.find(([id])=>Number(id)===day)?.[1]).join(', '):d.availability||'À configurer'} · {d.startTime||'09:00'}–{d.endTime||'17:00'}</strong></div><div><small>Rendez-vous</small><strong>{appointments.filter(a=>a.doctorId===d.id).length}</strong></div></div>{canManage&&<button type="button" className="ghost-btn" onClick={()=>open(d)}>Modifier</button>}</article>)}</div>
    {canManage&&<Modal open={Boolean(editing)} onClose={()=>setEditing(null)} title={editing==='new'?'Ajouter un praticien':'Modifier le praticien'} subtitle="Les jours et heures définissent les créneaux disponibles."><form onSubmit={submit} className="form-grid"><label>Nom<input required minLength="2" value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Spécialité<input value={form.specialty} onChange={e=>setForm({...form,specialty:e.target.value})}/></label><label>Téléphone<input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label><label>Email<input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label><fieldset className="full availability-days"><legend>Jours disponibles</legend>{weekdays.map(([day,label])=><label key={day}><input type="checkbox" checked={form.availabilityDays.includes(Number(day))} onChange={()=>toggleDay(day)}/>{label}</label>)}</fieldset><label>Début<input required type="time" value={form.startTime} onChange={e=>setForm({...form,startTime:e.target.value})}/></label><label>Fin<input required type="time" value={form.endTime} onChange={e=>setForm({...form,endTime:e.target.value})}/></label><label className="full switch-row"><input type="checkbox" checked={form.active!==false} onChange={e=>setForm({...form,active:e.target.checked})}/> Praticien actif et réservable</label>{error&&<div className="form-error full" role="alert">{error}</div>}<div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setEditing(null)}>Annuler</button><button className="primary-btn" disabled={saving}>{saving?'Enregistrement…':'Enregistrer'}</button></div></form></Modal>}
  </>
}
