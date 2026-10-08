import React, { useMemo, useState } from 'react'
import { CheckCircle2, Clock3, Sparkles } from 'lucide-react'
import { useParams } from 'react-router-dom'
import { useData } from '../DataContext'
import { todayISO } from '../utils'

export default function PublicBooking(){
  const { slug } = useParams(); const { bookingLinks, treatments, doctors, patients, appointments, add } = useData()
  const link = bookingLinks.find(x => x.slug === slug && x.published)
  const [form,setForm] = useState({date:todayISO(),time:'09:00',firstName:'',lastName:'',phone:'',email:''})
  const [done,setDone] = useState(null); const [error,setError] = useState('')
  const treatment = treatments.find(x => x.id === link?.treatmentId)
  const doctor = doctors.find(x => x.id === link?.doctorId)
  const slots = useMemo(()=>['09:00','09:30','10:00','10:30','11:00','14:00','14:30','15:00','15:30','16:00'],[])
  const available = useMemo(() => slots.filter(slot => !appointments.some(a => a.date === form.date && a.time === slot && a.doctorId === (link.doctorId || doctors[0]?.id) && !['Annulé','No-show'].includes(a.status))), [appointments, form.date, link, doctors, slots])
  if(!link) return <main className="public-booking"><div className="public-card"><h1>Lien indisponible</h1><p>Cette page de réservation n’est pas publiée.</p></div></main>
  async function submit(e){
    e.preventDefault(); setError('')
    try {
      if(!available.includes(form.time)) throw new Error('Ce créneau vient d’être réservé. Choisissez-en un autre.')
      let patient = patients.find(p => p.phone && p.phone === form.phone)
      if(!patient) patient = await add('patients',{firstName:form.firstName,lastName:form.lastName,phone:form.phone,email:form.email,createdAt:todayISO(),status:'Actif'})
      const appointment = await add('appointments',{patientId:patient.id,doctorId:link.doctorId || doctors[0]?.id || '',treatmentId:link.treatmentId,date:form.date,time:form.time,duration:link.duration || treatment?.duration || 30,reason:treatment?.name || link.title,status:link.confirmationPolicy==='manual'?'En attente':'Confirmé',source:'public',reference:`RDV-${Date.now().toString(36).toUpperCase()}`})
      setDone(appointment)
    } catch(err){ setError(err.message || 'Impossible de réserver ce créneau.') }
  }
  if(done) return <main className="public-booking"><div className="public-card booking-success"><CheckCircle2 size={48}/><h1>Demande enregistrée</h1><p>Votre rendez-vous <strong>{done.reference}</strong> est {done.status.toLowerCase()}.</p><div className="public-summary">{form.date} · {form.time}<br/>{link.title}<br/>{doctor?.name || 'Notre équipe'}</div></div></main>
  return <main className="public-booking"><div className="public-card"><div className="public-brand"><Sparkles size={20}/><span>Dental Spa</span></div><h1>{link.title}</h1><p>{link.description}</p><div className="public-meta"><span><Clock3 size={15}/> {link.duration || treatment?.duration || 30} minutes</span><span>{treatment?.name || 'Consultation'}</span></div><form onSubmit={submit} className="public-form"><label>Date<input required type="date" min={todayISO()} value={form.date} onChange={e=>setForm({...form,date:e.target.value})}/></label><div><span className="public-label">Choisissez une heure</span><div className="slot-grid">{slots.map(slot=><button type="button" disabled={!available.includes(slot)} key={slot} className={form.time===slot?'selected':''} onClick={()=>setForm({...form,time:slot})}>{slot}</button>)}</div>{!available.length&&<small className="form-error">Aucun créneau disponible à cette date.</small>}</div><div className="form-grid"><label>Prénom<input required value={form.firstName} onChange={e=>setForm({...form,firstName:e.target.value})}/></label><label>Nom<input required value={form.lastName} onChange={e=>setForm({...form,lastName:e.target.value})}/></label><label>Téléphone<input required value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label><label>Email<input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label></div>{error&&<div className="form-error">{error}</div>}<button className="primary-btn large" disabled={!available.length}>Confirmer le rendez-vous</button></form><small className="public-note">Vos coordonnées sont utilisées uniquement pour traiter cette demande de rendez-vous.</small></div></main>
}
