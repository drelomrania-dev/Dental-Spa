import React, { useCallback, useMemo } from 'react'
import { useParams } from 'react-router-dom'
import { useData } from '../DataContext'
import { todayISO } from '../utils'
import BookingExperience from '../components/BookingExperience'

export default function PublicBooking(){
  const { slug } = useParams(); const { bookingLinks, treatments, doctors, resources, patients, appointments, add } = useData()
  const link = bookingLinks.find(x => x.slug === slug && x.published)
  const treatment = treatments.find(x => x.id === link?.treatmentId)
  const doctor = doctors.find(x => x.id === link?.doctorId)
  const slots = useMemo(()=>['09:00','09:30','10:00','10:30','11:00','14:00','14:30','15:00','15:30','16:00'],[])
  const resourceId=link?.roomId||resources.find(resource=>resource.active)?.id||''
  const doctorId=link?.doctorId||doctors[0]?.id||''
  const duration=link?.duration||treatment?.duration||30
  const getSlots=useCallback(async(date,serviceId)=>{const selected=treatments.find(item=>item.id===serviceId);const selectedDuration=selected?.duration||duration;return slots.filter(slot=>{
    const [hour,minute]=slot.split(':').map(Number);const start=hour*60+minute;const end=start+duration
    return !appointments.some(a=>{const [aHour,aMinute]=a.time.split(':').map(Number);const aStart=aHour*60+aMinute;const aEnd=aStart+Number(a.duration||30);return a.date===date&&!['Annulé','No-show'].includes(a.status)&&(a.doctorId===doctorId||(resourceId&&a.roomId===resourceId))&&start<aEnd&&start+selectedDuration>aStart})
  })},[appointments,doctorId,duration,resourceId,slots,treatments])
  const onBook=useCallback(async form=>{
    const available=await getSlots(form.date,form.serviceId)
    if(!available.includes(form.time))throw new Error('Slot unavailable')
    const normalizedPhone=form.phone.replace(/[^0-9]/g,'')
    let patient=patients.find(p=>p.phone&&p.phone.replace(/[^0-9]/g,'')===normalizedPhone)
    if(!patient)patient=await add('patients',{firstName:form.firstName,lastName:form.lastName,phone:form.phone,email:form.email,createdAt:todayISO(),status:'Actif'})
    const recent=appointments.filter(appointment=>appointment.patientId===patient.id&&appointment.source==='public'&&Date.parse(appointment.createdAt||0)>Date.now()-30*60*1000).length
    if(recent>=3)throw new Error('Booking rate limit exceeded')
    const selected=treatments.find(item=>item.id===form.serviceId)||treatment
    return add('appointments',{patientId:patient.id,doctorId,treatmentId:selected?.id||link.treatmentId,roomId:resourceId,date:form.date,time:form.time,duration:selected?.duration||duration,reason:form.reason,status:link.confirmationPolicy==='manual'?'En attente':'Confirmé',source:'public',createdAt:new Date().toISOString(),reference:`RDV-${Date.now().toString(36).toUpperCase()}`,serviceName:selected?.name})
  },[add,appointments,doctorId,duration,getSlots,link,patients,resourceId,treatment,treatments])
  if(!link) return <main className="public-booking"><div className="public-card"><h1>Lien indisponible</h1><p>Cette page de réservation n’est pas publiée.</p></div></main>
  return <BookingExperience config={{...link,slug,defaultServiceId:link.treatmentId,services:treatments.filter(item=>item.active!==false).map(item=>({...item,description:item.description||'',duration:item.duration||30})),duration:link.duration||treatment?.duration||30,doctorName:doctor?.name,clinicName:'Dental Spa',timezone:'Africa/Casablanca'}} getSlots={getSlots} onBook={onBook}/>
}
