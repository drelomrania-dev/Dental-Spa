import React, { useCallback, useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { supabase } from '../services/supabase'
import BookingExperience from '../components/BookingExperience'

export default function PublicBookingRemote(){
  const {slug}=useParams(); const [link,setLink]=useState(null); const [loading,setLoading]=useState(true); const [error,setError]=useState('')
  useEffect(()=>{let live=true;supabase.rpc('public_booking_page',{p_slug:slug}).then(({data,error:rpcError})=>{if(live){setLink(data);setError(rpcError?.message||'');setLoading(false)}});return()=>{live=false}},[slug])
  const getSlots=useCallback(async date=>{const {data,error:rpcError}=await supabase.rpc('public_available_slots',{p_slug:slug,p_date:date});if(rpcError)throw rpcError;return data||[]},[slug])
  const onBook=useCallback(async form=>{const {data,error:rpcError}=await supabase.rpc('public_create_booking',{p_slug:slug,p_date:form.date,p_time:form.time,p_first_name:form.firstName,p_last_name:form.lastName,p_phone:form.phone,p_email:form.email||null});if(rpcError)throw rpcError;return data},[slug])
  if(loading)return <main className="public-booking"><div className="public-card"><p>Chargement des disponibilités…</p></div></main>
  if(!link||error)return <main className="public-booking"><div className="public-card"><h1>Lien indisponible</h1><p>{error||'Cette page de réservation n’est pas publiée.'}</p></div></main>
  return <BookingExperience config={{...link,slug}} getSlots={getSlots} onBook={onBook}/>
}
