import React, { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { appointmentOverlaps, createDoc, editDoc, getClinic, listDocs, loadClinic, openBalances, paymentBalance, paymentIdempotencyExists, persistClinic, removeDoc } from './services/dataStore'
import { useAuth } from './AuthContext'
import { supabaseEnabled } from './services/supabase'

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
    if(name === 'appointments') {
      const existing = data.appointments.find(x => x.id === id)
      const candidate = { ...existing, ...patch }
      if(appointmentOverlaps(candidate, data.appointments)) throw new Error('Ce créneau est déjà occupé pour ce praticien ou cette salle.')
      if(patch.status && patch.status !== existing?.status && !(appointmentTransitions[existing?.status] || []).includes(patch.status)) throw new Error(`Transition impossible : ${existing?.status} → ${patch.status}.`)
    }
    await editDoc(name, id, patch)
    setData(prev => ({ ...prev, [name]: prev[name].map(r => r.id === id ? { ...r, ...patch } : r) }))
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
  return <DataContext.Provider value={{ ...data, clinic, loading, dataError, add, update, remove, updateClinic, switchUser, ...helpers }}>{children}</DataContext.Provider>
}

export function useData(){
  const ctx = useContext(DataContext)
  if(!ctx) throw new Error('useData must be used inside DataProvider')
  return ctx
}
