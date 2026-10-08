import React from 'react'
import { AlertCircle, WalletCards } from 'lucide-react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money } from '../utils'

export default function Receivables(){
  const { balances,patientName,treatmentName } = useData()
  const rows=balances.filter(p=>Number(p.remaining)>0).sort((a,b)=>b.remaining-a.remaining)
  const total=rows.reduce((s,p)=>s+Number(p.remaining||0),0)
  return <>
    <Topbar title="Soldes à recevoir" subtitle="Suivez les plans de paiement encore ouverts."/>
    <div className="hero-balance"><div className="hero-icon"><WalletCards size={28}/></div><div><span>Total restant à encaisser</span><strong>{money(total)}</strong><p>{rows.length} dossier(s) avec un solde ouvert</p></div></div>
    <section className="panel"><div className="panel-head"><div><h3>Dossiers ouverts</h3><p>Priorisés par montant restant</p></div><span className="soft-badge"><AlertCircle size={14}/> À suivre</span></div>
    <div className="table-wrap"><table><thead><tr><th>Patient</th><th>Soin</th><th>Total</th><th>Déjà payé</th><th>Reste</th><th>Plan</th><th>Dernier paiement</th></tr></thead><tbody>{rows.map(p=><tr key={`${p.patientId}:${p.treatmentId}`}><td><strong>{patientName(p.patientId)}</strong></td><td>{treatmentName(p.treatmentId)}</td><td>{money(p.total)}</td><td>{money(p.paid)}</td><td><strong className="danger-text">{money(p.remaining)}</strong></td><td>{p.plan}</td><td>{p.lastDate}</td></tr>)}</tbody></table></div></section>
  </>
}
