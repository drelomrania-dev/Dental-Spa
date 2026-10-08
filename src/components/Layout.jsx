import React from 'react'
import { Outlet } from 'react-router-dom'
import Sidebar from './Sidebar'
import { useData } from '../DataContext'

export default function Layout(){
  const {dataError}=useData()
  return <div className="app-shell"><Sidebar/><main className="main-shell">{dataError&&<div className="data-error">Erreur Supabase : {dataError}</div>}<Outlet/></main></div>
}
