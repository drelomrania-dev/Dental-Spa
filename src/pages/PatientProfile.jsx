import React, { useMemo } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, CalendarDays, CreditCard, Mail, Phone, UserRound, WalletCards } from 'lucide-react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { money, todayISO } from '../utils'

export default function PatientProfile(){
  const { patientId } = useParams()
  const { patients, appointments, payments, balances, loading, doctorName, treatmentName } = useData()
  const patient = patients.find(p => p.id === patientId)
  const patientAppointments = useMemo(() => appointments
    .filter(a => a.patientId === patientId)
    .sort((a,b) => `${b.date} ${b.time}`.localeCompare(`${a.date} ${a.time}`)), [appointments, patientId])
  const patientPayments = useMemo(() => payments
    .filter(p => p.patientId === patientId)
    .sort((a,b) => `${b.date} ${b.reference}`.localeCompare(`${a.date} ${a.reference}`)), [payments, patientId])

  if (loading) return <Topbar title="Chargement du profil…" subtitle="Récupération des informations du patient."/>

  if (!patient) return <>
    <Topbar title="Patient introuvable" subtitle="Ce dossier n’est pas disponible dans la base actuelle."/>
    <Link className="ghost-btn profile-back" to="/patients"><ArrowLeft size={16}/> Retour aux patients</Link>
  </>

  const fullName = `${patient.firstName} ${patient.lastName}`
  const upcoming = patientAppointments.filter(a => a.date >= todayISO())
  const totalPaid = patientPayments.reduce((sum,p) => sum + Number(p.paid || 0), 0)
  const totalRemaining = balances.filter(b=>b.patientId===patientId).reduce((sum,p) => sum + Number(p.remaining || 0), 0)

  return <>
    <Topbar title={fullName} subtitle="Profil patient et historique des interactions au cabinet."/>
    <div className="profile-toolbar">
      <Link className="ghost-btn" to="/patients"><ArrowLeft size={15}/> Tous les patients</Link>
      <div><Link className="ghost-btn" to="/appointments"><CalendarDays size={15}/> Nouveau rendez-vous</Link><Link className="primary-btn" to="/payments"><CreditCard size={15}/> Nouveau paiement</Link></div>
    </div>
    <section className="profile-hero panel">
      <div className="profile-identity"><div className="profile-avatar"><UserRound size={25}/></div><div><span className="soft-badge">{patient.status || 'Patient'}</span><h2>{fullName}</h2><p>Patient depuis le {patient.createdAt || '—'}</p></div></div>
      <div className="profile-contact">
        <div><Phone size={16}/><span>{patient.phone || 'Téléphone non renseigné'}</span></div>
        <div><Mail size={16}/><span>{patient.email || 'Email non renseigné'}</span></div>
      </div>
    </section>
    <div className="profile-stats">
      <div className="panel"><span><CalendarDays size={15}/> Rendez-vous à venir</span><strong>{upcoming.length}</strong></div>
      <div className="panel"><span><CreditCard size={15}/> Total payé</span><strong>{money(totalPaid)}</strong></div>
      <div className="panel"><span><WalletCards size={15}/> Solde restant</span><strong>{money(totalRemaining)}</strong></div>
    </div>
    <div className="profile-columns">
      <section className="panel">
        <div className="panel-head"><div><h3>Rendez-vous</h3><p>Visites passées et planifiées</p></div><Link to="/appointments">Voir le planning</Link></div>
        {patientAppointments.length ? <div className="profile-list">{patientAppointments.map(a=><div className="profile-list-row" key={a.id}>
          <div className="profile-date"><strong>{a.date}</strong><span>{a.time}</span></div>
          <div><strong>{a.reason || 'Consultation'}</strong><span>{doctorName(a.doctorId)} · {a.duration} min</span></div>
          <span className={`status ${a.status === 'Confirmé' ? 'ok' : a.status === 'Annulé' ? 'bad' : 'wait'}`}>{a.status}</span>
        </div>)}</div> : <div className="empty-state">Aucun rendez-vous enregistré.</div>}
      </section>
      <section className="panel">
        <div className="panel-head"><div><h3>Paiements</h3><p>Historique et soldes</p></div><Link to="/payment-history">Historique complet</Link></div>
        {patientPayments.length ? <div className="profile-list">{patientPayments.map(p=><div className="profile-list-row" key={p.id}>
          <div className="profile-date"><strong>{p.date}</strong><span>{p.reference}</span></div>
          <div><strong>{treatmentName(p.treatmentId)}</strong><span>{p.method} · payé {money(p.paid)}</span></div>
          <span className={`status ${Number(p.remaining) > 0 ? 'wait' : 'ok'}`}>{Number(p.remaining) > 0 ? `Reste ${money(p.remaining)}` : 'Payé'}</span>
        </div>)}</div> : <div className="empty-state">Aucun paiement enregistré.</div>}
      </section>
    </div>
  </>
}
