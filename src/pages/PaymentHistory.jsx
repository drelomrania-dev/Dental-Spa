import React, { useMemo, useRef, useState } from 'react'
import { Download, FileDown, RotateCcw, Search } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money } from '../utils'
import { downloadPaymentReceiptPdf } from '../services/receiptPdf'
import { authorizeReceiptExport, downloadPaymentHistoryCsv, loadPaymentHistoryExport } from '../services/reporting'
import { supabaseEnabled } from '../services/supabase'
import { firebaseEnabled } from '../services/firebase'

export default function PaymentHistory(){
  const { payments,patientName,treatmentName,clinic,correctPayment,can,add } = useData()
  const [query,setQuery] = useState('')
  const [method,setMethod] = useState('Tous')
  const [correction,setCorrection] = useState(null)
  const [amount,setAmount] = useState('')
  const [reason,setReason] = useState('')
  const [error,setError] = useState('')
  const [saving,setSaving] = useState(false)
  const [exporting,setExporting] = useState(false)
  const correctionKey=useRef(null)
  const rows = useMemo(()=>payments.filter(p=>{
    const hay=`${patientName(p.patientId)} ${treatmentName(p.treatmentId)} ${p.reference}`.toLowerCase()
    return hay.includes(query.toLowerCase()) && (method==='Tous'||p.method===method)
  }),[payments,query,method,patientName,treatmentName])
  async function exportCsv(){
    setExporting(true);setError('')
    try{
      const data=supabaseEnabled?await loadPaymentHistoryExport(query,method):rows.map(p=>({reference:p.reference,date:p.date,patient:p.document?.patientName||patientName(p.patientId),treatment:p.document?.treatmentName||treatmentName(p.treatmentId),type:p.kind||'payment',originalReference:p.document?.originalReceiptNumber||'',total:p.accountTotal??p.total,paid:p.paid,remaining:p.remaining,plan:p.plan,method:p.method,reason:p.reason||''}))
      if(!supabaseEnabled)await add('auditEvents',{action:'finance.payment_history.exported',at:new Date().toISOString(),rowCount:data.length,mode:'demo'})
      downloadPaymentHistoryCsv(data)
    }catch(err){setError(err.message||'Export impossible.')}
    finally{setExporting(false)}
  }
  function openCorrection(row){setCorrection(row);setAmount(String(Math.abs(Number(row.paid||0))));setReason('');setError('');correctionKey.current=null}
  async function downloadReceipt(row){setError('');try{const approved=supabaseEnabled?await authorizeReceiptExport(row.id):row;if(!supabaseEnabled)await add('auditEvents',{action:'finance.receipt.exported',at:new Date().toISOString(),reference:row.reference,format:'pdf',mode:'demo'});downloadPaymentReceiptPdf({receipt:approved,patientName:patientName(approved.patientId),treatmentName:treatmentName(approved.treatmentId),clinic})}catch(err){setError(err.message||'Export du reçu impossible.')}}
  async function submitCorrection(e){
    e.preventDefault();setSaving(true);setError('')
    try{correctionKey.current||=`correction:${correction.id}:${crypto.randomUUID()}`;await correctPayment(correction.id,Number(amount),reason,correctionKey.current);correctionKey.current=null;setCorrection(null)}
    catch(err){setError(err.message||'La correction n’a pas pu être enregistrée.')}
    finally{setSaving(false)}
  }
  return <>
    <Topbar title="Historique des paiements" subtitle="Reçus et documents de correction liés aux écritures immuables. Les factures fiscales sont distinctes."/>
    <section className="panel">
      <div className="toolbar"><div className="toolbar-left"><div className="search-box"><Search size={17}/><input aria-label="Rechercher un paiement" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Patient, soin, reçu…"/></div><select aria-label="Filtrer par moyen de paiement" className="compact-select" value={method} onChange={e=>setMethod(e.target.value)}><option>Tous</option><option>Carte</option><option>Espèces</option><option>Virement</option><option>Chèque</option></select></div>{can('reports.export')&&!firebaseEnabled&&<button className="ghost-btn" disabled={exporting} onClick={exportCsv}><Download size={17}/>{exporting?'Export…':'Export CSV'}</button>}</div>
      {error&&!correction&&<div className="data-error" role="alert">{error}</div>}
      <div className="table-wrap"><table><thead><tr><th>Document</th><th>Date</th><th>Patient</th><th>Soin</th><th>Type</th><th>Référence liée</th><th>Total</th><th>Payé</th><th>Reste</th><th>Plan</th><th>Moyen</th>{(can('payments.receipt')||can('payments.correct'))&&<th>Action</th>}</tr></thead><tbody>{rows.map(p=><tr key={p.id}><td><strong>{p.receiptNumber||p.reference}</strong></td><td>{p.date}</td><td>{p.document?.patientName||patientName(p.patientId)}</td><td>{p.document?.treatmentName||treatmentName(p.treatmentId)}</td><td><span className={`status ${p.kind==='refund'?'wait':'ok'}`}>{p.kind==='refund'?'Correction':'Reçu'}</span></td><td>{p.document?.originalReceiptNumber||'—'}</td><td>{money(p.accountTotal??p.total,p.document?.clinic?.currency||clinic.currency)}</td><td className={Number(p.paid)<0?'danger-text':''}>{money(p.paid,p.document?.clinic?.currency||clinic.currency)}</td><td>{money(p.remaining,p.document?.clinic?.currency||clinic.currency)}</td><td>{p.plan}</td><td>{p.method}</td>{(can('payments.receipt')||can('payments.correct'))&&<td><div className="table-actions">{can('payments.receipt')&&!firebaseEnabled&&<button className="ghost-btn" onClick={()=>downloadReceipt(p)}><FileDown size={15}/> PDF</button>}{can('payments.correct')&&p.kind!=='refund'&&Number(p.paid)>0&&<button className="ghost-btn" onClick={()=>openCorrection(p)}><RotateCcw size={15}/> Corriger</button>}</div></td>}</tr>)}</tbody></table></div>
    </section>
    <Modal open={Boolean(correction)} onClose={()=>setCorrection(null)} title="Créer un document de correction" subtitle="Le paiement d’origine reste immuable. Une écriture de correction liée sera ajoutée.">
      <form className="form-grid" onSubmit={submitCorrection}>
        <label>Montant ({correction?.document?.clinic?.currency||clinic.currency})<input required type="number" min="0.01" step="0.01" max={Math.abs(Number(correction?.paid||0))} value={amount} onChange={e=>setAmount(e.target.value)}/></label>
        <label className="full">Motif de correction<textarea required minLength="4" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Ex. erreur de saisie ou remboursement"/></label>
        {error&&<div className="form-error full" role="alert">{error}</div>}
        <div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setCorrection(null)}>Annuler</button><button className="primary-btn" disabled={saving}>{saving?'Enregistrement…':'Créer la correction'}</button></div>
      </form>
    </Modal>
  </>
}
