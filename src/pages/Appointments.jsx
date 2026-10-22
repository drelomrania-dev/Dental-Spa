import React, { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { CalendarPlus, Check, ChevronLeft, ChevronRight, Clock3, Copy, ExternalLink, Pencil, Plus, Share2 } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

const transitions={
  'En attente':['Confirmé','Annulé'], 'Confirmé':['Arrivé','Annulé','No-show'],
  'Arrivé':['En attente clinique','En consultation','Annulé'],
  'En attente clinique':['En consultation','Annulé'], 'En consultation':['Terminé','Annulé']
}
function appointmentError(error){
  const message=String(error?.message||'').toLowerCase()
  if(message.includes('unavailable')||message.includes('slot'))return 'Ce créneau est indisponible pour le praticien ou le fauteuil. Choisissez une autre heure ou ressource.'
  if(message.includes('cancellation denied'))return 'Vous n’avez pas la permission d’annuler ou de marquer une absence.'
  if(message.includes('no-show'))return 'Une absence peut être enregistrée après le début du rendez-vous, sans déplacer le créneau.'
  if(message.includes('status transition'))return 'Ce changement de statut n’est pas autorisé.'
  return error?.message||'Le rendez-vous n’a pas pu être enregistré.'
}

const fromISO = value => new Date(`${value}T12:00:00`)
const toISO = date => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
function calendarDays(view, focus) {
  const date = fromISO(focus)
  if (view === 'week') date.setDate(date.getDate() - ((date.getDay() + 6) % 7))
  else date.setDate(1)
  const count = view === 'week' ? 7 : new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()
  return Array.from({ length: count }, (_, index) => {
    const day = new Date(date)
    day.setDate(date.getDate() + index)
    return toISO(day)
  })
}

export default function Appointments(){
  const { appointments,patients,doctors,treatments,resources,bookingLinks,clinic,add,update,patientName,doctorName,can } = useData()
  const canCreate=can('appointments.create');const canEdit=can('appointments.edit');const canCancel=can('appointments.cancel')
  const [open,setOpen]=useState(false)
  const [editingId,setEditingId]=useState(null)
  const [error,setError]=useState('');const [saving,setSaving]=useState(false)
  const [copiedLink,setCopiedLink]=useState('')
  const [calendarView,setCalendarView]=useState('list')
  const [focusDate,setFocusDate]=useState(todayISO)
  const defaultResource=resources.find(resource=>resource.active)?.id||''
  const [form,setForm]=useState({patientId:'',doctorId:'',treatmentId:'',roomId:'',estimatedAmount:'',date:todayISO(),time:'09:00',duration:30,reason:'Consultation',status:'Confirmé'})
  const grouped=useMemo(()=>Object.entries(appointments.reduce((a,x)=>{(a[x.date]??=[]).push(x);return a},{})).sort(([a],[b])=>a.localeCompare(b)),[appointments])
  const byDate=useMemo(()=>new Map(grouped),[grouped])
  const visibleDays=useMemo(()=>calendarView==='list'?[]:calendarDays(calendarView,focusDate),[calendarView,focusDate])
  function movePeriod(direction){
    const date=fromISO(focusDate)
    if(calendarView==='week')date.setDate(date.getDate()+7*direction)
    else {date.setDate(1);date.setMonth(date.getMonth()+direction)}
    setFocusDate(toISO(date))
  }
  const selectedPatient=patients.find(p=>p.id===form.patientId)
  const selectedTreatment=treatments.find(t=>t.id===form.treatmentId)
  const existing=appointments.find(item=>item.id===editingId)
  const statusOptions=editingId?[existing?.status,...(transitions[existing?.status]||[]).filter(status=>status!=='Annulé'&&status!=='No-show'||canCancel)].filter(Boolean):['En attente','Confirmé']
  const canMarkNoShow=existing?.status==='Confirmé'&&canCancel&&new Date(existing.startsAt||`${existing.date}T${existing.time}:00`)<=new Date()
  function treatmentFor(appointment){
    return treatments.find(t=>t.id===appointment.treatmentId)
      || treatments.find(t=>t.name.trim().toLocaleLowerCase()===String(appointment.reason||'').trim().toLocaleLowerCase())
  }
  function newAppointment(date=todayISO()){setEditingId(null);setError('');setForm({patientId:'',doctorId:'',treatmentId:'',roomId:defaultResource,estimatedAmount:'',date,time:'09:00',duration:30,reason:'Consultation',status:'Confirmé'});setOpen(true)}
  function editAppointment(appointment){
    const treatment=treatmentFor(appointment)
    setEditingId(appointment.id)
    setError('')
    setForm({...appointment,treatmentId:treatment?.id||appointment.treatmentId||'',estimatedAmount:appointment.estimatedAmount??treatment?.price??''})
    setOpen(true)
  }
  async function submit(e){
    e.preventDefault()
    const payload={...form,duration:Number(form.duration),estimatedAmount:form.estimatedAmount===''?'':Number(form.estimatedAmount)}
    setSaving(true);setError('')
    try {
      if(editingId) await update('appointments',editingId,payload)
      else await add('appointments',payload)
      setOpen(false);setEditingId(null)
    } catch(err) { setError(appointmentError(err)) }
    finally{setSaving(false)}
  }
  function bookingUrl(link){
    const publicOrigin=import.meta.env.VITE_PUBLIC_APP_URL||window.location.origin
    return `${publicOrigin.replace(/\/$/,'')}/book/${encodeURIComponent(link.slug)}`
  }
  async function copyBookingLink(link){
    const url=bookingUrl(link)
    await navigator.clipboard.writeText(url)
    setCopiedLink(link.id)
    window.setTimeout(()=>setCopiedLink(''),1800)
  }
  async function shareBookingLink(link){
    const url=bookingUrl(link)
    if(navigator.share){
      try { await navigator.share({title:link.title||'Réserver un rendez-vous',text:'Réservez votre rendez-vous en ligne au Dental Spa.',url}) } catch(err) { if(err?.name!=='AbortError') await copyBookingLink(link) }
    } else await copyBookingLink(link)
  }
  return <>
    <Topbar title="Rendez-vous" subtitle="Planning des patients et disponibilités des praticiens."/>
    {bookingLinks.filter(link=>link.published).length>0&&<section className="panel booking-share-panel">
      <div className="panel-head"><div><h3>Réservation en ligne</h3><p>Partagez ce lien pour permettre aux patients de choisir leur créneau.</p></div><Share2 size={22}/></div>
      <div className="booking-share-list">{bookingLinks.filter(link=>link.published).map(link=>{const url=bookingUrl(link);return <div className="booking-share-row" key={link.id}><div className="booking-share-info"><strong>{link.title||'Réserver un rendez-vous'}</strong><span>{url}</span></div><div className="booking-share-actions"><button type="button" className="ghost-btn" onClick={()=>copyBookingLink(link)}>{copiedLink===link.id?<><Check size={15}/> Copié</>:<><Copy size={15}/> Copier</>}</button><button type="button" className="primary-btn" onClick={()=>shareBookingLink(link)}><Share2 size={15}/> Partager</button><a className="icon-btn" href={`/book/${encodeURIComponent(link.slug)}`} target="_blank" rel="noreferrer" aria-label="Ouvrir le lien de réservation" title="Ouvrir le lien de réservation"><ExternalLink size={16}/></a></div></div>})}</div>
    </section>}
    <section className="panel">
      <div className="toolbar appointment-toolbar"><div className="appointment-view-switch" role="group" aria-label="Vue du planning">{[['list','Liste'],['week','Semaine'],['month','Mois']].map(([key,label])=><button type="button" key={key} className={calendarView===key?'active':''} aria-pressed={calendarView===key} onClick={()=>setCalendarView(key)}>{label}</button>)}</div>{canCreate&&<button className="primary-btn" onClick={()=>newAppointment(calendarView==='list'?todayISO():focusDate)}><Plus size={18}/> Nouveau rendez-vous</button>}</div>
      {calendarView!=='list'&&<div className="appointment-period"><button type="button" className="ghost-btn" aria-label="Période précédente" onClick={()=>movePeriod(-1)}><ChevronLeft size={16}/></button><input type="date" aria-label="Date du planning" value={focusDate} onChange={event=>event.target.value&&setFocusDate(event.target.value)}/><button type="button" className="ghost-btn" aria-label="Période suivante" onClick={()=>movePeriod(1)}><ChevronRight size={16}/></button><button type="button" className="ghost-btn" onClick={()=>setFocusDate(todayISO())}>Aujourd’hui</button></div>}
      {calendarView==='list'?<div className="schedule-list">{!grouped.length&&<div className="empty-state">Aucun rendez-vous dans l’agenda.</div>}{grouped.map(([date,items])=><div className="schedule-day" key={date}><div className="schedule-date"><CalendarPlus size={18}/><strong>{date}</strong><span>{items.length} rendez-vous</span></div><div className="schedule-items">{[...items].sort((a,b)=>a.time.localeCompare(b.time)).map(a=>{
        const patient=patients.find(p=>p.id===a.patientId)
        const treatment=treatmentFor(a)
        return <div className="booking-card" key={a.id}>
          <div className="booking-time">{a.time}</div>
          <div className="booking-patient"><strong>{can('patients.basic.view')?<Link to={`/patients/${encodeURIComponent(a.patientId)}`}>{patientName(a.patientId)}</Link>:patientName(a.patientId)}</strong><span className="booking-reason">{a.reason || 'Consultation'}</span><span>{patient?.phone || 'Téléphone non renseigné'}</span>{a.leadId&&can('acquisition.view')&&<Link className="appointment-record-link" to={`/acquisition/${encodeURIComponent(a.leadId)}`}>Voir le prospect</Link>}</div>
          <div className="booking-provider"><strong>{doctorName(a.doctorId)}</strong><span>{a.duration} min · {resources.find(resource=>resource.id===a.roomId)?.name||'Ressource non assignée'}</span></div>
          <div className="booking-cost"><span>À payer</span><strong>{a.estimatedAmount!==undefined&&a.estimatedAmount!==''?money(a.estimatedAmount,clinic.currency):treatment?money(treatment.price,clinic.currency):'À préciser'}</strong></div>
          <div className="booking-actions"><span className={`status ${a.status==='Confirmé'?'ok':'wait'}`}>{a.status}</span>{canEdit&&(a.status!=='Annulé'||canCancel)&&<button className="appointment-edit" type="button" title="Modifier le rendez-vous" aria-label={`Modifier le rendez-vous de ${patientName(a.patientId)}`} onClick={()=>editAppointment(a)}><Pencil size={14}/></button>}</div>
        </div>
      })}</div></div>)}</div>:<div className={`appointment-calendar ${calendarView}`}>
        {visibleDays.map(date=><section className={`appointment-calendar-day ${date===todayISO()?'today':''}`} key={date} style={calendarView==='month'&&date===visibleDays[0]?{gridColumnStart:(fromISO(date).getDay()+6)%7+1}:undefined}><header><strong>{fromISO(date).toLocaleDateString('fr-FR',{weekday:'short',day:'numeric',month:'short'})}</strong><span>{(byDate.get(date)||[]).length} RDV</span></header><div>{[...(byDate.get(date)||[])].sort((a,b)=>a.time.localeCompare(b.time)).map(a=><button type="button" className={`appointment-calendar-entry ${a.status==='Annulé'?'cancelled':''}`} key={a.id} onClick={()=>canEdit&&(a.status!=='Annulé'||canCancel)&&editAppointment(a)} disabled={!canEdit||(a.status==='Annulé'&&!canCancel)} title={`${a.time} · ${patientName(a.patientId)} · ${a.reason}`}><time>{a.time}</time><strong>{patientName(a.patientId)}</strong><small>{a.reason}</small></button>)}{canCreate&&<button type="button" className="appointment-calendar-add" onClick={()=>newAppointment(date)} aria-label={`Ajouter un rendez-vous le ${date}`}><Plus size={14}/> Ajouter</button>}</div></section>)}
      </div>}
    </section>
    <Modal open={open} onClose={()=>{setOpen(false);setEditingId(null)}} title={editingId?'Modifier le rendez-vous':'Nouveau rendez-vous'} subtitle={editingId?'Mettez à jour le soin prévu et le montant pour ce patient.':'Planifiez rapidement un passage au cabinet.'}>
      <form onSubmit={submit} className="form-grid">
        <label>Patient<select required value={form.patientId} onChange={e=>setForm({...form,patientId:e.target.value})}><option value="">Choisir</option>{patients.map(p=><option key={p.id} value={p.id}>{p.firstName} {p.lastName}</option>)}</select>{selectedPatient&&<small className="appointment-phone">Téléphone : {selectedPatient.phone || 'non renseigné'}</small>}</label>
        <label>Praticien<select required value={form.doctorId} onChange={e=>setForm({...form,doctorId:e.target.value})}><option value="">Choisir</option>{doctors.filter(d=>d.active!==false||d.id===form.doctorId).map(d=><option key={d.id} value={d.id}>{d.name}{d.active===false?' (inactif)':''}</option>)}</select></label>
        <label>Fauteuil / salle<select required={resources.some(resource=>resource.active)} value={form.roomId||''} onChange={e=>setForm({...form,roomId:e.target.value})}><option value="">{resources.some(resource=>resource.active)?'Choisir':'Aucune ressource active'}</option>{resources.filter(resource=>resource.active||resource.id===form.roomId).map(resource=><option key={resource.id} value={resource.id}>{resource.name} · {resource.type==='chair'?'Fauteuil':'Salle'}</option>)}</select></label>
        <label>Date<input required type="date" value={form.date} onChange={e=>setForm({...form,date:e.target.value})}/></label>
        <label>Heure<input required type="time" value={form.time} onChange={e=>setForm({...form,time:e.target.value})}/></label>
        <label>Soin prévu<select value={form.treatmentId} onChange={e=>{const id=e.target.value;const treatment=treatments.find(t=>t.id===id);setForm({...form,treatmentId:id,reason:treatment?.name||form.reason,estimatedAmount:treatment?.price??form.estimatedAmount})}}><option value="">Choisir un soin (facultatif)</option>{treatments.filter(t=>t.active).map(t=><option key={t.id} value={t.id}>{t.name} · {money(t.price,clinic.currency)}</option>)}</select></label>
        <label>Montant à prévoir ({clinic.currency==='MAD'?'DH':clinic.currency||'DH'})<input type="number" min="0" step="0.01" placeholder={selectedTreatment?String(selectedTreatment.price):'À préciser'} value={form.estimatedAmount} onChange={e=>setForm({...form,estimatedAmount:e.target.value})}/></label>
        <label>Durée (min)<input type="number" min="15" step="15" value={form.duration} onChange={e=>setForm({...form,duration:e.target.value})}/></label>
        <label>Motif<input required value={form.reason} onChange={e=>setForm({...form,reason:e.target.value})}/></label>
        <label>Statut<select value={form.status} onChange={e=>setForm({...form,status:e.target.value})}>{statusOptions.filter(status=>status!=='No-show'||canMarkNoShow||status===existing?.status).map(s=><option key={s}>{s}</option>)}</select></label>
        {editingId&&<div className="appointment-modal-records full">{can('patients.basic.view')&&<Link to={`/patients/${encodeURIComponent(form.patientId)}`} onClick={()=>setOpen(false)}>Ouvrir le dossier patient</Link>}{existing?.leadId&&can('acquisition.view')&&<Link to={`/acquisition/${encodeURIComponent(existing.leadId)}`} onClick={()=>setOpen(false)}>Ouvrir le prospect</Link>}</div>}
        {error&&<div className="form-error full" role="alert">{error}</div>}
        <div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn" disabled={saving}>{saving?'Enregistrement…':'Enregistrer'}</button></div>
      </form>
    </Modal>
  </>
}
