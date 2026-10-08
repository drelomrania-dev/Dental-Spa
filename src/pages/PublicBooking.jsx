import React, { useCallback, useMemo } from 'react'
import { useParams } from 'react-router-dom'
import { useData } from '../DataContext'
import { todayISO } from '../utils'
import BookingExperience from '../components/BookingExperience'

export default function PublicBooking(){
  const { slug } = useParams(); const { bookingLinks, treatments, doctors, patients, appointments, add } = useData()
  const link = bookingLinks.find(x => x.slug === slug && x.published)
  const treatment = treatments.find(x => x.id === link?.treatmentId)
  const doctor = doctors.find(x => x.id === link?.doctorId)
  const slots = useMemo(()=>['09:00','09:30','10:00','10:30','11:00','14:00','14:30','15:00','15:30','16:00'],[])
  const getSlots=useCallback(async date=>slots.filter(slot=>!appointments.some(a=>a.date===date&&a.time===slot&&a.doctorId===(link?.doctorId||doctors[0]?.id)&&!['Annulé','No-show'].includes(a.status))),[appointments,doctors,link,slots])
  const onBook=useCallback(async form=>{
    const available=await getSlots(form.date)
    if(!available.includes(form.time))throw new Error('Slot unavailable')
    let patient=patients.find(p=>p.phone&&p.phone===form.phone)
    if(!patient)patient=await add('patients',{firstName:form.firstName,lastName:form.lastName,phone:form.phone,email:form.email,createdAt:todayISO(),status:'Actif'})
    return add('appointments',{patientId:patient.id,doctorId:link.doctorId||doctors[0]?.id||'',treatmentId:link.treatmentId,date:form.date,time:form.time,duration:link.duration||treatment?.duration||30,reason:treatment?.name||link.title,status:link.confirmationPolicy==='manual'?'En attente':'Confirmé',source:'public',reference:`RDV-${Date.now().toString(36).toUpperCase()}`})
  },[add,doctors,getSlots,link,patients,treatment])
  if(!link) return <main className="public-booking"><div className="public-card"><h1>Lien indisponible</h1><p>Cette page de réservation n’est pas publiée.</p></div></main>
  return <BookingExperience config={{...link,slug,duration:link.duration||treatment?.duration||30,doctorName:doctor?.name,clinicName:'Dental Spa',timezone:'Africa/Casablanca'}} getSlots={getSlots} onBook={onBook}/>
}
