import React, { useState } from 'react'
import { Mail, Phone, Plus, Stethoscope } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'

export default function Doctors(){
  const { doctors,appointments,add }=useData();const [open,setOpen]=useState(false)
  const [form,setForm]=useState({name:'',specialty:'Dentisterie générale',phone:'',email:'',availability:'Lun–Ven',active:true,color:'#7357f6'})
  async function submit(e){e.preventDefault();await add('doctors',form);setOpen(false)}
  return <>
    <Topbar title="Praticiens" subtitle="Équipe médicale, spécialités et charge de rendez-vous."/>
    <div className="toolbar page-toolbar"><div></div><button className="primary-btn" onClick={()=>setOpen(true)}><Plus size={18}/> Ajouter un praticien</button></div>
    <div className="doctor-grid">{doctors.map(d=><article className="doctor-card" key={d.id}><div className="doctor-top"><div className="doctor-avatar" style={{background:d.color||'#7357f6'}}><Stethoscope size={24}/></div><span className="status ok">Actif</span></div><h3>{d.name}</h3><p className="specialty">{d.specialty}</p><div className="doctor-info"><span><Phone size={15}/>{d.phone||'—'}</span><span><Mail size={15}/>{d.email||'—'}</span></div><div className="doctor-bottom"><div><small>Disponibilité</small><strong>{d.availability}</strong></div><div><small>Rendez-vous</small><strong>{appointments.filter(a=>a.doctorId===d.id).length}</strong></div></div></article>)}</div>
    <Modal open={open} onClose={()=>setOpen(false)} title="Ajouter un praticien" subtitle="Informations opérationnelles uniquement."><form onSubmit={submit} className="form-grid"><label>Nom<input required value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Spécialité<input value={form.specialty} onChange={e=>setForm({...form,specialty:e.target.value})}/></label><label>Téléphone<input value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label><label>Email<input value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label><label>Disponibilité<input value={form.availability} onChange={e=>setForm({...form,availability:e.target.value})}/></label><div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn">Ajouter</button></div></form></Modal>
  </>
}
