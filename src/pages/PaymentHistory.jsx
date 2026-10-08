import React, { useMemo, useState } from 'react'
import { Download, Search } from 'lucide-react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money } from '../utils'

export default function PaymentHistory(){
  const { payments,patientName,treatmentName } = useData()
  const [query,setQuery] = useState('')
  const [method,setMethod] = useState('Tous')
  const rows = useMemo(()=>payments.filter(p=>{
    const hay=`${patientName(p.patientId)} ${treatmentName(p.treatmentId)} ${p.reference}`.toLowerCase()
    return hay.includes(query.toLowerCase()) && (method==='Tous'||p.method===method)
  }),[payments,query,method,patientName,treatmentName])
  const exportCsv=()=>{
    const csv=['Reference,Date,Patient,Soin,Total,Paye,Reste,Plan,Moyen',...rows.map(p=>[p.reference,p.date,patientName(p.patientId),treatmentName(p.treatmentId),p.total,p.paid,p.remaining,p.plan,p.method].map(v=>`"${String(v).replaceAll('"','""')}"`).join(','))].join('\n')
    const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='historique-paiements.csv';a.click();URL.revokeObjectURL(url)
  }
  return <>
    <Topbar title="Historique des paiements" subtitle="Retrouvez, filtrez et exportez toutes les opérations."/>
    <section className="panel">
      <div className="toolbar"><div className="toolbar-left"><div className="search-box"><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Patient, soin, reçu…"/></div><select className="compact-select" value={method} onChange={e=>setMethod(e.target.value)}><option>Tous</option><option>Carte</option><option>Espèces</option><option>Virement</option><option>Chèque</option></select></div><button className="ghost-btn" onClick={exportCsv}><Download size={17}/> Export CSV</button></div>
      <div className="table-wrap"><table><thead><tr><th>Reçu</th><th>Date</th><th>Patient</th><th>Soin</th><th>Total</th><th>Payé</th><th>Reste</th><th>Plan</th><th>Moyen</th></tr></thead><tbody>{rows.map(p=><tr key={p.id}><td><strong>{p.reference}</strong></td><td>{p.date}</td><td>{patientName(p.patientId)}</td><td>{treatmentName(p.treatmentId)}</td><td>{money(p.total)}</td><td>{money(p.paid)}</td><td>{money(p.remaining)}</td><td>{p.plan}</td><td>{p.method}</td></tr>)}</tbody></table></div>
    </section>
  </>
}
