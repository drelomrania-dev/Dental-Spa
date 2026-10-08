import React, { useState } from 'react'
import { Plus } from 'lucide-react'
import Topbar from '../components/Topbar'
import Modal from '../components/Modal'
import { useData } from '../DataContext'
import { money } from '../utils'

export default function Treatments(){
  const { treatments,add,update }=useData();const [open,setOpen]=useState(false)
  const [form,setForm]=useState({name:'',category:'Autre',price:'',duration:30,active:true})
  async function submit(e){e.preventDefault();await add('treatments',{...form,price:Number(form.price),duration:Number(form.duration)});setOpen(false)}
  return <>
    <Topbar title="Soins & tarifs" subtitle="Catalogue des prestations utilisées dans le module de paiement."/>
    <section className="panel"><div className="toolbar"><div><span className="soft-badge">{treatments.length} prestations</span></div><button className="primary-btn" onClick={()=>setOpen(true)}><Plus size={18}/> Nouveau soin</button></div>
    <div className="treatment-grid">{treatments.map(t=><div className="treatment-card" key={t.id}><div><span className="category-tag">{t.category}</span><h3>{t.name}</h3><p>{t.duration} min</p></div><div className="treatment-price">{money(t.price)}</div><label className="switch-row"><input type="checkbox" checked={t.active!==false} onChange={e=>update('treatments',t.id,{active:e.target.checked})}/><span>{t.active!==false?'Actif':'Masqué'}</span></label></div>)}</div></section>
    <Modal open={open} onClose={()=>setOpen(false)} title="Ajouter un soin" subtitle="Le tarif sera automatiquement proposé lors du paiement."><form onSubmit={submit} className="form-grid"><label>Nom du soin<input required value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Catégorie<input value={form.category} onChange={e=>setForm({...form,category:e.target.value})}/></label><label>Prix (DH)<input required type="number" min="0" value={form.price} onChange={e=>setForm({...form,price:e.target.value})}/></label><label>Durée (min)<input type="number" min="10" value={form.duration} onChange={e=>setForm({...form,duration:e.target.value})}/></label><div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn">Enregistrer</button></div></form></Modal>
  </>
}
