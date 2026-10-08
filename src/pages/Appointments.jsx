import React, { useMemo, useState } from 'react'
import { CalendarPlus, Clock3, Pencil, Plus } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

export default function Appointments(){
  const { appointments,patients,doctors,treatments,add,update,patientName,doctorName } = useData()
  const [open,setOpen]=useState(false)
  const [editingId,setEditingId]=useState(null)
  const [form,setForm]=useState({patientId:'',doctorId:'',treatmentId:'',estimatedAmount:'',date:todayISO(),time:'09:00',duration:30,reason:'Consultation',status:'Confirmé'})
  const grouped=useMemo(()=>Object.entries(appointments.reduce((a,x)=>{(a[x.date]??=[]).push(x);return a},{})).sort(([a],[b])=>a.localeCompare(b)),[appointments])
  const selectedPatient=patients.find(p=>p.id===form.patientId)
  const selectedTreatment=treatments.find(t=>t.id===form.treatmentId)
  function treatmentFor(appointment){
    return treatments.find(t=>t.id===appointment.treatmentId)
      || treatments.find(t=>t.name.trim().toLocaleLowerCase()===String(appointment.reason||'').trim().toLocaleLowerCase())
  }
  function newAppointment(){setEditingId(null);setForm({patientId:'',doctorId:'',treatmentId:'',estimatedAmount:'',date:todayISO(),time:'09:00',duration:30,reason:'Consultation',status:'Confirmé'});setOpen(true)}
  function editAppointment(appointment){
    const treatment=treatmentFor(appointment)
    setEditingId(appointment.id)
    setForm({...appointment,treatmentId:treatment?.id||appointment.treatmentId||'',estimatedAmount:appointment.estimatedAmount??treatment?.price??''})
    setOpen(true)
  }
  async function submit(e){
    e.preventDefault()
    const payload={...form,duration:Number(form.duration),estimatedAmount:form.estimatedAmount===''?'':Number(form.estimatedAmount)}
    try {
      if(editingId) await update('appointments',editingId,payload)
      else await add('appointments',payload)
      setOpen(false);setEditingId(null)
    } catch(err) { window.alert(err.message) }
  }
  return <>
    <Topbar title="Rendez-vous" subtitle="Planning des patients et disponibilités des praticiens."/>
    <section className="panel">
      <div className="toolbar"><div><span className="soft-badge"><Clock3 size={14}/> Planning clinique</span></div><button className="primary-btn" onClick={newAppointment}><Plus size={18}/> Nouveau rendez-vous</button></div>
      <div className="schedule-list">{grouped.map(([date,items])=><div className="schedule-day" key={date}><div className="schedule-date"><CalendarPlus size={18}/><strong>{date}</strong><span>{items.length} rendez-vous</span></div><div className="schedule-items">{[...items].sort((a,b)=>a.time.localeCompare(b.time)).map(a=>{
        const patient=patients.find(p=>p.id===a.patientId)
        const treatment=treatmentFor(a)
        return <div className="booking-card" key={a.id}>
          <div className="booking-time">{a.time}</div>
          <div className="booking-patient"><strong>{patientName(a.patientId)}</strong><span className="booking-reason">{a.reason || 'Consultation'}</span><span>{patient?.phone || 'Téléphone non renseigné'}</span></div>
          <div className="booking-provider"><strong>{doctorName(a.doctorId)}</strong><span>{a.duration} min</span></div>
          <div className="booking-cost"><span>À payer</span><strong>{a.estimatedAmount!==undefined&&a.estimatedAmount!==''?money(a.estimatedAmount):treatment?money(treatment.price):'À préciser'}</strong></div>
          <div className="booking-actions"><span className={`status ${a.status==='Confirmé'?'ok':'wait'}`}>{a.status}</span><button className="appointment-edit" type="button" title="Modifier le rendez-vous" aria-label={`Modifier le rendez-vous de ${patientName(a.patientId)}`} onClick={()=>editAppointment(a)}><Pencil size={14}/></button></div>
        </div>
      })}</div></div>)}</div>
    </section>
    <Modal open={open} onClose={()=>{setOpen(false);setEditingId(null)}} title={editingId?'Modifier le rendez-vous':'Nouveau rendez-vous'} subtitle={editingId?'Mettez à jour le soin prévu et le montant pour ce patient.':'Planifiez rapidement un passage au cabinet.'}>
      <form onSubmit={submit} className="form-grid">
        <label>Patient<select required value={form.patientId} onChange={e=>setForm({...form,patientId:e.target.value})}><option value="">Choisir</option>{patients.map(p=><option key={p.id} value={p.id}>{p.firstName} {p.lastName}</option>)}</select>{selectedPatient&&<small className="appointment-phone">Téléphone : {selectedPatient.phone || 'non renseigné'}</small>}</label>
        <label>Praticien<select required value={form.doctorId} onChange={e=>setForm({...form,doctorId:e.target.value})}><option value="">Choisir</option>{doctors.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
        <label>Date<input required type="date" value={form.date} onChange={e=>setForm({...form,date:e.target.value})}/></label>
        <label>Heure<input required type="time" value={form.time} onChange={e=>setForm({...form,time:e.target.value})}/></label>
        <label>Soin prévu<select value={form.treatmentId} onChange={e=>{const id=e.target.value;const treatment=treatments.find(t=>t.id===id);setForm({...form,treatmentId:id,reason:treatment?.name||form.reason,estimatedAmount:treatment?.price??form.estimatedAmount})}}><option value="">Choisir un soin (facultatif)</option>{treatments.filter(t=>t.active).map(t=><option key={t.id} value={t.id}>{t.name} · {money(t.price)}</option>)}</select></label>
        <label>Montant à prévoir (DH)<input type="number" min="0" step="50" placeholder={selectedTreatment?String(selectedTreatment.price):'À préciser'} value={form.estimatedAmount} onChange={e=>setForm({...form,estimatedAmount:e.target.value})}/></label>
        <label>Durée (min)<input type="number" min="15" step="15" value={form.duration} onChange={e=>setForm({...form,duration:e.target.value})}/></label>
        <label>Motif<input required value={form.reason} onChange={e=>setForm({...form,reason:e.target.value})}/></label>
        <label>Statut<select value={form.status} onChange={e=>setForm({...form,status:e.target.value})}>{['En attente','Confirmé','Arrivé','En attente clinique','En consultation','Terminé','Annulé','No-show'].map(s=><option key={s}>{s}</option>)}</select></label>
        <div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn">Enregistrer</button></div>
      </form>
    </Modal>
  </>
}
