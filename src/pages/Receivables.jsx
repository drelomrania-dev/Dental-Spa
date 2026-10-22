import React, { useState } from 'react'
import { AlertCircle, WalletCards } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money } from '../utils'

const labels={paid:'Payée',late:'En retard',due:'À échéance',rescheduled:'Reprogrammée'}

export default function Receivables(){
  const {balances,patientName,treatmentName,clinic,can,rescheduleInstallment,scheduleHistoricalAccount}=useData()
  const [selected,setSelected]=useState(null)
  const [historical,setHistorical]=useState(null)
  const [count,setCount]=useState(6)
  const [dueDate,setDueDate]=useState('')
  const [reason,setReason]=useState('')
  const [error,setError]=useState('')
  const [saving,setSaving]=useState(false)
  const rows=balances.filter(row=>Number(row.remaining)>0).sort((a,b)=>Number(b.remaining)-Number(a.remaining))
  const total=rows.reduce((sum,row)=>sum+Number(row.remaining||0),0)
  function openReschedule(item){setSelected(item);setDueDate(item.dueDate);setReason('');setError('')}
  function openHistorical(account){setHistorical(account);setDueDate('');setCount(6);setReason('');setError('')}
  async function submit(e){
    e.preventDefault();setSaving(true);setError('')
    try{await rescheduleInstallment(selected.id,dueDate,reason);setSelected(null)}
    catch(err){setError(err.message||'Reprogrammation impossible.')}
    finally{setSaving(false)}
  }
  async function submitHistorical(e){
    e.preventDefault();setSaving(true);setError('')
    try{await scheduleHistoricalAccount(historical.id,dueDate,count,reason);setHistorical(null)}
    catch(err){setError(err.message||'Planification impossible.')}
    finally{setSaving(false)}
  }
  return <>
    <Topbar title="Soldes à recevoir" subtitle="Comptes ouverts et échéances datées, calculés depuis le registre."/>
    <div className="hero-balance"><div className="hero-icon"><WalletCards size={28}/></div><div><span>Total restant à encaisser</span><strong>{money(total,clinic.currency)}</strong><p>{rows.length} dossier(s) avec un solde ouvert</p></div></div>
    <section className="panel"><div className="panel-head"><div><h3>Dossiers ouverts</h3><p>Prix et plan figés à l’ouverture du compte</p></div><span className="soft-badge"><AlertCircle size={14}/> À suivre</span></div>
      <div className="table-wrap"><table><thead><tr><th>Patient</th><th>Soin</th><th>Total</th><th>Déjà payé</th><th>Reste</th><th>Plan</th><th>Échéances</th></tr></thead><tbody>{rows.map(row=><tr key={row.id||`${row.patientId}:${row.treatmentId}`}><td><strong>{patientName(row.patientId)}</strong></td><td>{treatmentName(row.treatmentId)}</td><td>{money(row.total,row.currency||clinic.currency)}</td><td>{money(row.paid,row.currency||clinic.currency)}</td><td><strong className="danger-text">{money(row.remaining,row.currency||clinic.currency)}</strong></td><td>{row.plan}</td><td>{row.installments?.length?row.installments.map(item=><div key={item.id} className="installment-row"><span>{item.sequence}. {item.dueDate} · {money(item.remaining,row.currency||clinic.currency)} · {labels[item.status]||item.status}</span>{can('payments.correct')&&item.status!=='paid'&&<button type="button" className="ghost-btn" onClick={()=>openReschedule(item)}>Reprogrammer</button>}</div>):<div className="installment-row"><span>Dates historiques non définies</span>{can('payments.correct')&&row.id&&<button type="button" className="ghost-btn" onClick={()=>openHistorical(row)}>Saisir les dates</button>}</div>}</td></tr>)}</tbody></table></div>
      {!rows.length&&<div className="empty-state">Aucun solde ouvert.</div>}
    </section>
    <Modal open={Boolean(selected)} onClose={()=>setSelected(null)} title="Reprogrammer une échéance" subtitle="La date initiale et chaque modification restent dans l’historique."><form className="form-grid" onSubmit={submit}><label>Nouvelle date<input required type="date" value={dueDate} onChange={e=>setDueDate(e.target.value)}/></label><label className="full">Motif<textarea required minLength="4" value={reason} onChange={e=>setReason(e.target.value)}/></label>{error&&<div className="form-error full" role="alert">{error}</div>}<div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setSelected(null)}>Annuler</button><button className="primary-btn" disabled={saving}>Enregistrer</button></div></form></Modal>
    <Modal open={Boolean(historical)} onClose={()=>setHistorical(null)} title="Saisir les échéances historiques" subtitle="Renseignez la première date du plan convenu. Le prix et le plan du compte restent figés."><form className="form-grid" onSubmit={submitHistorical}><label>Première échéance prévue<input required type="date" value={dueDate} onChange={e=>setDueDate(e.target.value)}/></label>{historical?.plan==='Mensuel'&&<label>Nombre de mensualités<input required type="number" min="2" max="60" value={count} onChange={e=>setCount(e.target.value)}/></label>}<label className="full">Source des dates<textarea required minLength="4" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Ex. plan signé le 15/10/2026"/></label>{error&&<div className="form-error full" role="alert">{error}</div>}<div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setHistorical(null)}>Annuler</button><button className="primary-btn" disabled={saving}>Enregistrer les dates</button></div></form></Modal>
  </>
}
