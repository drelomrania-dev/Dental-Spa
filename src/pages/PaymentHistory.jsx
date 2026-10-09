import React, { useMemo, useState } from 'react'
import { Download, FileDown, RotateCcw, Search } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money } from '../utils'
import { downloadPaymentReceiptPdf } from '../services/receiptPdf'

export default function PaymentHistory(){
  const { payments,patientName,treatmentName,clinic,correctPayment,can } = useData()
  const [query,setQuery] = useState('')
  const [method,setMethod] = useState('Tous')
  const [correction,setCorrection] = useState(null)
  const [amount,setAmount] = useState('')
  const [reason,setReason] = useState('')
  const [error,setError] = useState('')
  const [saving,setSaving] = useState(false)
  const rows = useMemo(()=>payments.filter(p=>{
    const hay=`${patientName(p.patientId)} ${treatmentName(p.treatmentId)} ${p.reference}`.toLowerCase()
    return hay.includes(query.toLowerCase()) && (method==='Tous'||p.method===method)
  }),[payments,query,method,patientName,treatmentName])
  const exportCsv=()=>{
    const csv=['Reference,Date,Patient,Soin,Type,Total,Paye,Reste,Plan,Moyen,Motif',...rows.map(p=>[p.reference,p.date,patientName(p.patientId),treatmentName(p.treatmentId),p.kind||'payment',p.accountTotal??p.total,p.paid,p.remaining,p.plan,p.method,p.reason||''].map(v=>`"${String(v).replaceAll('"','""')}"`).join(','))].join('\n')
    const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='historique-paiements.csv';a.click();URL.revokeObjectURL(url)
  }
  function openCorrection(row){setCorrection(row);setAmount(String(Math.abs(Number(row.paid||0))));setReason('');setError('')}
  function downloadReceipt(row){downloadPaymentReceiptPdf({receipt:row,patientName:patientName(row.patientId),treatmentName:treatmentName(row.treatmentId),clinic})}
  async function submitCorrection(e){
    e.preventDefault();setSaving(true);setError('')
    try{await correctPayment(correction.id,Number(amount),reason);setCorrection(null)}
    catch(err){setError(err.message||'La correction n’a pas pu être enregistrée.')}
    finally{setSaving(false)}
  }
  return <>
    <Topbar title="Historique des paiements" subtitle="Retrouvez, filtrez et exportez toutes les opérations."/>
    <section className="panel">
      <div className="toolbar"><div className="toolbar-left"><div className="search-box"><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Patient, soin, reçu…"/></div><select className="compact-select" value={method} onChange={e=>setMethod(e.target.value)}><option>Tous</option><option>Carte</option><option>Espèces</option><option>Virement</option><option>Chèque</option></select></div><button className="ghost-btn" onClick={exportCsv}><Download size={17}/> Export CSV</button></div>
      <div className="table-wrap"><table><thead><tr><th>Reçu</th><th>Date</th><th>Patient</th><th>Soin</th><th>Type</th><th>Total</th><th>Payé</th><th>Reste</th><th>Plan</th><th>Moyen</th>{(can('payments.receipt')||can('payments.correct'))&&<th>Action</th>}</tr></thead><tbody>{rows.map(p=><tr key={p.id}><td><strong>{p.reference}</strong></td><td>{p.date}</td><td>{patientName(p.patientId)}</td><td>{treatmentName(p.treatmentId)}</td><td><span className={`status ${p.kind==='refund'?'wait':'ok'}`}>{p.kind==='refund'?'Avoir':'Paiement'}</span></td><td>{money(p.accountTotal??p.total)}</td><td className={Number(p.paid)<0?'danger-text':''}>{money(p.paid)}</td><td>{money(p.remaining)}</td><td>{p.plan}</td><td>{p.method}</td>{(can('payments.receipt')||can('payments.correct'))&&<td><div className="table-actions">{can('payments.receipt')&&<button className="ghost-btn" onClick={()=>downloadReceipt(p)}><FileDown size={15}/> PDF</button>}{can('payments.correct')&&p.kind!=='refund'&&Number(p.paid)>0&&<button className="ghost-btn" onClick={()=>openCorrection(p)}><RotateCcw size={15}/> Corriger</button>}</div></td>}</tr>)}</tbody></table></div>
    </section>
    <Modal open={Boolean(correction)} onClose={()=>setCorrection(null)} title="Créer un avoir" subtitle="Le paiement d’origine reste immuable. Une écriture de correction liée sera ajoutée.">
      <form className="form-grid" onSubmit={submitCorrection}>
        <label>Montant (DH)<input required type="number" min="0.01" step="0.01" max={Math.abs(Number(correction?.paid||0))} value={amount} onChange={e=>setAmount(e.target.value)}/></label>
        <label className="full">Motif de correction<textarea required minLength="4" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Ex. erreur de saisie ou remboursement"/></label>
        {error&&<div className="form-error full" role="alert">{error}</div>}
        <div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setCorrection(null)}>Annuler</button><button className="primary-btn" disabled={saving}>{saving?'Enregistrement…':'Créer l’avoir'}</button></div>
      </form>
    </Modal>
  </>
}
