import React from 'react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money } from '../utils'

export default function Reports(){
  const { payments,treatments }=useData()
  const total=payments.reduce((s,p)=>s+Number(p.paid||0),0);const billed=payments.reduce((s,p)=>s+Number(p.total||0),0);const outstanding=billed-total
  const byTreatment=treatments.map(t=>({name:t.name,value:payments.filter(p=>p.treatmentId===t.id).reduce((s,p)=>s+Number(p.paid||0),0)})).sort((a,b)=>b.value-a.value)
  const max=Math.max(...byTreatment.map(x=>x.value),1)
  return <><Topbar title="Rapports" subtitle="Lecture simple des encaissements — sans comptabilité complexe."/>
    <div className="report-cards"><div><span>Total encaissé</span><strong>{money(total)}</strong></div><div><span>Valeur des traitements</span><strong>{money(billed)}</strong></div><div><span>Solde ouvert</span><strong>{money(outstanding)}</strong></div></div>
    <section className="panel"><div className="panel-head"><div><h3>Encaissements par soin</h3><p>Somme réellement encaissée par catégorie de prestation</p></div></div><div className="bar-list">{byTreatment.map(x=><div className="bar-row" key={x.name}><span>{x.name}</span><div className="bar-track"><div style={{width:`${(x.value/max)*100}%`}}></div></div><strong>{money(x.value)}</strong></div>)}</div></section></>
}
