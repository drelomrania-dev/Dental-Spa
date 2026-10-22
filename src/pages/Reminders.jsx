import React, { useCallback, useEffect, useState } from 'react'
import Topbar from '../components/Topbar'
import { useData } from '../DataContext'
import { configureReminderRule, fakeDispatchReminder, loadReminderSnapshot, queueDueReminders, recordReminderConsent, saveReminderTemplate } from '../services/reminders'
import { supabaseEnabled } from '../services/supabase'

const labels={appointment:'Rendez-vous',installment_before:'Échéance à venir',installment_due:'Échéance du jour'}
const channelLabels={email:'Email',whatsapp:'WhatsApp'}
const statusLabels={queued:'En attente',retry:'À réessayer',sent_fake:'Envoyé (simulation)',cancelled:'Annulé'}
const blank={rules:[],templates:[],consents:[],outbox:[],events:[]}

export default function Reminders(){
  const {patients,appointments,balances,financeAccounts,clinic,can,patientName}=useData()
  const [snapshot,setSnapshot]=useState(blank)
  const [selectedPatient,setSelectedPatient]=useState('')
  const [channel,setChannel]=useState('email')
  const [granted,setGranted]=useState(true)
  const [evidence,setEvidence]=useState('')
  const [message,setMessage]=useState('')
  const [busy,setBusy]=useState(false)
  const [error,setError]=useState('')
  const context={patients,appointments,balances:!supabaseEnabled&&financeAccounts.length?financeAccounts:balances,clinic}
  const refresh=useCallback(async()=>setSnapshot(await loadReminderSnapshot()),[])
  useEffect(()=>{refresh().catch(e=>setError(e.message||'Rappels indisponibles.'))},[refresh])
  async function run(action,success){setBusy(true);setError('');setMessage('');try{await action();await refresh();setMessage(success)}catch(e){setError(e.message||'Opération impossible.')}finally{setBusy(false)}}
  async function saveConsent(e){e.preventDefault();const patient=patients.find(x=>x.id===selectedPatient);await run(()=>recordReminderConsent(selectedPatient,channel,granted,evidence,patient),'Préférence enregistrée avec sa preuve.');setEvidence('')}
  async function updateRule(row,patch){await run(()=>configureReminderRule(row.kind,patch.enabled??row.enabled,patch.leadAmount??row.leadAmount),'Règle enregistrée.')}
  async function updateTemplate(row,approve){await run(()=>saveReminderTemplate(row.kind,row.channel,row.body,approve),approve?'Modèle approuvé.':'Brouillon enregistré.')}
  async function queue(){let result;await run(async()=>{result=await queueDueReminders(context)},'File actualisée.');if(result)setMessage(`${result.queued} rappel(s) mis en file, ${result.cancelled} obsolète(s) annulé(s).`)}
  async function dispatch(row,fail){await run(()=>fakeDispatchReminder(row.id,fail,context),fail?'Échec simulé; nouvelle tentative planifiée.':'Simulation enregistrée. Aucun message réel envoyé.')}
  const selectedConsent=snapshot.consents.filter(x=>x.patientId===selectedPatient)
  return <>
    <Topbar title="Rappels" subtitle="Consentements, modèles approuvés et historique des simulations"/>
    <section className="panel"><div className="panel-head"><div><h3>File de rappels</h3><p>Le mode actuel est un expéditeur fictif. Aucun email ni WhatsApp réel n’est envoyé.</p></div><button className="primary-btn" type="button" disabled={busy} onClick={queue}>Préparer les rappels dus</button></div>
      {error&&<div className="form-error" role="alert">{error}</div>}{message&&<div className="soft-badge" role="status">{message}</div>}
      <div className="table-wrap"><table><thead><tr><th>Patient</th><th>Rappel</th><th>Canal</th><th>Destinataire</th><th>Statut</th><th>Tentatives</th><th>Action</th></tr></thead><tbody>{snapshot.outbox.map(row=><tr key={row.id}><td>{patientName(row.patientId)}</td><td>{labels[row.kind]}<small className="reminder-muted">{new Date(row.scheduledAt).toLocaleString('fr-FR',{timeZone:clinic.timezone||'Africa/Casablanca'})}</small><details><summary>Voir le message</summary><p>{row.body}</p></details></td><td>{channelLabels[row.channel]}</td><td>{row.recipient}</td><td>{statusLabels[row.status]||row.status}{row.lastError&&<small className="reminder-muted">{row.lastError}</small>}</td><td>{row.attempts}</td><td>{['queued','retry'].includes(row.status)&&<div className="reminder-actions"><button type="button" className="ghost-btn" disabled={busy||Boolean(row.nextAttemptAt&&new Date(row.nextAttemptAt)>new Date())} onClick={()=>dispatch(row,false)}>Simuler l’envoi</button><button type="button" className="ghost-btn" disabled={busy||Boolean(row.nextAttemptAt&&new Date(row.nextAttemptAt)>new Date())} onClick={()=>dispatch(row,true)}>Simuler un échec</button></div>}</td></tr>)}</tbody></table></div>{!snapshot.outbox.length&&<div className="empty-state compact">Aucun rappel en file. Les modèles doivent être approuvés et le patient doit consentir au canal.</div>}
    </section>
    <section className="panel"><div className="panel-head"><div><h3>Préférences du patient</h3><p>Chaque canal nécessite un accord explicite documenté. Un retrait annule les rappels encore en attente.</p></div></div>
      <form className="form-grid" onSubmit={saveConsent}><label>Patient<select required value={selectedPatient} onChange={e=>setSelectedPatient(e.target.value)}><option value="">Choisir</option>{patients.map(p=><option key={p.id} value={p.id}>{p.firstName} {p.lastName}</option>)}</select></label><label>Canal<select value={channel} onChange={e=>setChannel(e.target.value)}><option value="email">Email</option><option value="whatsapp">WhatsApp</option></select></label><label>Préférence<select value={granted?'yes':'no'} onChange={e=>setGranted(e.target.value==='yes')}><option value="yes">Consentement accordé</option><option value="no">Consentement retiré</option></select></label><label className="full">Preuve ou motif<input required minLength="4" maxLength="300" value={evidence} onChange={e=>setEvidence(e.target.value)} placeholder="Ex. accord confirmé à l’accueil le 20/10/2026"/></label><div className="form-actions full"><button className="primary-btn" disabled={busy}>Enregistrer la préférence</button></div></form>
      {selectedPatient&&<div className="reminder-consents">{['email','whatsapp'].map(item=>{const row=selectedConsent.find(x=>x.channel===item);return <span key={item} className="soft-badge">{channelLabels[item]} : {row?row.granted?'Accordé':'Retiré':'Non renseigné'}</span>})}</div>}
    </section>
    {can('settings.manage')&&<><section className="panel"><div className="panel-head"><div><h3>Délais et activation</h3><p>Rendez-vous : heures avant le début. Échéances : jours avant la date, à 09:00 dans le fuseau du cabinet.</p></div></div><div className="reminder-rule-grid">{snapshot.rules.map(row=><RuleEditor key={row.kind} row={row} busy={busy} onSave={updateRule}/>)}</div></section>
      <section className="panel"><div className="panel-head"><div><h3>Modèles de message</h3><p>Un modèle modifié redevient un nouveau brouillon. Variables autorisées : {'{clinic}'}, {'{first_name}'}, {'{date}'}, {'{time}'}. Les notes cliniques ne sont jamais injectées.</p></div></div><div className="reminder-template-grid">{snapshot.templates.map(row=><TemplateEditor key={`${row.kind}:${row.channel}:${row.revision}`} row={row} busy={busy} onSave={updateTemplate}/>)}</div></section></>}
    <section className="panel"><div className="panel-head"><div><h3>Historique de livraison</h3><p>Journal des tentatives fictives et annulations, séparé des interactions CRM manuelles.</p></div></div>{snapshot.events.length?snapshot.events.map((event,index)=><div className="resource-row" key={`${event.outboxId}:${event.at}:${index}`}><div><strong>{event.outcome==='fake_sent'?'Simulation réussie':event.outcome==='fake_failed'?'Échec simulé':'Annulation'} · tentative {event.attempt}</strong><span>{new Date(event.at).toLocaleString('fr-FR')} · {event.detail}</span></div></div>):<div className="empty-state compact">Aucune tentative.</div>}</section>
  </>
}

