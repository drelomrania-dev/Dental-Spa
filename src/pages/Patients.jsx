import React, { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowUpRight, Plus, Search, UserRound } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'

export default function Patients(){
  const { patients, payments, add } = useData()
  const [query,setQuery] = useState('')
  const [open,setOpen] = useState(false)
  const [form,setForm] = useState({firstName:'',lastName:'',phone:'',email:''})
  const rows = useMemo(()=>patients.filter(p=>`${p.firstName} ${p.lastName} ${p.phone} ${p.email}`.toLowerCase().includes(query.toLowerCase())),[patients,query])

  async function submit(e){
    e.preventDefault()
    await add('patients',{...form,createdAt:new Date().toISOString().slice(0,10),status:'Actif'})
    setForm({firstName:'',lastName:'',phone:'',email:''});setOpen(false)
  }

  return <>
    <Topbar title="Patients" subtitle="Dossiers simples, coordonnées et activité de paiement."/>
    <section className="panel">
      <div className="toolbar"><div className="search-box"><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Rechercher un patient…"/></div><button className="primary-btn" onClick={()=>setOpen(true)}><Plus size={18}/> Ajouter un patient</button></div>
      <div className="table-wrap"><table><thead><tr><th>Patient</th><th>Téléphone</th><th>Email</th><th>Depuis</th><th>Paiements</th><th>Statut</th></tr></thead><tbody>
        {rows.map(p=><tr key={p.id}><td><div className="person-cell"><div className="mini-avatar"><UserRound size={16}/></div><Link className="patient-link" to={`/patients/${p.id}`}><strong>{p.firstName} {p.lastName}</strong><ArrowUpRight size={13}/></Link></div></td><td>{p.phone||'—'}</td><td>{p.email||'—'}</td><td>{p.createdAt}</td><td>{payments.filter(x=>x.patientId===p.id).length}</td><td><span className="status ok">{p.status}</span></td></tr>)}
        {!rows.length&&<tr><td colSpan="6"><div className="empty-state">Aucun patient ne correspond à cette recherche.</div></td></tr>}
      </tbody></table></div>
    </section>
    <Modal open={open} onClose={()=>setOpen(false)} title="Nouveau patient" subtitle="Ajoutez uniquement les informations utiles à l’accueil.">
      <form onSubmit={submit} className="form-grid">
        <label>Prénom<input required value={form.firstName} onChange={e=>setForm({...form,firstName:e.target.value})}/></label>
        <label>Nom<input required value={form.lastName} onChange={e=>setForm({...form,lastName:e.target.value})}/></label>
        <label>Téléphone<input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label>
        <label>Email<input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label>
        <div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn">Créer le patient</button></div>
      </form>
    </Modal>
  </>
}
