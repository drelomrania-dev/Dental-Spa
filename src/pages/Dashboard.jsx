import React from 'react'
import { CalendarCheck2, CalendarPlus, CreditCard, Plus, UserRoundCheck, WalletCards } from 'lucide-react'
import { Link } from 'react-router-dom'
import Topbar from '../components/Topbar'
import StatCard from '../components/StatCard'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

const methods = ['Carte','Espèces','Virement','Chèque']

function lastSevenDays(payments, today){
  return Array.from({length:7}, (_,index) => {
    const date = new Date(`${today}T12:00:00`)
    date.setDate(date.getDate() - (6-index))
    const key = `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`
    const total = payments.filter(p=>p.date===key).reduce((sum,p)=>sum+Number(p.paid||0),0)
    return { key, total, label:date.toLocaleDateString('fr-FR',{weekday:'short'}).replace('.','') }
  })
}

export default function Dashboard(){
  const { patients, payments, appointments, balances, patientName, doctorName } = useData()
  const today = todayISO()
  const todaysPayments = payments.filter(p => p.date === today)
  const collected = todaysPayments.reduce((sum,p)=>sum+Number(p.paid||0),0)
  const outstanding = balances.reduce((sum,p)=>sum+Number(p.remaining||0),0)
  const todaysAppointments = appointments.filter(a => a.date === today).sort((a,b)=>a.time.localeCompare(b.time))
  const methodTotals = todaysPayments.reduce((totals,p)=>{
    totals[p.method] = (totals[p.method] || 0) + Number(p.paid || 0)
    return totals
  }, {})
  const methodSum = methods.reduce((sum,method)=>sum+(methodTotals[method]||0),0)
  const shares = methods.map(method => methodSum ? (methodTotals[method]||0)/methodSum*100 : 0)
  const weekly = lastSevenDays(payments,today)
  const peak = Math.max(...weekly.map(day=>day.total),1)
  const points = weekly.map((day,index)=>({
    ...day,
    x:24 + index * 85.3,
    y:122 - (day.total/peak)*91
  }))
  const line = points.map((point,index)=>`${index ? 'L' : 'M'} ${point.x} ${point.y}`).join(' ')
  const area = `${line} L ${points[points.length-1].x} 132 L ${points[0].x} 132 Z`
  const weekTotal = weekly.reduce((sum,day)=>sum+day.total,0)
  const recentPayments = [...payments].sort((a,b)=>`${b.date} ${b.reference}`.localeCompare(`${a.date} ${a.reference}`)).slice(0,6)
  const dateLabel = new Date(`${today}T12:00:00`).toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long',year:'numeric'})

  return <>
    <Topbar title="Bonjour 👋" subtitle="Voici l’activité de votre cabinet aujourd’hui."/>
    <div className="dashboard-toolbar">
      <span>{dateLabel}</span>
      <div><Link className="ghost-btn" to="/appointments"><CalendarPlus size={15}/> Planifier un rendez-vous</Link><Link className="primary-btn" to="/payments"><Plus size={16}/> Nouveau paiement</Link></div>
    </div>
    <div className="stat-grid">
      <StatCard icon={CreditCard} label="Encaissements du jour" value={money(collected)} foot={`${todaysPayments.length} paiement(s)`} tone="violet"/>
      <StatCard icon={WalletCards} label="Reste à recevoir" value={money(outstanding)} foot="Tous plans de paiement" tone="mint"/>
      <StatCard icon={CalendarCheck2} label="Rendez-vous aujourd’hui" value={todaysAppointments.length} foot={`${todaysAppointments.filter(a=>a.status==='Confirmé').length} confirmés`} tone="orange"/>
      <StatCard icon={UserRoundCheck} label="Patients actifs" value={patients.length} foot="Base patients" tone="blue"/>
    </div>

    <div className="dash-grid dashboard-main-grid">
      <section className="panel trend-panel">
        <div className="panel-head"><div><h3>Encaissements de la semaine</h3><p>Montants reçus au cours des 7 derniers jours</p></div><span className="soft-badge">7 jours</span></div>
        <div className="trend-total"><strong>{money(weekTotal)}</strong><span>Total encaissé</span></div>
        <div className="trend-chart">
          <div className="trend-y-labels"><span>{money(peak)}</span><span>{money(peak/2)}</span><span>0 DH</span></div>
          <svg viewBox="0 0 560 145" role="img" aria-label="Graphique des encaissements journaliers sur les sept derniers jours" preserveAspectRatio="none">
            <defs><linearGradient id="trend-fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="#7959f6" stopOpacity=".22"/><stop offset="100%" stopColor="#7959f6" stopOpacity=".01"/></linearGradient></defs>
            <path className="trend-gridline" d="M20 31 H550 M20 76 H550 M20 132 H550"/>
            <path d={area} fill="url(#trend-fill)"/>
            <path d={line} className="trend-line"/>
            {points.map(point=><circle key={point.key} cx={point.x} cy={point.y} r="3.5" className="trend-point"><title>{point.key}: {money(point.total)}</title></circle>)}
          </svg>
        </div>
        <div className="trend-x-labels">{points.map(point=><span key={point.key}>{point.label}</span>)}</div>
      </section>

      <section className="panel">
        <div className="panel-head"><div><h3>Encaissements par moyen</h3><p>Répartition des paiements d’aujourd’hui</p></div><span className="soft-badge">Aujourd’hui</span></div>
        <div className="donut-layout">
          <div className="donut" style={{'--a':`${shares[0]}%`,'--b':`${shares[0]+shares[1]}%`,'--c':`${shares[0]+shares[1]+shares[2]}%`}}>
            <div><strong>{money(collected)}</strong><span>Total</span></div>
          </div>
          <div className="legend-list">
            {methods.map((method,index)=><div key={method}><span className={`legend-dot l${index}`}></span><b>{method}</b><em>{money(methodTotals[method]||0)}</em></div>)}
          </div>
        </div>
      </section>
    </div>

    <div className="dashboard-bottom-grid">
      <section className="panel">
        <div className="panel-head"><div><h3>Agenda du jour</h3><p>{todaysAppointments.length} rendez-vous planifié(s)</p></div><Link to="/appointments">Voir le planning</Link></div>
        <div className="agenda-list">
          {todaysAppointments.length ? todaysAppointments.slice(0,5).map(a=><div className="agenda-row" key={a.id}>
            <div className="time-chip">{a.time}</div>
            <div className="agenda-main"><strong>{patientName(a.patientId)}</strong><span>{a.reason} · {doctorName(a.doctorId)}</span></div>
            <span className={`status ${a.status==='Confirmé'?'ok':'wait'}`}>{a.status}</span>
          </div>) : <div className="dashboard-empty"><CalendarCheck2 size={20}/><span>Aucun rendez-vous prévu aujourd’hui.</span><Link to="/appointments">Ajouter au planning</Link></div>}
        </div>
      </section>

      <section className="panel">
        <div className="panel-head"><div><h3>Paiements récents</h3><p>Dernières opérations enregistrées</p></div><Link to="/payment-history">Historique complet</Link></div>
        {recentPayments.length ? <div className="table-wrap"><table><thead><tr><th>Patient</th><th>Date</th><th>Moyen</th><th>Payé</th><th>Reste</th></tr></thead>
        <tbody>{recentPayments.map(p=><tr key={p.id}><td><strong>{patientName(p.patientId)}</strong><small>{p.reference}</small></td><td>{p.date}</td><td>{p.method}</td><td>{money(p.paid)}</td><td><span className={`status ${p.remaining>0?'wait':'ok'}`}>{p.remaining>0?money(p.remaining):'Payé'}</span></td></tr>)}</tbody></table></div> : <div className="dashboard-empty"><CreditCard size={20}/><span>Aucun paiement enregistré.</span><Link to="/payments">Créer un paiement</Link></div>}
      </section>
    </div>
  </>
}
