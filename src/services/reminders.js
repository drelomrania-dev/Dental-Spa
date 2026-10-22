import { supabase, supabaseEnabled } from './supabase'

// Provider boundary: this module only calls database RPCs or the local fake sender.
// A future server worker must revalidate consent/source and deliver outside this client.
const key='dentalflow:reminders:v1'
const kinds=['appointment','installment_before','installment_due']
const channels=['email','whatsapp']
const defaults={
  appointment:'Bonjour {first_name}, rappel de votre rendez-vous chez {clinic} le {date} à {time}.',
  installment_before:'Bonjour {first_name}, votre échéance chez {clinic} est prévue le {date}. Contactez le cabinet si nécessaire.',
  installment_due:'Bonjour {first_name}, votre échéance chez {clinic} est prévue aujourd’hui, le {date}.'
}
function initial(){return {rules:kinds.map((kind,i)=>({kind,enabled:true,leadAmount:[24,3,0][i]})),templates:kinds.flatMap(kind=>channels.map(channel=>({kind,channel,body:defaults[kind],approved:false,revision:1}))),consents:[],outbox:[],events:[]}}
function read(){try{return JSON.parse(localStorage.getItem(key))||initial()}catch{return initial()}}
function save(data){localStorage.setItem(key,JSON.stringify(data));return data}
function cancelPending(data,predicate){for(const row of data.outbox){if(['queued','retry'].includes(row.status)&&predicate(row)){row.status='cancelled';row.cancelledAt=new Date().toISOString();row.lastError='Préférence ou configuration modifiée';data.events.unshift({outboxId:row.id,attempt:row.attempts,outcome:'cancelled',detail:row.lastError,at:row.cancelledAt})}}}
function unwrap(result){if(result.error)throw result.error;return result.data}
function render(body,clinic,patient,date,time){return body.replaceAll('{clinic}',clinic.name).replaceAll('{first_name}',patient.firstName).replaceAll('{date}',date).replaceAll('{time}',time||'')}
function validateTemplate(body){
  if(body.trim().length<10||body.trim().length>500)throw new Error('Le modèle doit contenir entre 10 et 500 caractères.')
  const remaining=body.replace(/\{(?:clinic|first_name|date|time)\}/g,'')
  if(/[{}]/.test(remaining))throw new Error('Variable non autorisée. Utilisez {clinic}, {first_name}, {date} ou {time}.')
}
export async function loadReminderSnapshot(){return supabaseEnabled?unwrap(await supabase.rpc('reminder_snapshot')):read()}
export async function configureReminderRule(kind,enabled,leadAmount){
  if(supabaseEnabled)return unwrap(await supabase.rpc('configure_reminder_rule',{p_kind:kind,p_enabled:enabled,p_lead_amount:Number(leadAmount)}))
  const data=read();const row=data.rules.find(x=>x.kind===kind);if(!row)throw new Error('Règle introuvable.')
  if(row.enabled!==Boolean(enabled)||row.leadAmount!==Number(leadAmount))cancelPending(data,item=>item.kind===kind)
  row.enabled=Boolean(enabled);row.leadAmount=Number(leadAmount);save(data);return row
}
export async function saveReminderTemplate(kind,channel,body,approve){
  validateTemplate(body)
  if(supabaseEnabled)return unwrap(await supabase.rpc('save_reminder_template',{p_kind:kind,p_channel:channel,p_body:body,p_approve:approve}))
  const data=read();const row=data.templates.find(x=>x.kind===kind&&x.channel===channel);if(!row)throw new Error('Modèle introuvable.')
  cancelPending(data,item=>item.kind===kind&&item.channel===channel)
  Object.assign(row,{body:body.trim(),approved:Boolean(approve),revision:row.revision+1,approvedAt:approve?new Date().toISOString():null});save(data);return row
}
export async function recordReminderConsent(patientId,channel,granted,evidence,patient){
  if(evidence.trim().length<4)throw new Error('Indiquez la source ou le motif du consentement.')
  if(supabaseEnabled)return unwrap(await supabase.rpc('record_reminder_consent',{p_patient_app_id:patientId,p_channel:channel,p_granted:granted,p_evidence:evidence}))
  if(granted&&!(channel==='email'?patient?.email:patient?.phone))throw new Error('Coordonnée du patient manquante.')
  const data=read();data.consents=data.consents.filter(x=>!(x.patientId===patientId&&x.channel===channel));const row={patientId,channel,granted,evidence:evidence.trim(),recordedAt:new Date().toISOString()};data.consents.push(row)
  if(!granted)cancelPending(data,item=>item.patientId===patientId&&item.channel===channel)
  save(data);return row
}
function localSourceValid(row,context,data){
  const rule=data.rules.find(x=>x.kind===row.kind)
  const template=data.templates.find(x=>x.kind===row.kind&&x.channel===row.channel)
  const consent=data.consents.find(x=>x.patientId===row.patientId&&x.channel===row.channel)
  const patient=context.patients.find(x=>x.id===row.patientId)
  if(!rule?.enabled||!template?.approved||template.revision!==row.templateRevision||!consent?.granted||!patient)return false
  if((row.channel==='email'?patient.email:patient.phone)!==row.recipient)return false
  if(row.kind==='appointment'){
    const appointment=context.appointments.find(x=>x.id===row.sourceId)
    return Boolean(appointment&&['En attente','Confirmé'].includes(appointment.status)&&`${appointment.date}T${appointment.time}`===row.sourceVersion&&new Date(row.sourceVersion)>new Date())
  }
  const item=context.balances.flatMap(x=>x.installments||[]).find(x=>x.id===row.sourceId)
  return Boolean(item&&item.dueDate===row.sourceVersion&&item.status!=='paid'&&Number(item.remaining)>0)
}
export async function queueDueReminders(context){
  if(supabaseEnabled)return unwrap(await supabase.rpc('queue_due_reminders'))
  const data=read(),now=new Date();let queued=0,cancelled=0
  for(const row of data.outbox.filter(x=>['queued','retry'].includes(x.status))){if(!localSourceValid(row,context,data)){row.status='cancelled';row.cancelledAt=now.toISOString();cancelled++}}
  const sources=[]
  for(const a of context.appointments){
    if(!['En attente','Confirmé'].includes(a.status))continue
    const start=new Date(`${a.date}T${a.time}`),rule=data.rules.find(x=>x.kind==='appointment')
    if(rule?.enabled&&start>now&&new Date(start.getTime()-rule.leadAmount*3600000)<=now)sources.push({kind:'appointment',sourceId:a.id,sourceVersion:`${a.date}T${a.time}`,patientId:a.patientId,date:a.date,time:a.time,scheduledAt:new Date(start.getTime()-rule.leadAmount*3600000).toISOString()})
  }
  for(const account of context.balances)for(const item of account.installments||[]){
    if(item.status==='paid'||Number(item.remaining)<=0)continue
    for(const kind of ['installment_before','installment_due']){
      const rule=data.rules.find(x=>x.kind===kind);if(!rule?.enabled)continue
      const due=new Date(`${item.dueDate}T09:00`),scheduled=new Date(due.getTime()-rule.leadAmount*86400000)
      if(scheduled<=now&&item.dueDate>=now.toISOString().slice(0,10))sources.push({kind,sourceId:item.id,sourceVersion:item.dueDate,patientId:account.patientId,date:item.dueDate,time:'',scheduledAt:scheduled.toISOString()})
    }
  }
  for(const source of sources){
    const patient=context.patients.find(x=>x.id===source.patientId);if(!patient)continue
    for(const channel of channels){
      const consent=data.consents.find(x=>x.patientId===patient.id&&x.channel===channel)
      const template=data.templates.find(x=>x.kind===source.kind&&x.channel===channel)
      const recipient=channel==='email'?patient.email:patient.phone
      if(!consent?.granted||!template?.approved||!recipient)continue
      const existing=data.outbox.find(x=>x.kind===source.kind&&x.channel===channel&&x.sourceId===source.sourceId&&x.sourceVersion===source.sourceVersion)
      if(existing&&existing.status!=='cancelled')continue
      const content={...source,channel,recipient,body:render(template.body,context.clinic,patient,source.date,source.time),templateRevision:template.revision,status:'queued',attempts:0,queuedAt:now.toISOString(),cancelledAt:null,nextAttemptAt:null,lastError:null}
      if(existing)Object.assign(existing,content)
      else data.outbox.unshift({id:crypto.randomUUID(),...content})
      queued++
    }
  }
  save(data);return {queued,cancelled}
}
export async function fakeDispatchReminder(id,fail,context){
  if(supabaseEnabled)return unwrap(await supabase.rpc('fake_dispatch_reminder',{p_id:id,p_fail:Boolean(fail)}))
  const data=read(),row=data.outbox.find(x=>x.id===id);if(!row)throw new Error('Rappel introuvable.')
  if(!['queued','retry'].includes(row.status))throw new Error('Rappel non disponible.')
  if(row.nextAttemptAt&&new Date(row.nextAttemptAt)>new Date())throw new Error('Nouvelle tentative pas encore disponible.')
  if(!localSourceValid(row,context,data)){row.status='cancelled';row.cancelledAt=new Date().toISOString();save(data);return {id,status:'cancelled'}}
  row.attempts++;row.status=fail?'retry':'sent_fake';row.lastError=fail?'Échec simulé':null;row.nextAttemptAt=fail?new Date(Date.now()+5*60000).toISOString():null;row.deliveredAt=fail?null:new Date().toISOString()
  data.events.unshift({outboxId:id,attempt:row.attempts,outcome:fail?'fake_failed':'fake_sent',at:new Date().toISOString(),detail:fail?'Échec simulé':'Expéditeur local fictif; aucun réseau'})
  save(data);return {id,status:row.status,attempts:row.attempts}
}
