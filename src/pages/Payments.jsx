import React, { useEffect, useMemo, useRef, useState } from 'react'
import { CheckCircle2, FileDown, Printer, ReceiptText } from 'lucide-react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money } from '../utils'
import { downloadPaymentReceiptPdf } from '../services/receiptPdf'
import { supabaseEnabled } from '../services/supabase'
import { firebaseEnabled } from '../services/firebase'
import { authorizeReceiptExport } from '../services/reporting'

export default function Payments(){
  const { patients,treatments,doctors,payments,priceRequests,collectionSessions,currentUser,clinic,add,patientName,treatmentName,balanceFor,financeBalance,can } = useData()
  const clinicToday=Object.fromEntries(new Intl.DateTimeFormat('en-US',{timeZone:clinic.timezone||'Africa/Casablanca',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()).map(part=>[part.type,part.value]))
  const today=`${clinicToday.year}-${clinicToday.month}-${clinicToday.day}`
  const [form,setForm] = useState({patientId:'',treatmentId:'',doctorId:'',plan:'Comptant',paid:'',method:'Carte',firstDueDate:today,installmentCount:6})
  const [receipt,setReceipt] = useState(null)
  const [remoteLedger,setRemoteLedger] = useState(null)
  const [balanceLoading,setBalanceLoading] = useState(false)
  const [error,setError] = useState('')
  const [saving,setSaving] = useState(false)
  const [receiptExporting,setReceiptExporting] = useState(false)
  const submitting=useRef(false)
  const pendingKey=useRef(null)
  const treatment = treatments.find(t=>t.id===form.treatmentId)
  const localLedger = form.patientId && form.treatmentId ? balanceFor(form.patientId, form.treatmentId) : {total:0,paid:0,remaining:Number(treatment?.price||0)}
  const ledger=remoteLedger||localLedger
  const displayCurrency=remoteLedger?.currency||clinic.currency
  const planLocked=Boolean(remoteLedger?.id)
  const effectivePlan=planLocked?remoteLedger.plan:form.plan
  const approvedPrice = supabaseEnabled?undefined:priceRequests.filter(r=>r.patientId===form.patientId&&r.treatmentId===form.treatmentId&&r.status==='Approved').sort((a,b)=>String(b.decidedAt).localeCompare(String(a.decidedAt)))[0]?.proposedPrice
  const total = supabaseEnabled&&!remoteLedger?0:ledger.total || Number(approvedPrice ?? treatment?.price ?? 0)
  const amountDue = ledger.total ? ledger.remaining : total
  const activeSession = collectionSessions.find(s=>s.status==='Open'&&s.openedBy===(currentUser?.id||'u2'))
  const needsSession=currentUser?.role==='assistant'||form.method==='Espèces'
  const suggested = useMemo(()=>{
    if(amountDue<=0)return 0
    if(effectivePlan==='2 fois') return Math.min(total/2,amountDue)
    if(effectivePlan==='3 fois') return Math.min(total/3,amountDue)
    if(effectivePlan==='Mensuel') return Math.min(total/Number(form.installmentCount||6),amountDue)
    return amountDue
  },[total,amountDue,effectivePlan,form.installmentCount])
  useEffect(()=>{setForm(f=>({...f,paid:suggested?suggested.toFixed(2):''}))},[suggested])
  useEffect(()=>{
    let active=true
    setRemoteLedger(null);setBalanceLoading(Boolean(supabaseEnabled&&form.patientId&&form.treatmentId))
    if(!form.patientId||!form.treatmentId)return()=>{active=false}
    financeBalance(form.patientId,form.treatmentId).then(value=>{if(active){setRemoteLedger(value);setBalanceLoading(false)}}).catch(err=>{if(active){setBalanceLoading(false);setError(err.message||'Impossible de charger le solde.')}})
    return()=>{active=false}
  },[form.patientId,form.treatmentId,payments.length,financeBalance])
  const paid = Number(form.paid||0)
  const remaining = Math.max(0,amountDue-paid)
  async function exportReceipt(action){if(!receipt)return;setReceiptExporting(true);setError('');try{const approved=supabaseEnabled?await authorizeReceiptExport(receipt.id,action):receipt;if(!supabaseEnabled)await add('auditEvents',{action:'finance.receipt.exported',at:new Date().toISOString(),reference:receipt.reference,format:action,mode:'demo'});if(action==='pdf')downloadPaymentReceiptPdf({receipt:approved,patientName:patientName(approved.patientId),treatmentName:treatmentName(approved.treatmentId),clinic});else window.print()}catch(err){setError(err.message||'Export du reçu impossible.')}finally{setReceiptExporting(false)}}

  async function submit(e){
    e.preventDefault()
    if(submitting.current)return
    if(!form.patientId || !form.treatmentId || (supabaseEnabled&&!remoteLedger) || paid<=0 || paid>amountDue) return
    if(needsSession&&!activeSession){setError('Ouvrez d’abord votre session de caisse.');return}
    submitting.current=true;setSaving(true);setError('')
    try{
      const row = await add('payments',{
        patientId:form.patientId,treatmentId:form.treatmentId,doctorId:form.doctorId,date:today,total:ledger.total||total,paid,remaining:Math.max(0,amountDue-paid),
        plan:effectivePlan,method:form.method,status:remaining>0?'Partiel':'Payé',reference:`REC-${String(Date.now()).slice(-6)}`,idempotencyKey:pendingKey.current||= `payment:${crypto.randomUUID()}`,collectorUserId:currentUser?.id||'u1',sessionId:activeSession?.id||'',firstDueDate:form.firstDueDate,installmentCount:form.installmentCount
      })
      setReceipt(row)
      pendingKey.current=null
    }catch(err){setError(err.message||'Le paiement n’a pas pu être enregistré.')}
    finally{submitting.current=false;setSaving(false)}
  }

  return <>
    <Topbar title="Nouveau paiement" subtitle="Patient → soin → plan → encaissement → reçu."/>
    <div className="payment-layout">
      <form className="panel payment-form" onSubmit={submit}>
        <div className="section-kicker">1. Patient & soin</div>
        <div className="form-grid">
          <label className="full">Patient<select required value={form.patientId} onChange={e=>setForm({...form,patientId:e.target.value})}><option value="">Choisir un patient</option>{patients.map(p=><option value={p.id} key={p.id}>{p.firstName} {p.lastName}</option>)}</select></label>
          <label>Soin<select required value={form.treatmentId} onChange={e=>setForm({...form,treatmentId:e.target.value})}><option value="">Choisir un soin</option>{treatments.filter(t=>t.active!==false).map(t=><option key={t.id} value={t.id}>{t.name} — {money(t.price,clinic.currency)}</option>)}</select></label>
          <label>Praticien<select value={form.doctorId} onChange={e=>setForm({...form,doctorId:e.target.value})}><option value="">Non assigné</option>{doctors.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
        </div>
        <div className="section-kicker">2. Plan de paiement</div>
        <div className="segmented">{['Comptant','2 fois','3 fois','Mensuel'].map(x=><button type="button" key={x} disabled={planLocked} className={effectivePlan===x?'active':''} onClick={()=>setForm({...form,plan:x})}>{x}</button>)}</div>
        {planLocked?<p className="receipt-note">Plan et prix figés à l’ouverture du compte. Toute correction crée une écriture liée.</p>:<div className="form-grid"><label>Première échéance<input type="date" min={today} value={form.firstDueDate} onChange={e=>setForm({...form,firstDueDate:e.target.value})}/></label>{form.plan==='Mensuel'&&<label>Nombre de mensualités<input type="number" min="2" max="60" value={form.installmentCount} onChange={e=>setForm({...form,installmentCount:e.target.value})}/></label>}</div>}
        <div className="summary-cards"><div><span>Total traitement{approvedPrice!==undefined?' négocié':''}</span><strong>{balanceLoading?'Chargement…':money(total,displayCurrency)}</strong></div><div><span>Payé aujourd’hui</span><strong>{money(paid,displayCurrency)}</strong></div><div className="highlight"><span>Reste à payer</span><strong>{balanceLoading?'Chargement…':money(remaining,displayCurrency)}</strong></div></div>
        <div className="section-kicker">3. Encaissement</div>
        <div className="form-grid">
          <label>Montant reçu ({displayCurrency})<input type="number" min="0" max={amountDue||undefined} step="0.01" value={form.paid} onChange={e=>setForm({...form,paid:e.target.value})}/></label>
          <label>Moyen<select value={form.method} onChange={e=>setForm({...form,method:e.target.value})}><option>Carte</option><option>Espèces</option><option>Virement</option><option>Chèque</option></select></label>
        </div>
        {needsSession&&!activeSession&&<div className="form-error">Aucune session de caisse ouverte.</div>}
        {form.patientId&&form.treatmentId&&amountDue<=0&&<div className="success-strip">Ce soin est entièrement réglé.</div>}
        {error&&<div className="form-error" role="alert">{error}</div>}
        <button className="primary-btn large" disabled={!total||balanceLoading||(supabaseEnabled&&!remoteLedger)||amountDue<=0||paid<=0||paid>amountDue||saving||(needsSession&&!activeSession)}><CheckCircle2 size={19}/> {saving?'Enregistrement…':'Valider le paiement'}</button>
      </form>

      <aside className="panel receipt-panel" id="receipt-print">
        <div className="receipt-logo"><ReceiptText size={22}/><div><strong>{receipt?.document?.clinic?.name||clinic.name||'Dental Spa'}</strong><span>Reçu de paiement</span></div></div>
        <div className="receipt-rule"></div>
        <div className="receipt-line"><span>Date</span><strong>{receipt?.date||today}</strong></div>
        {receipt&&<div className="receipt-line"><span>Numéro</span><strong>{receipt.document?.number||receipt.reference}</strong></div>}
        <div className="receipt-line"><span>Patient</span><strong>{receipt?.document?.patientName||(receipt?patientName(receipt.patientId):(form.patientId?patientName(form.patientId):'—'))}</strong></div>
        <div className="receipt-line"><span>Soin</span><strong>{receipt?.document?.treatmentName||(receipt?treatmentName(receipt.treatmentId):(treatment?.name||'—'))}</strong></div>
        <div className="receipt-line"><span>Plan</span><strong>{receipt?.plan||effectivePlan}</strong></div>
        <div className="receipt-line"><span>Moyen</span><strong>{receipt?.method||form.method}</strong></div>
        <div className="receipt-total-box"><div><span>Total</span><strong>{money(receipt?.document?.accountTotal??receipt?.accountTotal??receipt?.total??total,receipt?.document?.clinic?.currency||clinic.currency)}</strong></div><div><span>Payé</span><strong>{money(receipt?.document?.amount??receipt?.paid??paid,receipt?.document?.clinic?.currency||clinic.currency)}</strong></div><div><span>Reste</span><strong>{money(receipt?.document?.remaining??receipt?.remaining??remaining,receipt?.document?.clinic?.currency||clinic.currency)}</strong></div></div>
        {receipt&&<p className="receipt-note">{receipt.document?.clinic?.address||''} · {receipt.document?.clinic?.phone||''}</p>}
        <p className="receipt-note">Ce reçu confirme le paiement enregistré. Il ne remplace pas une facture fiscale.</p>
        {receipt&&can('payments.receipt')&&!firebaseEnabled&&<button type="button" className="ghost-btn full-btn no-print" disabled={receiptExporting} onClick={()=>exportReceipt('print')}><Printer size={17}/> Imprimer le ticket 80 mm</button>}
        {receipt&&can('payments.receipt')&&!firebaseEnabled&&<button type="button" className="primary-btn full-btn no-print" disabled={receiptExporting} onClick={()=>exportReceipt('pdf')}><FileDown size={17}/> Télécharger le reçu PDF</button>}
        {receipt && <div className="success-strip no-print">✓ Paiement enregistré · {receipt.reference}</div>}
      </aside>
    </div>
  </>
}
