import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { appointmentOverlaps, createDoc, editDoc, getClinic, listDocs, loadClinic, openBalances, paymentBalance, paymentIdempotencyExists, persistClinic, removeDoc } from './services/dataStore'
import { useAuth } from './AuthContext'
import { supabaseEnabled } from './services/supabase'
import { correctFinancePayment, getFinanceBalance, initializeFinanceSchedule, rescheduleFinanceInstallment, rejectFinanceSession } from './services/finance'
import { decideClinicalPrice as decideClinicalPriceRemote, recordClinicalVisit as recordClinicalVisitRemote, requestClinicalPrice as requestClinicalPriceRemote, updateClinicalVisit as updateClinicalVisitRemote, updateTreatmentPlanStatus as updateTreatmentPlanStatusRemote } from './services/clinical'

const DataContext = createContext(null)
const collections = ['patients','treatments','doctors','resources','appointments','payments','financeAccounts','visits','treatmentPlans','priceTargets','priceRequests','collectionSessions','auditEvents','bookingLinks','staff','roles']
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
    const granted=new Set((access?.permissions||[]).map(item=>typeof item==='string'?item:item.permission))
    const allowed=name=>!supabaseEnabled||access?.role==='administrator'||granted.has('*')||({
      patients:['patients.basic.view','patients.create','patients.edit','payments.collect','clinical.view'],
      appointments:['appointments.view','appointments.create','appointments.edit'],
      payments:['payments.collect','payments.view.own','payments.view.all','payments.correct','sessions.own','sessions.manage'],
      financeAccounts:['payments.view.all'],
      collectionSessions:['payments.collect','sessions.own','sessions.manage'],
      visits:['clinical.view'],treatmentPlans:['clinical.view','plans.create'],priceTargets:['priceRequests.create'],
      priceRequests:['priceRequests.create','priceRequests.approve'],auditEvents:['audit.view'],
      resources:['appointments.view','services.view','services.manage','settings.manage'],
      staff:['staff.manage'],roles:['permissions.manage']
    }[name]||[]).some(permission=>granted.has(permission))||['treatments','doctors','bookingLinks'].includes(name)
    Promise.all([Promise.all(collections.map(async name => [name,allowed(name)?await listDocs(name):[]])), loadClinic()])
      .then(([entries,clinicData]) => { if(live){ setData(Object.fromEntries(entries)); setClinicState(clinicData) } })
      .catch(err=>{console.error('Dental Spa data loading failed',err);if(live)setDataError(err.message||'Impossible de charger les données Supabase.')})
      .finally(() => { if(live) setLoading(false) })
    return () => { live = false }
  }, [access?.id])

  async function add(name, payload){
    if(name === 'appointments' && appointmentOverlaps(payload, data.appointments)) throw new Error('Ce créneau est déjà occupé pour ce praticien ou cette salle.')
    if(name === 'payments' && payload.idempotencyKey && paymentIdempotencyExists(data.payments, payload.idempotencyKey)) throw new Error('Cette opération de paiement a déjà été enregistrée.')
    const row = await createDoc(name, payload)
    if(name==='payments'&&supabaseEnabled){
      let account=null
      try{account=await getFinanceBalance(payload.patientId,payload.treatmentId)}catch(error){console.warn('Payment saved; account refresh deferred',error)}
      setData(prev=>({...prev,payments:prev.payments.some(x=>x.id===row.id)?prev.payments:[row,...prev.payments],financeAccounts:account?(prev.financeAccounts.some(x=>x.id===account.id)?prev.financeAccounts.map(x=>x.id===account.id?account:x):[account,...prev.financeAccounts]):prev.financeAccounts}))
    }else setData(prev => ({ ...prev, [name]: [row, ...prev[name]] }))
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

  async function correctPayment(paymentId,amount,reason,idempotencyKey){
    if(supabaseEnabled){
      const row=await correctFinancePayment(paymentId,amount,reason,idempotencyKey)
      let account=null
      try{account=await getFinanceBalance(row.patientId,row.treatmentId)}catch(error){console.warn('Correction saved; account refresh deferred',error)}
      setData(prev=>({...prev,payments:prev.payments.some(x=>x.id===row.id)?prev.payments:[row,...prev.payments],financeAccounts:account?prev.financeAccounts.map(x=>x.id===account.id?account:x):prev.financeAccounts}))
      return row
    }
    const original=data.payments.find(row=>row.id===paymentId)
    if(!original)throw new Error('Paiement introuvable.')
    return add('payments',{patientId:original.patientId,treatmentId:original.treatmentId,doctorId:original.doctorId,date:new Date().toISOString().slice(0,10),total:0,paid:-Number(amount),remaining:0,plan:original.plan,method:original.method,status:'Correction',reference:`AVOIR-${String(Date.now()).slice(-6)}`,idempotencyKey:`correction:${paymentId}:${crypto.randomUUID()}`,collectorUserId:currentUserId,sessionId:original.sessionId||'',kind:'refund',reason})
  }

  async function rescheduleInstallment(id,dueDate,reason){
    if(!supabaseEnabled)throw new Error('La reprogrammation requiert le registre serveur.')
    const item=await rescheduleFinanceInstallment(id,dueDate,reason)
    setData(prev=>({...prev,financeAccounts:prev.financeAccounts.map(account=>({...account,installments:account.installments?.map(existing=>existing.id===id?item:existing)}))}))
    return item
  }

  async function scheduleHistoricalAccount(id,firstDueDate,installmentCount,reason){
    if(!supabaseEnabled)throw new Error('La planification historique requiert le registre serveur.')
    const account=await initializeFinanceSchedule(id,firstDueDate,installmentCount,reason)
    setData(prev=>({...prev,financeAccounts:prev.financeAccounts.map(existing=>existing.id===id?account:existing)}))
    return account
  }

  async function rejectSession(id,reason){
    if(!supabaseEnabled)throw new Error('Le rejet requiert le registre serveur.')
    const row=await rejectFinanceSession(id,reason)
    setData(prev=>({...prev,collectionSessions:prev.collectionSessions.map(existing=>existing.id===id?{...existing,...row}:existing)}))
    return row
  }

  async function createClinicalVisit(payload){
    if(supabaseEnabled){
      const result=await recordClinicalVisitRemote(payload)
      setData(prev=>({...prev,visits:[result.visit,...prev.visits],treatmentPlans:result.plan?[result.plan,...prev.treatmentPlans]:prev.treatmentPlans}))
      return result
    }
    const treatment=data.treatments.find(row=>row.id===payload.treatmentId)
    if(payload.appointmentId&&data.visits.some(row=>row.appointmentId===payload.appointmentId))throw new Error('Ce rendez-vous a déjà une consultation.')
    const visit=await add('visits',{patientId:payload.patientId,doctorId:payload.doctorId,appointmentId:payload.appointmentId||'',date:new Date().toISOString().slice(0,10),notes:payload.notes,followUp:payload.followUp,status:'Terminé',services:treatment?[{treatmentId:treatment.id,name:treatment.name,price:treatment.price}]:[]})
    let plan=null
    if(treatment&&payload.createPlan)plan=await add('treatmentPlans',{patientId:payload.patientId,doctorId:payload.doctorId,visitId:visit.id,date:new Date().toISOString().slice(0,10),status:'Proposé',items:[{id:crypto.randomUUID(),treatmentId:treatment.id,name:treatment.name,quantity:1,originalPrice:Number(treatment.price),effectivePrice:Number(treatment.price),status:'Proposé'}],originalTotal:Number(treatment.price),total:Number(treatment.price)})
    return {visit,plan}
  }

  async function updateClinicalVisit(id,notes,followUp){
    const row=supabaseEnabled?await updateClinicalVisitRemote(id,notes,followUp):await editDoc('visits',id,{notes,followUp})
    setData(prev=>({...prev,visits:prev.visits.map(visit=>visit.id===id?row:visit)}))
    return row
  }

  async function updateTreatmentPlanStatus(id,status){
    const row=supabaseEnabled?await updateTreatmentPlanStatusRemote(id,status):await editDoc('treatmentPlans',id,{status})
    setData(prev=>({...prev,treatmentPlans:prev.treatmentPlans.map(plan=>plan.id===id?row:plan)}))
    return row
  }

  async function requestPrice(payload){
    const treatment=data.treatments.find(row=>row.id===payload.treatmentId)
    if(!treatment)throw new Error('Soin introuvable.')
    const target=data.priceTargets.find(row=>row.patientId===payload.patientId&&row.treatmentId===payload.treatmentId)
    const plan=data.treatmentPlans.find(row=>row.patientId===payload.patientId&&row.items?.some(item=>item.treatmentId===payload.treatmentId))
    const item=plan?.items.find(row=>row.treatmentId===payload.treatmentId)
    const proposed=Number(payload.proposedPrice)
    const standard=Number(target?.standardPrice??item?.originalPrice??treatment.price)
    if(!Number.isFinite(proposed)||proposed<0||proposed>=standard)throw new Error('Le prix proposé doit être inférieur au prix standard.')
    const command={...payload,planId:target?.planId||plan?.id||'',planItemId:target?.planItemId||item?.id||'',standardPrice:standard,proposedPrice:proposed}
    if(supabaseEnabled){
      const row=await requestClinicalPriceRemote(command)
      setData(prev=>({...prev,priceRequests:[row,...prev.priceRequests]}))
      return row
    }
    return add('priceRequests',{...command,discountAmount:standard-proposed,discountPercent:Math.round((1-proposed/standard)*100),requestedBy:data.staff.find(row=>row.id===currentUserId)?.id||'u2',requestedAt:new Date().toISOString().slice(0,10),status:'Pending'})
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
    balances: supabaseEnabled?data.financeAccounts:openBalances(data.payments),
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
  return <DataContext.Provider value={{ ...data, clinic, loading, dataError, add, update, remove, updateClinic, switchUser, financeBalance, correctPayment, rescheduleInstallment, scheduleHistoricalAccount, rejectSession, createClinicalVisit, updateClinicalVisit, updateTreatmentPlanStatus, requestPrice, decidePrice, ...helpers }}>{children}</DataContext.Provider>
}

export function useData(){
  const ctx = useContext(DataContext)
  if(!ctx) throw new Error('useData must be used inside DataProvider')
  return ctx
}
