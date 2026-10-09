import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { appointmentOverlaps, createDoc, editDoc, getClinic, listDocs, loadClinic, openBalances, paymentBalance, paymentIdempotencyExists, persistClinic, removeDoc } from './services/dataStore'
import { useAuth } from './AuthContext'
import { supabaseEnabled } from './services/supabase'
import { correctFinancePayment, getFinanceBalance } from './services/finance'
import { decideClinicalPrice as decideClinicalPriceRemote, recordClinicalVisit as recordClinicalVisitRemote, requestClinicalPrice as requestClinicalPriceRemote } from './services/clinical'

const DataContext = createContext(null)
const collections = ['patients','treatments','doctors','appointments','payments','visits','treatmentPlans','priceRequests','collectionSessions','auditEvents','bookingLinks','staff','roles']
const appointmentTransitions = {
  'En attente':['Confirmé','Annulé'], 'Confirmé':['Arrivé','Annulé','No-show'], 'Arrivé':['En attente clinique','En consultation','Annulé'],
  'En attente clinique':['En consultation','Annulé'], 'En consultation':['Terminé','Annulé'], 'Terminé':[], 'Annulé':[], 'No-show':[]
}

export function DataProvider({ children }){
  const {access}=useAuth()
  const [data, setData] = useState(Object.fromEntries(collections.map(x => [x, []])))
  const [clinic, setClinicState] = useState(getClinic)
  const [currentUserId, setCurrentUserId] = useState(() => localStorage.getItem('dentalflow:currentUser') || 'u1')
  const [loading, setLoading] = useState(true)
  const [dataError,setDataError]=useState('')

  useEffect(() => {
    let live = true
    Promise.all([Promise.all(collections.map(async name => [name, await listDocs(name)])), loadClinic()])
      .then(([entries,clinicData]) => { if(live){ setData(Object.fromEntries(entries)); setClinicState(clinicData) } })
      .catch(err=>{console.error('Dental Spa data loading failed',err);if(live)setDataError(err.message||'Impossible de charger les données Supabase.')})
      .finally(() => { if(live) setLoading(false) })
    return () => { live = false }
  }, [])

  async function add(name, payload){
    if(name === 'appointments' && appointmentOverlaps(payload, data.appointments)) throw new Error('Ce créneau est déjà occupé pour ce praticien ou cette salle.')
    if(name === 'payments' && payload.idempotencyKey && paymentIdempotencyExists(data.payments, payload.idempotencyKey)) throw new Error('Cette opération de paiement a déjà été enregistrée.')
    const row = await createDoc(name, payload)
    setData(prev => ({ ...prev, [name]: [row, ...prev[name]] }))
    return row
  }

  async function updateClinic(patch){ const next = { ...clinic, ...patch }; await persistClinic(next); setClinicState(next); return next }

  async function update(name, id, patch){
    let payloadForSave=patch
    if(name === 'appointments') {
      const existing = data.appointments.find(x => x.id === id)
      const candidate = { ...existing, ...patch }
      if(appointmentOverlaps(candidate, data.appointments)) throw new Error('Ce créneau est déjà occupé pour ce praticien ou cette salle.')
      if(patch.status && patch.status !== existing?.status && !(appointmentTransitions[existing?.status] || []).includes(patch.status)) throw new Error(`Transition impossible : ${existing?.status} → ${patch.status}.`)
      payloadForSave=candidate
    }
    const saved=await editDoc(name, id, payloadForSave)
    setData(prev => ({ ...prev, [name]: prev[name].map(r => r.id === id ? { ...r, ...patch, ...saved } : r) }))
  }

  const financeBalance=useCallback(async(patientId,treatmentId)=>{
    if(supabaseEnabled)return getFinanceBalance(patientId,treatmentId)
    return paymentBalance(data.payments,patientId,treatmentId)
  },[data.payments])

  async function correctPayment(paymentId,amount,reason){
    if(supabaseEnabled){
      const row=await correctFinancePayment(paymentId,amount,reason)
      setData(prev=>({...prev,payments:[row,...prev.payments]}))
      return row
    }
    const original=data.payments.find(row=>row.id===paymentId)
    if(!original)throw new Error('Paiement introuvable.')
    return add('payments',{patientId:original.patientId,treatmentId:original.treatmentId,doctorId:original.doctorId,date:new Date().toISOString().slice(0,10),total:0,paid:-Number(amount),remaining:0,plan:original.plan,method:original.method,status:'Correction',reference:`AVOIR-${String(Date.now()).slice(-6)}`,idempotencyKey:`correction:${paymentId}:${crypto.randomUUID()}`,collectorUserId:currentUserId,sessionId:original.sessionId||'',kind:'refund',reason})
  }

  async function createClinicalVisit(payload){
    if(supabaseEnabled){
      const result=await recordClinicalVisitRemote(payload)
      setData(prev=>({...prev,visits:[result.visit,...prev.visits],treatmentPlans:result.plan?[result.plan,...prev.treatmentPlans]:prev.treatmentPlans}))
      return result
    }
    const treatment=data.treatments.find(row=>row.id===payload.treatmentId)
    const visit=await add('visits',{patientId:payload.patientId,doctorId:payload.doctorId,date:new Date().toISOString().slice(0,10),notes:payload.notes,followUp:payload.followUp,status:'Terminé',services:treatment?[{treatmentId:treatment.id,name:treatment.name,price:treatment.price}]:[]})
    let plan=null
    if(treatment&&payload.createPlan)plan=await add('treatmentPlans',{patientId:payload.patientId,doctorId:payload.doctorId,visitId:visit.id,date:new Date().toISOString().slice(0,10),status:'Proposé',items:[{id:crypto.randomUUID(),treatmentId:treatment.id,name:treatment.name,quantity:1,originalPrice:Number(treatment.price),effectivePrice:Number(treatment.price),status:'Proposé'}],originalTotal:Number(treatment.price),total:Number(treatment.price)})
    return {visit,plan}
  }

  async function requestPrice(payload){
    const treatment=data.treatments.find(row=>row.id===payload.treatmentId)
    if(!treatment)throw new Error('Soin introuvable.')
    const plan=data.treatmentPlans.find(row=>row.patientId===payload.patientId&&row.items?.some(item=>item.treatmentId===payload.treatmentId))
    const item=plan?.items.find(row=>row.treatmentId===payload.treatmentId)
    const proposed=Number(payload.proposedPrice)
    if(proposed>=Number(treatment.price))throw new Error('Le prix proposé doit être inférieur au prix standard.')
    const command={...payload,planId:plan?.id||'',planItemId:item?.id||'',standardPrice:Number(treatment.price),proposedPrice:proposed}
    if(supabaseEnabled){
      const row=await requestClinicalPriceRemote(command)
      setData(prev=>({...prev,priceRequests:[row,...prev.priceRequests]}))
      return row
    }
    return add('priceRequests',{...command,discountAmount:Number(treatment.price)-proposed,discountPercent:Math.round((1-proposed/Number(treatment.price))*100),requestedBy:data.staff.find(row=>row.id===currentUserId)?.id||'u2',requestedAt:new Date().toISOString().slice(0,10),status:'Pending'})
  }

  async function decidePrice(requestId,status){
    const request=data.priceRequests.find(row=>row.id===requestId)
    if(!request)throw new Error('Demande de prix introuvable.')
    const actorId=supabaseEnabled?access?.id:(data.staff.find(row=>row.id===currentUserId)?.id||'u1')
    if(request.requestedBy===actorId)throw new Error('Vous ne pouvez pas approuver votre propre demande.')
    if(supabaseEnabled){
      const result=await decideClinicalPriceRemote(requestId,status,status==='Rejected'?'Prix non validé':'Prix approuvé')
      setData(prev=>({...prev,priceRequests:prev.priceRequests.map(row=>row.id===requestId?result.request:row),treatmentPlans:result.plan?prev.treatmentPlans.map(row=>row.id===result.plan.id?result.plan:row):prev.treatmentPlans}))
      return result
    }
    await update('priceRequests',requestId,{status,decidedBy:actorId,decidedAt:new Date().toISOString().slice(0,10),decisionReason:status==='Rejected'?'Prix non validé':'Prix approuvé'})
    if(status==='Approved'&&request.planId){
      const plan=data.treatmentPlans.find(row=>row.id===request.planId)
      if(plan){const items=plan.items.map(item=>item.id===request.planItemId?{...item,effectivePrice:Number(request.proposedPrice),status:'Approuvé'}:item);await update('treatmentPlans',plan.id,{items,total:items.reduce((sum,item)=>sum+Number(item.effectivePrice||item.originalPrice||0)*Number(item.quantity||1),0),status:'Accepté'})}
    }
  }

  async function remove(name, id){
    await removeDoc(name, id)
    setData(prev => ({ ...prev, [name]: prev[name].filter(r => r.id !== id) }))
  }

  const helpers = useMemo(() => ({
    patientName: id => {
      const p = data.patients.find(x => x.id === id)
      return p ? `${p.firstName} ${p.lastName}` : 'Patient inconnu'
    },
    doctorName: id => data.doctors.find(x => x.id === id)?.name || 'Non assigné',
    treatmentName: id => data.treatments.find(x => x.id === id)?.name || 'Soin',
    balanceFor: (patientId, treatmentId) => paymentBalance(data.payments, patientId, treatmentId),
    balances: openBalances(data.payments),
    currentUser: supabaseEnabled&&access?{id:access.id,name:access.displayName,role:access.role,email:''}:data.staff.find(x => x.id === currentUserId) || data.staff[0],
    can: permission => {
      if(supabaseEnabled&&access){const permissions=access.permissions||[];return permissions.includes('*')||permissions.some(item=>(typeof item==='string'?item:item.permission)===permission)}
      const user = data.staff.find(x => x.id === currentUserId)
      const roleId = user?.role === 'administrator' ? 'role-admin' : user?.role === 'practitioner' ? 'role-practitioner' : 'role-assistant'
      const role = data.roles.find(x => x.id === roleId)
      return Boolean(role?.permissions?.includes('*') || role?.permissions?.includes(permission))
    }
  }), [data, currentUserId, access])

  function switchUser(id){ localStorage.setItem('dentalflow:currentUser', id); setCurrentUserId(id) }
  return <DataContext.Provider value={{ ...data, clinic, loading, dataError, add, update, remove, updateClinic, switchUser, financeBalance, correctPayment, createClinicalVisit, requestPrice, decidePrice, ...helpers }}>{children}</DataContext.Provider>
}

export function useData(){
  const ctx = useContext(DataContext)
  if(!ctx) throw new Error('useData must be used inside DataProvider')
  return ctx
}
