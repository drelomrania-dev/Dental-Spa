import React, { useEffect, useMemo, useState } from 'react'
import { ArrowLeft, CalendarDays, Check, CheckCircle2, ChevronLeft, ChevronRight, Clock3, MapPin, ShieldCheck, Sparkles, Stethoscope, UserRound } from 'lucide-react'
import { todayISO } from '../utils'

const WEEKDAYS = ['Lun','Mar','Mer','Jeu','Ven','Sam','Dim']

function isoDate(date){
  return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`
}

function dateFromISO(value){
  const [year,month,day]=String(value).split('-').map(Number)
  return new Date(year,month-1,day,12)
}

function displayDate(value){
  return dateFromISO(value).toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long',year:'numeric'})
}

function monthDays(month){
  const first=new Date(month.getFullYear(),month.getMonth(),1,12)
  const offset=(first.getDay()+6)%7
  return Array.from({length:42},(_,index)=>{
    const date=new Date(first)
    date.setDate(index-offset+1)
    return date
  })
}

export default function BookingExperience({config,getSlots,onBook}){
  const today=todayISO()
  const [month,setMonth]=useState(()=>{const date=dateFromISO(today);return new Date(date.getFullYear(),date.getMonth(),1,12)})
  const [step,setStep]=useState('schedule')
  const [selectedDate,setSelectedDate]=useState(today)
  const [selectedTime,setSelectedTime]=useState('')
  const [slots,setSlots]=useState([])
  const [loadingSlots,setLoadingSlots]=useState(true)
  const [submitting,setSubmitting]=useState(false)
  const [error,setError]=useState('')
  const [done,setDone]=useState(null)
  const [contact,setContact]=useState({firstName:'',lastName:'',phone:'',email:''})
  const days=useMemo(()=>monthDays(month),[month])
  const maxDate=useMemo(()=>{const date=dateFromISO(today);date.setDate(date.getDate()+Number(config.maximumAdvanceDays||90));return isoDate(date)},[today,config.maximumAdvanceDays])

  useEffect(()=>{
    let live=true
    setLoadingSlots(true);setError('');setSelectedTime('')
    getSlots(selectedDate).then(next=>{if(live)setSlots(next||[])}).catch(()=>{if(live){setSlots([]);setError('Impossible de charger les disponibilités. Réessayez.')}}).finally(()=>{if(live)setLoadingSlots(false)})
    return()=>{live=false}
  },[selectedDate,getSlots])

  function chooseDate(date){
    const value=isoDate(date)
    if(value<today||value>maxDate||date.getDay()===0)return
    setSelectedDate(value)
  }

  function previousMonth(){
    const current=dateFromISO(today)
    if(month.getFullYear()===current.getFullYear()&&month.getMonth()===current.getMonth())return
    setMonth(new Date(month.getFullYear(),month.getMonth()-1,1,12))
  }

  async function submit(e){
    e.preventDefault();setError('');setSubmitting(true)
    try {
      const booking=await onBook({...contact,date:selectedDate,time:selectedTime})
      setDone(booking)
    } catch(err){
      const unavailable=String(err?.message||'').toLowerCase().includes('slot')
      setError(unavailable?'Ce créneau vient d’être réservé. Choisissez une autre heure.':'Impossible d’enregistrer le rendez-vous. Vérifiez vos informations puis réessayez.')
      if(unavailable){setStep('schedule');const refreshed=await getSlots(selectedDate).catch(()=>[]);setSlots(refreshed);setSelectedTime('')}
    } finally { setSubmitting(false) }
  }

  if(done)return <main className="booking-page"><section className="booking-success-card"><div className="booking-success-icon"><CheckCircle2 size={38}/></div><span className="booking-eyebrow">Réservation confirmée</span><h1>Votre rendez-vous est enregistré</h1><p>Un membre de l’équipe pourra vous contacter si une précision est nécessaire.</p><div className="booking-confirmation"><div><CalendarDays size={18}/><span><strong>{displayDate(done.date||selectedDate)}</strong>{done.time||selectedTime}</span></div><div><Stethoscope size={18}/><span><strong>{config.title}</strong>{config.doctorName||'Équipe Dental Spa'}</span></div><div className="booking-reference"><span>Référence</span><strong>{done.reference}</strong></div></div><a className="primary-btn large" href={`/book/${config.slug}`}>Nouvelle réservation</a></section></main>

  return <main className="booking-page"><section className="booking-shell">
    <aside className="booking-event-panel">
      <div className="public-brand"><Sparkles size={20}/><span>{config.clinicName||'Dental Spa'}</span></div>
      <span className="booking-eyebrow">Réservation en ligne</span>
      <h1>{config.title}</h1>
      <p>{config.description}</p>
      <div className="booking-event-meta">
        <div><Clock3 size={17}/><span><strong>{config.duration||30} minutes</strong>Durée du rendez-vous</span></div>
        <div><UserRound size={17}/><span><strong>{config.doctorName||'Équipe Dental Spa'}</strong>Praticien</span></div>
        {config.address&&<div><MapPin size={17}/><span><strong>Au cabinet</strong>{config.address}</span></div>}
      </div>
      {(selectedDate&&selectedTime)&&<div className="booking-selection"><Check size={17}/><span>{displayDate(selectedDate)} à {selectedTime}</span></div>}
      <div className="booking-trust"><ShieldCheck size={16}/><span>Vos coordonnées sont transmises de manière sécurisée au cabinet.</span></div>
    </aside>

    <div className="booking-flow-panel">
      <div className="booking-progress" aria-label="Progression"><span className={step==='schedule'?'active':'done'}>1</span><i/><span className={step==='details'?'active':''}>2</span></div>
      {step==='schedule'?<>
        <div className="booking-step-head"><div><span className="booking-eyebrow">Étape 1 sur 2</span><h2>Choisissez une date et une heure</h2></div></div>
        <div className="calendar-layout">
          <div className="booking-calendar">
            <div className="calendar-head"><button type="button" aria-label="Mois précédent" onClick={previousMonth}><ChevronLeft size={18}/></button><strong>{month.toLocaleDateString('fr-FR',{month:'long',year:'numeric'})}</strong><button type="button" aria-label="Mois suivant" onClick={()=>setMonth(new Date(month.getFullYear(),month.getMonth()+1,1,12))}><ChevronRight size={18}/></button></div>
            <div className="calendar-weekdays">{WEEKDAYS.map(day=><span key={day}>{day}</span>)}</div>
            <div className="calendar-grid">{days.map(date=>{const value=isoDate(date);const outside=date.getMonth()!==month.getMonth();const disabled=value<today||value>maxDate||date.getDay()===0;return <button type="button" key={value} disabled={disabled} className={`${outside?'outside ':''}${selectedDate===value?'selected':''}`} aria-label={displayDate(value)} onClick={()=>chooseDate(date)}>{date.getDate()}</button>})}</div>
          </div>
          <div className="booking-times"><strong>{dateFromISO(selectedDate).toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'})}</strong>{loadingSlots?<div className="slot-loading">Recherche des créneaux…</div>:slots.length?<div className="time-list">{slots.map(slot=><button type="button" key={slot} className={selectedTime===slot?'selected':''} onClick={()=>setSelectedTime(slot)}>{slot}{selectedTime===slot&&<Check size={15}/>}</button>)}</div>:<div className="slot-empty"><CalendarDays size={24}/><span>Aucun créneau ce jour-là.</span><small>Choisissez une autre date.</small></div>}</div>
        </div>
        {error&&<div className="form-error">{error}</div>}
        <button type="button" className="primary-btn large booking-continue" disabled={!selectedTime} onClick={()=>setStep('details')}>Continuer</button>
      </>:<>
        <div className="booking-step-head"><button type="button" className="booking-back" aria-label="Revenir au calendrier" onClick={()=>setStep('schedule')}><ArrowLeft size={18}/></button><div><span className="booking-eyebrow">Étape 2 sur 2</span><h2>Vos coordonnées</h2></div></div>
        <div className="booking-mobile-summary"><CalendarDays size={17}/><span>{displayDate(selectedDate)} · {selectedTime}</span></div>
        <form className="booking-details-form" onSubmit={submit}>
          <div className="form-grid"><label>Prénom<input autoComplete="given-name" required value={contact.firstName} onChange={e=>setContact({...contact,firstName:e.target.value})}/></label><label>Nom<input autoComplete="family-name" required value={contact.lastName} onChange={e=>setContact({...contact,lastName:e.target.value})}/></label><label>Téléphone<input type="tel" autoComplete="tel" required minLength="6" value={contact.phone} onChange={e=>setContact({...contact,phone:e.target.value})}/></label><label>Email <small>(facultatif)</small><input type="email" autoComplete="email" value={contact.email} onChange={e=>setContact({...contact,email:e.target.value})}/></label></div>
          {error&&<div className="form-error">{error}</div>}
          <button className="primary-btn large" disabled={submitting}>{submitting?'Réservation en cours…':'Confirmer le rendez-vous'}</button>
        </form>
      </>}
    </div>
  </section><small className="booking-footer">Propulsé par DentalFlow · Fuseau horaire {config.timezone||'Africa/Casablanca'}</small></main>
}
