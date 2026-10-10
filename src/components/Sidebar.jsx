import React from 'react'
import { NavLink } from 'react-router-dom'
import { CalendarDays, CircleDollarSign, ClipboardList, CreditCard, FileHeart, LayoutDashboard, ReceiptText, Settings, Stethoscope, Users, WalletCards, BadgeCheck, Calculator, X, Megaphone } from 'lucide-react'
import { useData } from '../DataContext'
import { firebaseEnabled } from '../services/firebase'
import { supabaseEnabled } from '../services/supabase'

const nav = [
  ['/', 'Vue d’ensemble', LayoutDashboard],
  ['/acquisition', 'Acquisition', Megaphone],
  ['/patients', 'Patients', Users],
  ['/payments', 'Nouveau paiement', CreditCard],
  ['/payment-history', 'Historique paiements', ReceiptText],
  ['/receivables', 'Soldes à recevoir', WalletCards],
  ['/appointments', 'Rendez-vous', CalendarDays],
  ['/doctors', 'Praticiens', Stethoscope],
  ['/treatments', 'Soins & tarifs', ClipboardList],
  ['/clinical', 'Clinique', FileHeart],
  ['/approvals', 'Prix négociés', BadgeCheck],
  ['/collection-sessions', 'Sessions de caisse', Calculator],
  ['/reports', 'Rapports', CircleDollarSign],
  ['/settings', 'Paramètres', Settings]
]

export default function Sidebar({open=false,onClose=()=>{},onNavigate=()=>{}}){
  const { can, currentUser } = useData()
  const storageLabel = supabaseEnabled ? 'Supabase distant · connecté' : firebaseEnabled ? 'Firebase · connecté' : 'Stockage local · actif'
  const visible = new Set(nav.filter(([to]) => {
    if(['/clinical'].includes(to)) return can('clinical.view')
    if(['/approvals'].includes(to)) return can('priceRequests.create') || currentUser?.role === 'administrator'
    if(to==='/reports') return can('reports.finance') || currentUser?.role === 'administrator'
    if(['/receivables','/payment-history'].includes(to)) return currentUser?.role === 'administrator'
    return true
  }).map(([to])=>to))
  return (
    <aside className={`sidebar ${open?'is-open':''}`} aria-label="Navigation principale">
      <div className="logo-wrap">
        <div className="logo-mark"><span></span><span></span></div>
        <div><strong>DentalFlow</strong><small>Care. Track. Grow.</small></div>
        <button className="sidebar-close" type="button" aria-label="Fermer la navigation" onClick={onClose}><X size={20}/></button>
      </div>
      <nav>
        {nav.filter(([to])=>visible.has(to)).map(([to,label,Icon]) => <NavLink key={to} to={to} end={to==='/' } onClick={onNavigate} className={({isActive})=>isActive?'active':''}><Icon size={18}/><span>{label}</span></NavLink>)}
      </nav>
      <div className="sidebar-card">
        <div className="sidebar-orb">✦</div>
        <strong>Cabinet organisé</strong>
        <p>Paiements, rendez-vous et patients au même endroit.</p>
        <NavLink to="/payments" className="sidebar-cta">+ Nouveau paiement</NavLink>
      </div>
      <div className="sidebar-footer">{storageLabel}</div>
    </aside>
  )
}
