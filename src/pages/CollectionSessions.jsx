import React, { useState } from 'react'
import { Calculator, LockKeyhole, Plus } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

export default function CollectionSessions(){
  const {collectionSessions,payments,currentUser,clinic,add,update,rejectSession,can}=useData()
  const [open,setOpen]=useState(false)
  const [counted,setCounted]=useState('')
  const [rejecting,setRejecting]=useState(null)
  const [reason,setReason]=useState('')
  const [error,setError]=useState('')
  const [busy,setBusy]=useState(false)
  const ownSessions=collectionSessions.filter(row=>row.openedBy===currentUser?.id)
  const visibleSessions=can('sessions.manage')?collectionSessions:ownSessions
  const current=ownSessions.find(row=>row.status==='Open')
  const currentPayments=current?payments.filter(row=>row.sessionId===current.id):[]
  const currentTotal=current?.liveTotal??currentPayments.reduce((sum,row)=>sum+Number(row.paid||0),0)
  const currentCash=current?.liveCash??Number(current?.openingCash||0)+currentPayments.filter(row=>row.method==='Espèces').reduce((sum,row)=>sum+Number(row.paid||0),0)
  async function act(callback){setBusy(true);setError('');try{await callback()}catch(err){setError(err.message||'Opération impossible.')}finally{setBusy(false)}}
  function start(e){e.preventDefault();const openingCash=Number(e.target.openingCash.value||0);act(async()=>{await add('collectionSessions',{openedBy:currentUser?.id,openingCash,openedAt:new Date().toISOString(),date:todayISO(),status:'Open'});setOpen(false)})}
  function closeSession(){if(!current||counted==='')return;act(async()=>{await update('collectionSessions',current.id,{status:'Submitted',countedCash:Number(counted),recordedTotal:currentTotal,recordedCash:currentCash,discrepancy:Number(counted)-currentCash,closedAt:new Date().toISOString()});setCounted('')})}
  function validateSession(id){act(()=>update('collectionSessions',id,{status:'Validated',validatedAt:new Date().toISOString(),validatedBy:currentUser?.id}))}
  function reject(){if(!rejecting)return;act(async()=>{await rejectSession(rejecting.id,reason);setRejecting(null);setReason('')})}
  return <>
    <Topbar title="Sessions de caisse" subtitle="Collecte personnelle, rapprochement des espèces et validation administrative."/>
    <div className="report-cards"><div><span>Encaissement net de ma session</span><strong>{money(currentTotal,clinic.currency)}</strong></div><div><span>Espèces attendues, fonds inclus</span><strong>{money(currentCash,clinic.currency)}</strong></div><div><span>Opérations visibles</span><strong>{currentPayments.length}</strong></div></div>
    <section className="panel"><div className="toolbar"><span className="soft-badge"><Calculator size={14}/> {can('sessions.manage')?'Toutes les sessions':'Mes sessions uniquement'}</span>{can('sessions.own')&&!current&&<button className="primary-btn" onClick={()=>setOpen(true)}><Plus size={17}/> Ouvrir ma session</button>}</div>
      {current&&<div className="session-close"><div><h3>Session ouverte</h3><p>Ouverte le {new Date(current.openedAt).toLocaleString('fr-FR')} · espèces attendues {money(currentCash,clinic.currency)}</p></div><div className="form-actions"><input className="session-input" aria-label="Espèces comptées" type="number" min="0" step="0.01" placeholder="Espèces comptées" value={counted} onChange={e=>setCounted(e.target.value)}/><button className="primary-btn" disabled={busy||counted===''} onClick={closeSession}><LockKeyhole size={15}/> Soumettre</button></div></div>}
      {error&&<div className="form-error" role="alert">{error}</div>}
      <div className="table-wrap"><table><thead><tr><th>Date</th><th>Collecteur</th><th>Statut</th><th>Total net</th><th>Espèces attendues</th><th>Comptées</th><th>Écart</th><th>Décision</th></tr></thead><tbody>{visibleSessions.slice().reverse().map(row=><tr key={row.id}><td>{row.date}</td><td>{row.openedBy===currentUser?.id?'Moi':row.openedBy}</td><td><span className={`status ${row.status==='Validated'?'ok':'wait'}`}>{row.status}</span></td><td>{money(row.recordedTotal??row.liveTotal,clinic.currency)}</td><td>{money(row.recordedCash??row.liveCash,clinic.currency)}</td><td>{row.countedCash==null?'—':money(row.countedCash,clinic.currency)}</td><td>{row.discrepancy==null?'—':money(row.discrepancy,clinic.currency)}</td><td>{can('sessions.manage')&&row.status==='Submitted'?<div className="table-actions"><button className="ghost-btn" disabled={busy} onClick={()=>validateSession(row.id)}>Valider</button><button className="ghost-btn" disabled={busy} onClick={()=>{setRejecting(row);setReason('')}}>Rejeter</button></div>:row.rejectionReason||'—'}</td></tr>)}</tbody></table></div>
    </section>
    <Modal open={open} onClose={()=>setOpen(false)} title="Ouvrir une session" subtitle="Une session personnelle est requise pour encaisser à l’accueil."><form onSubmit={start} className="form-grid"><label className="full">Fonds de caisse initial<input name="openingCash" type="number" min="0" step="0.01" defaultValue="0"/></label><div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn" disabled={busy}>Ouvrir</button></div></form></Modal>
    <Modal open={Boolean(rejecting)} onClose={()=>setRejecting(null)} title="Rejeter une clôture" subtitle="Le montant soumis reste conservé pour le contrôle."><form className="form-grid" onSubmit={e=>{e.preventDefault();reject()}}><label className="full">Motif<textarea required minLength="4" value={reason} onChange={e=>setReason(e.target.value)}/></label><div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setRejecting(null)}>Annuler</button><button className="primary-btn" disabled={busy}>Rejeter</button></div></form></Modal>
  </>
}
