import React, { useEffect, useMemo, useRef, useState } from 'react'
import { CheckCircle2, Printer, ReceiptText } from 'lucide-react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

export default function Payments(){
  const { patients,treatments,doctors,payments,priceRequests,collectionSessions,currentUser,add,patientName,treatmentName,balanceFor,financeBalance } = useData()
  const [form,setForm] = useState({patientId:'',treatmentId:'',doctorId:'',plan:'Comptant',paid:'',method:'Carte'})
  const [receipt,setReceipt] = useState(null)
  const [remoteLedger,setRemoteLedger] = useState(null)
  const [error,setError] = useState('')
  const [saving,setSaving] = useState(false)
  const submitting=useRef(false)
  const treatment = treatments.find(t=>t.id===form.treatmentId)
  const localLedger = form.patientId && form.treatmentId ? balanceFor(form.patientId, form.treatmentId) : {total:0,paid:0,remaining:Number(treatment?.price||0)}
  const ledger=remoteLedger||localLedger
  const approvedPrice = priceRequests.filter(r=>r.patientId===form.patientId&&r.treatmentId===form.treatmentId&&r.status==='Approved').sort((a,b)=>String(b.decidedAt).localeCompare(String(a.decidedAt)))[0]?.proposedPrice
  const total = ledger.total || Number(approvedPrice ?? treatment?.price ?? 0)
  const amountDue = ledger.total ? ledger.remaining : total
  const activeSession = collectionSessions.find(s=>s.status==='Open'&&s.openedBy===(currentUser?.id||'u2'))
  const suggested = useMemo(()=>{
    if(amountDue<=0)return 0
    if(form.plan==='2 fois') return Math.min(total/2,amountDue)
    if(form.plan==='3 fois') return Math.min(total/3,amountDue)
    if(form.plan==='Mensuel') return 0
    return amountDue
  },[total,amountDue,form.plan])
  useEffect(()=>{setForm(f=>({...f,paid:suggested?suggested.toFixed(2):''}))},[suggested])
  useEffect(()=>{
    let active=true
    setRemoteLedger(null)
    if(!form.patientId||!form.treatmentId)return()=>{active=false}
    financeBalance(form.patientId,form.treatmentId).then(value=>{if(active)setRemoteLedger(value)}).catch(err=>{if(active)setError(err.message||'Impossible de charger le solde.')})
    return()=>{active=false}
  },[form.patientId,form.treatmentId,payments.length,financeBalance])
  const paid = Number(form.paid||0)
  const remaining = Math.max(0,amountDue-paid)

  async function submit(e){
    e.preventDefault()
    if(submitting.current)return
    if(!form.patientId || !form.treatmentId || paid<=0 || paid>amountDue) return
    if(currentUser?.role==='assistant'&&!activeSession){setError('Ouvrez d’abord votre session de caisse.');return}
    submitting.current=true;setSaving(true);setError('')
    try{
      const row = await add('payments',{
        patientId:form.patientId,treatmentId:form.treatmentId,doctorId:form.doctorId,date:todayISO(),total:ledger.total||total,paid,remaining:Math.max(0,amountDue-paid),
        plan:form.plan,method:form.method,status:remaining>0?'Partiel':'Payé',reference:`REC-${String(Date.now()).slice(-6)}`,idempotencyKey:`payment:${crypto.randomUUID()}`,collectorUserId:currentUser?.id||'u1',sessionId:activeSession?.id||''
      })
      setReceipt(row)
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
          <label>Soin<select required value={form.treatmentId} onChange={e=>setForm({...form,treatmentId:e.target.value})}><option value="">Choisir un soin</option>{treatments.filter(t=>t.active!==false).map(t=><option key={t.id} value={t.id}>{t.name} — {money(t.price)}</option>)}</select></label>
          <label>Praticien<select value={form.doctorId} onChange={e=>setForm({...form,doctorId:e.target.value})}><option value="">Non assigné</option>{doctors.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
        </div>
        <div className="section-kicker">2. Plan de paiement</div>
        <div className="segmented">{['Comptant','2 fois','3 fois','Mensuel'].map(x=><button type="button" key={x} className={form.plan===x?'active':''} onClick={()=>setForm({...form,plan:x})}>{x}</button>)}</div>
        <div className="summary-cards"><div><span>Total traitement{approvedPrice!==undefined?' négocié':''}</span><strong>{money(total)}</strong></div><div><span>Payé aujourd’hui</span><strong>{money(paid)}</strong></div><div className="highlight"><span>Reste à payer</span><strong>{money(remaining)}</strong></div></div>
        <div className="section-kicker">3. Encaissement</div>
        <div className="form-grid">
          <label>Montant reçu (DH)<input type="number" min="0" max={amountDue||undefined} step="0.01" value={form.paid} onChange={e=>setForm({...form,paid:e.target.value})}/></label>
          <label>Moyen<select value={form.method} onChange={e=>setForm({...form,method:e.target.value})}><option>Carte</option><option>Espèces</option><option>Virement</option><option>Chèque</option></select></label>
        </div>
        {currentUser?.role==='assistant'&&!activeSession&&<div className="form-error">Aucune session de caisse ouverte.</div>}
        {form.patientId&&form.treatmentId&&amountDue<=0&&<div className="success-strip">Ce soin est entièrement réglé.</div>}
        {error&&<div className="form-error" role="alert">{error}</div>}
        <button className="primary-btn large" disabled={!total||amountDue<=0||paid<=0||paid>amountDue||saving||(currentUser?.role==='assistant'&&!activeSession)}><CheckCircle2 size={19}/> {saving?'Enregistrement…':'Valider le paiement'}</button>
      </form>

      <aside className="panel receipt-panel" id="receipt-print">
        <div className="receipt-logo"><ReceiptText size={22}/><div><strong>DentalFlow</strong><span>Reçu de paiement</span></div></div>
        <div className="receipt-rule"></div>
        <div className="receipt-line"><span>Date</span><strong>{receipt?.date||todayISO()}</strong></div>
        <div className="receipt-line"><span>Patient</span><strong>{receipt?patientName(receipt.patientId):(form.patientId?patientName(form.patientId):'—')}</strong></div>
        <div className="receipt-line"><span>Soin</span><strong>{receipt?treatmentName(receipt.treatmentId):(treatment?.name||'—')}</strong></div>
        <div className="receipt-line"><span>Plan</span><strong>{receipt?.plan||form.plan}</strong></div>
        <div className="receipt-line"><span>Moyen</span><strong>{receipt?.method||form.method}</strong></div>
        <div className="receipt-total-box"><div><span>Total</span><strong>{money(receipt?.accountTotal??receipt?.total??total)}</strong></div><div><span>Payé</span><strong>{money(receipt?.paid??paid)}</strong></div><div><span>Reste</span><strong>{money(receipt?.remaining??remaining)}</strong></div></div>
        <p className="receipt-note">Ce reçu confirme le paiement enregistré. Il ne remplace pas une facture fiscale.</p>
        <button type="button" className="ghost-btn full-btn no-print" onClick={()=>window.print()}><Printer size={17}/> Imprimer le ticket</button>
        {receipt && <div className="success-strip no-print">✓ Paiement enregistré · {receipt.reference}</div>}
      </aside>
    </div>
  </>
}
