import React from 'react'
import { Bell, LogOut, Search } from 'lucide-react'
import { useAuth } from '../AuthContext'

export default function Topbar({ title, subtitle }){
  const { session, signOut, supabaseEnabled } = useAuth()
  return (
    <div className="topbar">
      <div>
        <h1>{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      <div className="topbar-actions">
        <div className="global-search"><Search size={17}/><input placeholder="Rechercher patient, paiement…"/></div>
        <button className="icon-btn has-dot topbar-notifications" aria-label="Notifications"><Bell size={19}/></button>
        <div className="avatar" title={session?.user?.email || 'Dental Spa'}>DO</div>
        {supabaseEnabled&&<button className="icon-btn" aria-label="Se déconnecter" title="Se déconnecter" onClick={signOut}><LogOut size={17}/></button>}
      </div>
    </div>
  )
}
