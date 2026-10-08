import React, { useEffect, useMemo, useState } from 'react'
import { ArrowRight, Filter, LayoutGrid, List, Megaphone, Plus, Search, Sparkles, UserCheck, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import Modal from '../components/Modal'
import Topbar from '../components/Topbar'
import { createLead, listLeads } from '../services/acquisition'

const STAGES=['Nouveau','Contacte','Qualifie','Invitation envoyee','Rendez-vous','Converti','Perdu']
const SOURCES=['Direct','Instagram','Facebook','Google','WhatsApp','Recommandation','Site web','Autre']

export default function Acquisition(){
  const [leads,setLeads]=useState([]);const [loading,setLoading]=useState(true);const [error,setError]=useState('');const [query,setQuery]=useState('');const [stage,setStage]=useState('Tous');const [view,setView]=useState('pipeline');const [open,setOpen]=useState(false);const [saving,setSaving]=useState(false)
  const [form,setForm]=useState({firstName:'',lastName:'',phone:'',email:'',source:'Direct',priority:'Normale',concern:'',status:'Nouveau'})
  useEffect(()=>{let live=true;listLeads().then(rows=>{if(live)setLeads(rows)}).catch(err=>{if(live)setError(err.message||'Impossible de charger les prospects.')}).finally(()=>{if(live)setLoading(false)});return()=>{live=false}},[])
  const rows=useMemo(()=>leads.filter(lead=>(stage==='Tous'||lead.status===stage)&&`${lead.firstName} ${lead.lastName} ${lead.phone} ${lead.email} ${lead.concern}`.toLowerCase().includes(query.toLowerCase())),[leads,query,stage])
  const kpis=useMemo(()=>({total:leads.length,new:leads.filter(x=>x.status==='Nouveau').length,qualified:leads.filter(x=>['Qualifie','Invitation envoyee','Rendez-vous','Converti'].includes(x.status)).length,converted:leads.filter(x=>x.status==='Converti').length}),[leads])
  async function submit(e){e.preventDefault();setSaving(true);setError('');try{const lead=await createLead(form);setLeads(current=>[lead,...current]);setOpen(false);setForm({firstName:'',lastName:'',phone:'',email:'',source:'Direct',priority:'Normale',concern:'',status:'Nouveau'})}catch(err){setError(err.message||'Création impossible.')}finally{setSaving(false)}}

  return <>
    <Topbar title="Acquisition" subtitle="Transformez chaque demande en patient grâce à un suivi clair et rapide."/>
    <div className="acquisition-kpis">
      <div className="panel"><span><UsersRound size={17}/> Prospects</span><strong>{kpis.total}</strong><small>Toutes les sources</small></div>
      <div className="panel"><span><Sparkles size={17}/> Nouveaux</span><strong>{kpis.new}</strong><small>À contacter</small></div>
      <div className="panel"><span><Megaphone size={17}/> Qualifiés</span><strong>{kpis.qualified}</strong><small>{kpis.total?Math.round(kpis.qualified/kpis.total*100):0}% du pipeline</small></div>
      <div className="panel"><span><UserCheck size={17}/> Convertis</span><strong>{kpis.converted}</strong><small>Devenus patients</small></div>
    </div>
    <section className="panel acquisition-panel">
      <div className="toolbar acquisition-toolbar"><div className="toolbar-left"><div className="search-box"><Search size={17}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Nom, téléphone, besoin…"/></div><label className="filter-select"><Filter size={15}/><select value={stage} onChange={e=>setStage(e.target.value)}><option>Tous</option>{STAGES.map(item=><option key={item}>{item}</option>)}</select></label></div><div className="acquisition-actions"><div className="view-switch"><button className={view==='pipeline'?'active':''} aria-label="Vue pipeline" onClick={()=>setView('pipeline')}><LayoutGrid size={16}/></button><button className={view==='list'?'active':''} aria-label="Vue liste" onClick={()=>setView('list')}><List size={16}/></button></div><button className="primary-btn" onClick={()=>setOpen(true)}><Plus size={18}/> Nouveau prospect</button></div></div>
      {error&&<div className="data-error">{error}</div>}
      {loading?<div className="empty-state">Chargement du pipeline…</div>:view==='pipeline'?<div className="lead-pipeline">{STAGES.filter(item=>item!=='Perdu').map(item=>{const stageRows=rows.filter(lead=>lead.status===item);return <section className="lead-column" key={item}><header><span className={`lead-stage-dot stage-${STAGES.indexOf(item)}`}/><strong>{item}</strong><b>{stageRows.length}</b></header><div>{stageRows.map(lead=><Link to={`/acquisition/${lead.id}`} className="lead-card" key={lead.id}><div className="lead-card-head"><strong>{lead.firstName} {lead.lastName}</strong><span className={`lead-priority priority-${lead.priority.toLowerCase()}`}>{lead.priority}</span></div><p>{lead.concern||'Besoin à préciser'}</p><footer><span>{lead.source}</span><ArrowRight size={14}/></footer></Link>)}{!stageRows.length&&<div className="lead-column-empty">Aucun prospect</div>}</div></section>})}</div>:<div className="table-wrap"><table><thead><tr><th>Prospect</th><th>Contact</th><th>Besoin</th><th>Source</th><th>Priorité</th><th>Étape</th></tr></thead><tbody>{rows.map(lead=><tr key={lead.id}><td><Link className="patient-link" to={`/acquisition/${lead.id}`}><strong>{lead.firstName} {lead.lastName}</strong><ArrowRight size={13}/></Link></td><td>{lead.phone||lead.email||'—'}</td><td>{lead.concern||'—'}</td><td>{lead.source}</td><td><span className={`lead-priority priority-${lead.priority.toLowerCase()}`}>{lead.priority}</span></td><td><span className="soft-badge">{lead.status}</span></td></tr>)}{!rows.length&&<tr><td colSpan="6"><div className="empty-state">Aucun prospect ne correspond à ces filtres.</div></td></tr>}</tbody></table></div>}
    </section>
    <Modal open={open} onClose={()=>setOpen(false)} title="Nouveau prospect" subtitle="Capturez la demande en moins d’une minute.">
      <form className="form-grid" onSubmit={submit}><label>Prénom<input required value={form.firstName} onChange={e=>setForm({...form,firstName:e.target.value})}/></label><label>Nom<input value={form.lastName} onChange={e=>setForm({...form,lastName:e.target.value})}/></label><label>Téléphone<input type="tel" value={form.phone} onChange={e=>setForm({...form,phone:e.target.value})}/></label><label>Email<input type="email" value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label><label>Source<select value={form.source} onChange={e=>setForm({...form,source:e.target.value})}>{SOURCES.map(item=><option key={item}>{item}</option>)}</select></label><label>Priorité<select value={form.priority} onChange={e=>setForm({...form,priority:e.target.value})}><option>Basse</option><option>Normale</option><option>Haute</option><option>Urgente</option></select></label><label className="full">Besoin / motif<textarea rows="3" value={form.concern} onChange={e=>setForm({...form,concern:e.target.value})} placeholder="Ex. facettes, douleur, implant, contrôle…"/></label><div className="form-actions full"><button type="button" className="ghost-btn" onClick={()=>setOpen(false)}>Annuler</button><button className="primary-btn" disabled={saving}>{saving?'Création…':'Créer le prospect'}</button></div></form>
    </Modal>
  </>
}
