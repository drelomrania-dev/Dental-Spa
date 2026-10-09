import React, { useEffect, useState } from 'react'
import { CalendarDays, CheckCircle2, Clock3, RotateCcw, XCircle } from 'lucide-react'
import { useParams } from 'react-router-dom'
import { cancelPublicBooking, loadPublicBookingManagement, reschedulePublicBooking } from '../services/appointments'
import { supabase } from '../services/supabase'
import { todayISO } from '../utils'

function displayDate(value){
  if(!value)return '—'
  const [year,month,day]=String(value).split('-').map(Number)
  return new Date(year,month-1,day,12).toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long',year:'numeric'})
}

export default function PublicManageBooking(){
  const {token}=useParams()
  const [booking,setBooking]=useState(null)
  const [config,setConfig]=useState(null)
  const [loading,setLoading]=useState(true)
  const [error,setError]=useState('')
  const [mode,setMode]=useState('summary')
  const [date,setDate]=useState('')
  const [time,setTime]=useState('')
  const [slots,setSlots]=useState([])
  const [reason,setReason]=useState('')
  const [busy,setBusy]=useState(false)
  const [message,setMessage]=useState('')

  useEffect(()=>{let live=true;loadPublicBookingManagement(token).then(async data=>{
    if(!live)return
    if(!data){setError('Ce lien est invalide ou a expiré.');setLoading(false);return}
    setBooking(data);setDate(data.date)
    const {data:page}=await supabase.rpc('public_booking_page',{p_slug:data.bookingSlug})
    if(live){setConfig(page);setLoading(false)}
  }).catch(()=>{if(live){setError('Impossible de charger ce rendez-vous.');setLoading(false)}});return()=>{live=false}},[token])

  useEffect(()=>{let live=true;if(mode!=='reschedule'||!date||!booking?.bookingSlug)return()=>{live=false};setSlots([]);setTime('');supabase.rpc('public_available_slots',{p_slug:booking.bookingSlug,p_date:date}).then(({data,error:rpcError})=>{if(live){if(rpcError)setError('Impossible de charger les créneaux.');else setSlots(data||[])}});return()=>{live=false}},[mode,date,booking?.bookingSlug])

  async function reschedule(e){e.preventDefault();if(!time)return;setBusy(true);setError('');try{const next=await reschedulePublicBooking(token,date,time);setBooking(current=>({...current,...next}));setMessage('Votre rendez-vous a été reprogrammé.');setMode('summary')}catch(err){setError(String(err?.message||'').toLowerCase().includes('slot')?'Ce créneau vient d’être réservé. Choisissez-en un autre.':'La reprogrammation n’a pas pu être enregistrée.')}finally{setBusy(false)}}
  async function cancel(e){e.preventDefault();setBusy(true);setError('');try{const next=await cancelPublicBooking(token,reason);setBooking(current=>({...current,...next,canManage:false}));setMessage('Votre rendez-vous a été annulé.');setMode('summary')}catch{setError('L’annulation n’a pas pu être enregistrée. Contactez le cabinet.')}finally{setBusy(false)}}

  if(loading)return <main className="booking-page"><section className="booking-success-card"><p>Chargement du rendez-vous…</p></section></main>
  if(error&&!booking)return <main className="booking-page"><section className="booking-success-card"><XCircle size={36}/><h1>Lien indisponible</h1><p>{error}</p></section></main>

  return <main className="booking-page"><section className="booking-success-card booking-manage-card">
    <span className="booking-eyebrow">{config?.clinicName||'Dental Spa'} · Espace rendez-vous</span>
    <h1>Gérer mon rendez-vous</h1>
    {message&&<div className="success-strip" role="status"><CheckCircle2 size={17}/>{message}</div>}
    <div className="booking-confirmation"><div><CalendarDays size={18}/><span><strong>{displayDate(booking.date)}</strong>{booking.time}</span></div><div><Clock3 size={18}/><span><strong>{config?.treatmentName||booking.reason||'Consultation'}</strong>{config?.doctorName||'Équipe Dental Spa'} · {booking.duration} min</span></div><div className="booking-reference"><span>Référence</span><strong>{booking.reference}</strong></div></div>
    <span className={`status ${booking.status==='Annulé'?'bad':'ok'}`}>{booking.status}</span>
    {booking.canManage&&mode==='summary'&&<div className="booking-manage-actions"><button className="primary-btn large" onClick={()=>{setError('');setMode('reschedule')}}><RotateCcw size={17}/> Reprogrammer</button><button className="ghost-btn full-btn" onClick={()=>{setError('');setMode('cancel')}}><XCircle size={17}/> Annuler le rendez-vous</button></div>}
    {mode==='reschedule'&&<form onSubmit={reschedule} className="booking-manage-form"><h2>Choisir un nouveau créneau</h2><label>Date<input required type="date" min={todayISO()} value={date} onChange={e=>setDate(e.target.value)}/></label><div className="time-list">{slots.map(slot=><button type="button" key={slot} className={time===slot?'selected':''} onClick={()=>setTime(slot)}>{slot}</button>)}</div>{!slots.length&&<p>Aucun créneau disponible pour cette date.</p>}{error&&<div className="form-error" role="alert">{error}</div>}<div className="form-actions"><button type="button" className="ghost-btn" onClick={()=>setMode('summary')}>Retour</button><button className="primary-btn" disabled={!time||busy}>{busy?'Enregistrement…':'Confirmer le nouveau créneau'}</button></div></form>}
    {mode==='cancel'&&<form onSubmit={cancel} className="booking-manage-form"><h2>Confirmer l’annulation</h2><p>Cette action libérera immédiatement le créneau pour un autre patient.</p><label>Motif <small>(facultatif)</small><textarea value={reason} onChange={e=>setReason(e.target.value)} placeholder="Vous pouvez indiquer la raison au cabinet."/></label>{error&&<div className="form-error" role="alert">{error}</div>}<div className="form-actions"><button type="button" className="ghost-btn" onClick={()=>setMode('summary')}>Conserver le rendez-vous</button><button className="primary-btn danger-btn" disabled={busy}>{busy?'Annulation…':'Confirmer l’annulation'}</button></div></form>}
    {!booking.canManage&&booking.status!=='Annulé'&&<p>Ce rendez-vous ne peut plus être modifié en ligne. Contactez directement le cabinet.</p>}
  </section></main>
}
