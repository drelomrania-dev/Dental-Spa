import { addDoc, collection, deleteDoc, doc, getDocs, updateDoc } from 'firebase/firestore'
import { db, firebaseEnabled } from './firebase'
import { seedData } from '../data/seed'
import { remoteClinicId, supabase, supabaseEnabled } from './supabase'
import { loadFinanceSnapshot, openFinanceSession, recordFinancePayment, submitFinanceSession, validateFinanceSession } from './finance'
import { loadClinicalSnapshot } from './clinical'
import { createAppointment, loadAppointments, updateAppointment } from './appointments'

const PREFIX = 'dentalflow:'

function ensureLocal(name){
  const key = PREFIX + name
  const existing = localStorage.getItem(key)
  if (!existing) localStorage.setItem(key, JSON.stringify(seedData[name] || []))
}

function localList(name){
  ensureLocal(name)
  return JSON.parse(localStorage.getItem(PREFIX + name) || '[]')
}

function localSave(name, rows){
  localStorage.setItem(PREFIX + name, JSON.stringify(rows))
}

function patientFromRow(row){ return {id:row.app_id,firstName:row.first_name,lastName:row.last_name,phone:row.phone||'',email:row.email||'',dateOfBirth:row.date_of_birth||'',address:row.address||'',medicalAlerts:row.medical_alerts||'',status:row.status,createdAt:String(row.created_at||'').slice(0,10)} }
function patientToRow(data,clinicId){ return {clinic_id:clinicId,app_id:data.id,first_name:data.firstName,last_name:data.lastName,phone:data.phone||null,email:data.email||null,date_of_birth:data.dateOfBirth||null,address:data.address||null,medical_alerts:data.medicalAlerts||null,status:data.status||'Actif'} }

export async function listDocs(name){
  if (supabaseEnabled){
    if(name==='payments'||name==='collectionSessions'){
      const snapshot=await loadFinanceSnapshot()
      return name==='payments'?snapshot.payments:snapshot.sessions
    }
    if(name==='visits'||name==='treatmentPlans'||name==='priceRequests'){
      const snapshot=await loadClinicalSnapshot()
      return snapshot[name]
    }
    if(name==='appointments')return loadAppointments()
    const clinicId = await remoteClinicId()
    if(name==='patients'){
      const {data,error}=await supabase.from('patients').select('app_id,first_name,last_name,phone,email,date_of_birth,address,medical_alerts,status,created_at').eq('clinic_id',clinicId).order('created_at',{ascending:false})
      if(error)throw error
      return data.map(patientFromRow)
    }
    const { data, error } = await supabase.from('app_records').select('id,data').eq('clinic_id',clinicId).eq('collection',name).order('updated_at',{ascending:false})
    if(error) throw error
    return data.map(row => ({ ...row.data, id:row.id }))
  }
  if (!firebaseEnabled) return localList(name)
  const snapshot = await getDocs(collection(db, name))
  return snapshot.docs.map(d => ({ id:d.id, ...d.data() }))
}

export async function createDoc(name, data){
  if (supabaseEnabled){
    if(name==='payments') return recordFinancePayment(data)
    if(name==='collectionSessions') return openFinanceSession(data.openingCash)
    if(name==='appointments')return createAppointment(data)
    const id = data.id || crypto.randomUUID(); const clinicId = await remoteClinicId(); const payload = { ...data, id }
    if(name==='patients'){
      const {data:row,error}=await supabase.from('patients').insert(patientToRow(payload,clinicId)).select('app_id,first_name,last_name,phone,email,date_of_birth,address,medical_alerts,status,created_at').single()
      if(error)throw error
      return patientFromRow(row)
    }
    const { error } = await supabase.from('app_records').insert({clinic_id:clinicId,collection:name,id,data:payload})
    if(error) throw error
    return payload
  }
  if (!firebaseEnabled){
    const rows = localList(name)
    const row = { id: crypto.randomUUID(), ...data }
    rows.unshift(row)
    localSave(name, rows)
    return row
  }
  const ref = await addDoc(collection(db, name), data)
  return { id:ref.id, ...data }
}

export async function editDoc(name, id, patch){
  if (supabaseEnabled){
    if(name==='collectionSessions'){
      if(patch.status==='Submitted') return submitFinanceSession(id,patch.countedCash)
      if(patch.status==='Validated') return validateFinanceSession(id)
      throw new Error('Transition de session de caisse non prise en charge.')
    }
    if(name==='appointments')return updateAppointment(id,patch)
    const clinicId = await remoteClinicId()
    if(name==='patients'){
      const {data:existing,error:readError}=await supabase.from('patients').select('app_id,first_name,last_name,phone,email,date_of_birth,address,medical_alerts,status,created_at').eq('clinic_id',clinicId).eq('app_id',id).single()
      if(readError)throw readError
      const next={...patientFromRow(existing),...patch,id}; const row=patientToRow(next,clinicId); delete row.app_id; delete row.clinic_id
      const {error}=await supabase.from('patients').update(row).eq('clinic_id',clinicId).eq('app_id',id)
      if(error)throw error
      return next
    }
    const { data:row, error:readError } = await supabase.from('app_records').select('data').eq('clinic_id',clinicId).eq('collection',name).eq('id',id).single()
    if(readError) throw readError
    const next = { ...row.data, ...patch, id }
    const { error } = await supabase.from('app_records').update({data:next,updated_at:new Date().toISOString()}).eq('clinic_id',clinicId).eq('collection',name).eq('id',id)
    if(error) throw error
    return next
  }
  if (!firebaseEnabled){
    const rows = localList(name).map(r => r.id === id ? { ...r, ...patch } : r)
    localSave(name, rows)
    return rows.find(r => r.id === id)
  }
  await updateDoc(doc(db, name, id), patch)
  return { id, ...patch }
}

