import React, { useEffect, useState } from 'react'
import { Outlet } from 'react-router-dom'
import { Menu } from 'lucide-react'
import Sidebar from './Sidebar'
import { useData } from '../DataContext'

export default function Layout(){
  const {dataError}=useData()
  const [navigationOpen,setNavigationOpen]=useState(false)
  useEffect(()=>{
    document.body.classList.toggle('mobile-nav-open',navigationOpen)
    return ()=>document.body.classList.remove('mobile-nav-open')
  },[navigationOpen])
  return <div className="app-shell">
    <button className={`sidebar-overlay ${navigationOpen?'is-open':''}`} aria-label="Fermer la navigation" onClick={()=>setNavigationOpen(false)}/>
    <Sidebar open={navigationOpen} onClose={()=>setNavigationOpen(false)} onNavigate={()=>setNavigationOpen(false)}/>
    <div className="mobile-shellbar"><button className="mobile-menu-btn" aria-label="Ouvrir la navigation" aria-expanded={navigationOpen} onClick={()=>setNavigationOpen(true)}><Menu size={21}/></button><div className="mobile-brand"><span className="mobile-brand-mark">✦</span><strong>DentalFlow</strong></div><span className="mobile-online" aria-label="Supabase connecté"/></div>
    <main className="main-shell">{dataError&&<div className="data-error">Erreur Supabase : {dataError}</div>}<Outlet/></main>
  </div>
}