function RuleEditor({row,busy,onSave}){
  const [enabled,setEnabled]=useState(row.enabled);const [lead,setLead]=useState(row.leadAmount)
  return <form className="reminder-editor" onSubmit={e=>{e.preventDefault();onSave(row,{enabled,leadAmount:Number(lead)})}}><strong>{labels[row.kind]}</strong><label className="switch-row"><input type="checkbox" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/> Actif</label><label>{row.kind==='appointment'?'Heures avant':'Jours avant'}<input type="number" min={row.kind==='appointment'?1:0} max={row.kind==='appointment'?168:30} value={lead} onChange={e=>setLead(e.target.value)}/></label><button className="ghost-btn" disabled={busy}>Enregistrer</button></form>
}
function TemplateEditor({row,busy,onSave}){
  const [body,setBody]=useState(row.body)
  return <div className="reminder-editor"><strong>{labels[row.kind]} · {channelLabels[row.channel]}</strong><span className="soft-badge">{row.approved?'Approuvé':'Brouillon'} · v{row.revision}</span><textarea aria-label={`Modèle ${labels[row.kind]} ${channelLabels[row.channel]}`} minLength="10" maxLength="500" value={body} onChange={e=>setBody(e.target.value)}/><div className="reminder-actions"><button className="ghost-btn" type="button" disabled={busy} onClick={()=>onSave({...row,body},false)}>Enregistrer brouillon</button><button className="primary-btn" type="button" disabled={busy} onClick={()=>onSave({...row,body},true)}>Approuver</button></div></div>
}