export async function removeDoc(name, id){
  if (supabaseEnabled){
    const clinicId = await remoteClinicId()
    if(name==='patients'){
      const {error}=await supabase.from('patients').delete().eq('clinic_id',clinicId).eq('app_id',id)
      if(error)throw error
      return
    }
    const { error } = await supabase.from('app_records').delete().eq('clinic_id',clinicId).eq('collection',name).eq('id',id)
    if(error) throw error
    return
  }
  if (!firebaseEnabled){
    localSave(name, localList(name).filter(r => r.id !== id))
    return
  }
  await deleteDoc(doc(db, name, id))
}

export function resetDemoData(){
  Object.entries(seedData).forEach(([name, rows]) => {
    localStorage.setItem(PREFIX + name, JSON.stringify(rows))
  })
}

export function getClinic(){
  return JSON.parse(localStorage.getItem(PREFIX + 'clinic') || JSON.stringify({
    name:'Dental Spa', phone:'', address:'Casablanca', timezone:'Africa/Casablanca', currency:'MAD',
    openingHours:{ monday:['09:00','18:00'], tuesday:['09:00','18:00'], wednesday:['09:00','18:00'], thursday:['09:00','18:00'], friday:['09:00','18:00'], saturday:['09:00','13:00'] },
    minimumNoticeHours:2, maximumAdvanceDays:90, bookingConfirmation:'auto', receiptPrefix:'REC'
  }))
}

export function saveClinic(clinic){ localStorage.setItem(PREFIX + 'clinic', JSON.stringify(clinic)); return clinic }

export async function loadClinic(){
  if(!supabaseEnabled) return getClinic()
  const rows = await listDocs('_clinic')
  return rows[0] || getClinic()
}

export async function persistClinic(clinic){
  if(!supabaseEnabled) return saveClinic(clinic)
  const clinicId = await remoteClinicId()
  const payload = { ...clinic, id:'settings' }
  const { error } = await supabase.from('app_records').upsert({clinic_id:clinicId,collection:'_clinic',id:'settings',data:payload,updated_at:new Date().toISOString()})
  if(error) throw error
  return payload
}

export function appointmentOverlaps(candidate, appointments){
  const start = toMinutes(candidate.time)
  const end = start + Number(candidate.duration || 30)
  return appointments.some(a => a.id !== candidate.id && a.date === candidate.date && ['Annulé','No-show'].includes(a.status) === false && (a.doctorId === candidate.doctorId || (candidate.roomId && a.roomId === candidate.roomId)) && start < toMinutes(a.time) + Number(a.duration || 30) && end > toMinutes(a.time))
}

function toMinutes(value='00:00'){ const [h,m] = String(value).split(':').map(Number); return h * 60 + m }

export function paymentBalance(payments, patientId, treatmentId){
  const rows = payments.filter(p => p.patientId === patientId && (!treatmentId || p.treatmentId === treatmentId) && p.status !== 'Annulé')
  const total = rows.reduce((sum,p) => sum + Number(p.total || 0), 0)
  const paid = rows.reduce((sum,p) => sum + Number(p.paid || 0), 0)
  return { total, paid, remaining: Math.max(0, total - paid) }
}

export function openBalances(payments){
  const groups = new Map()
  payments.filter(p=>p.status!=='Annulé').forEach(p=>{
    const key=`${p.patientId}:${p.treatmentId}`; const row=groups.get(key)||{patientId:p.patientId,treatmentId:p.treatmentId,total:0,paid:0,lastDate:'',plan:p.plan}
    row.total+=Number(p.total||0); row.paid+=Number(p.paid||0); if(String(p.date)>=row.lastDate){row.lastDate=p.date;row.plan=p.plan} groups.set(key,row)
  })
  return [...groups.values()].map(row=>({...row,remaining:Math.max(0,row.total-row.paid)}))
}

export function paymentIdempotencyExists(payments, key){ return payments.some(p => p.idempotencyKey && p.idempotencyKey === key) }

export function exportLocalData(){
  const payload = { exportedAt: new Date().toISOString(), version: 1, collections: {} }
  Object.keys(seedData).forEach(name => { payload.collections[name] = localList(name) })
  payload.clinic = getClinic()
  return JSON.stringify(payload, null, 2)
}

export function importLocalData(json){
  const payload = typeof json === 'string' ? JSON.parse(json) : json
  if(!payload || payload.version !== 1 || !payload.collections || typeof payload.collections !== 'object') throw new Error('Fichier de sauvegarde Dental Spa invalide.')
  Object.keys(seedData).forEach(name => {
    if(Array.isArray(payload.collections[name])) localSave(name, payload.collections[name])
  })
  if(payload.clinic && typeof payload.clinic === 'object') saveClinic(payload.clinic)
  return true
}
