import { remoteClinicId, supabase, supabaseEnabled } from './supabase'

const LOCAL_PREFIX = 'dentalflow:acquisition:'

function localRows(name){ return JSON.parse(localStorage.getItem(LOCAL_PREFIX+name)||'[]') }
function saveLocal(name,rows){ localStorage.setItem(LOCAL_PREFIX+name,JSON.stringify(rows)) }

function leadFromRow(row){
  return {
    id:row.id,firstName:row.first_name,lastName:row.last_name||'',phone:row.phone||'',email:row.email||'',
    source:row.source,status:row.status,priority:row.priority,ownerId:row.owner_id||'',concern:row.concern||'',notes:row.notes||'',
    convertedPatientId:row.converted_patient_id||'',lastContactAt:row.last_contact_at||'',nextFollowUpAt:row.next_follow_up_at||'',createdAt:row.created_at,updatedAt:row.updated_at
  }
}

function leadToRow(data,clinicId){
  return {
    clinic_id:clinicId,first_name:data.firstName.trim(),last_name:(data.lastName||'').trim(),phone:(data.phone||'').trim()||null,
    email:(data.email||'').trim()||null,source:data.source||'Direct',status:data.status||'Nouveau',priority:data.priority||'Normale',
    concern:(data.concern||'').trim()||null,notes:(data.notes||'').trim()||null,next_follow_up_at:data.nextFollowUpAt||null,owner_id:data.ownerId||null,updated_at:new Date().toISOString()
  }
}

export async function listLeads(){
  if(!supabaseEnabled) return localRows('leads').sort((a,b)=>String(b.createdAt).localeCompare(String(a.createdAt)))
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('leads').select('*').eq('clinic_id',clinicId).order('created_at',{ascending:false})
  if(error)throw error
  return data.map(leadFromRow)
}

export async function listLeadOwners(){
  if(!supabaseEnabled)return []
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('staff_profiles').select('id,display_name,role').eq('clinic_id',clinicId).eq('active',true).order('display_name')
  if(error)throw error
  return data.map(row=>({id:row.id,name:row.display_name,role:row.role}))
}

export async function listOpenLeadTasks(){
  if(!supabaseEnabled){const leads=new Map(localRows('leads').map(row=>[row.id,row]));return localRows('tasks').filter(row=>row.status==='A faire').map(row=>({...row,lead:leads.get(row.leadId)})).sort((a,b)=>String(a.dueAt).localeCompare(String(b.dueAt)))}
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('follow_up_tasks').select('id,lead_id,title,due_at,status,leads(first_name,last_name,status)').eq('clinic_id',clinicId).eq('status','A faire').order('due_at',{ascending:true}).limit(100)
  if(error)throw error
  return data.map(row=>({id:row.id,leadId:row.lead_id,title:row.title,dueAt:row.due_at,status:row.status,lead:row.leads?{firstName:row.leads.first_name,lastName:row.leads.last_name,status:row.leads.status}:null}))
}

export async function createLead(payload){
  if(!supabaseEnabled){
    const now=new Date().toISOString();const existing=localRows('leads').find(row=>(payload.phone&&row.phone?.replace(/\D/g,'')===payload.phone.replace(/\D/g,''))||(payload.email&&row.email?.toLowerCase()===payload.email.toLowerCase()));if(existing)return {...existing,deduplicated:true}
    const row={id:crypto.randomUUID(),...payload,status:payload.status||'Nouveau',priority:payload.priority||'Normale',createdAt:now,updatedAt:now}
    const rows=localRows('leads');rows.unshift(row);saveLocal('leads',rows);return row
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.rpc('create_lead_checked',{p_lead:leadToRow(payload,clinicId)})
  if(error)throw error
  return {...leadFromRow(data.lead),deduplicated:data.deduplicated}
}

export async function updateLead(id,patch){
  if(!supabaseEnabled){
    let changed=null;const previous=localRows('leads');const old=previous.find(row=>row.id===id);const rows=previous.map(row=>row.id===id?(changed={...row,...patch,updatedAt:new Date().toISOString()}):row);saveLocal('leads',rows)
    if(old?.status!==patch.status&&patch.status){const events=localRows('events');events.unshift({id:crypto.randomUUID(),leadId:id,type:'lead.stage_changed',metadata:{from:old?.status,to:patch.status},createdAt:new Date().toISOString()});saveLocal('events',events)}
    return changed
  }
  const clinicId=await remoteClinicId();const row={}
  const map={firstName:'first_name',lastName:'last_name',phone:'phone',email:'email',source:'source',status:'status',priority:'priority',concern:'concern',notes:'notes',nextFollowUpAt:'next_follow_up_at',ownerId:'owner_id'}
  Object.entries(map).forEach(([key,column])=>{if(Object.prototype.hasOwnProperty.call(patch,key))row[column]=patch[key]||null})
  row.updated_at=new Date().toISOString()
  const {data,error}=await supabase.from('leads').update(row).eq('clinic_id',clinicId).eq('id',id).select('*').single()
  if(error)throw error
  return leadFromRow(data)
}

export async function getLeadBundle(id){
  if(!supabaseEnabled){
    const lead=localRows('leads').find(row=>row.id===id)||null
    const originalQuotes=localRows('quotes');const expired=[]
    const quotes=originalQuotes.map(row=>{if(row.leadId===id&&row.status==='Envoye'&&row.validUntil&&row.validUntil<new Date().toISOString().slice(0,10)){expired.push({id:crypto.randomUUID(),leadId:id,quoteId:row.id,previousStatus:'Envoye',status:'Expire',createdAt:new Date().toISOString()});return {...row,status:'Expire'}}return row})
    if(expired.length){saveLocal('quotes',quotes);saveLocal('quoteEvents',[...expired,...localRows('quoteEvents')])}
    return {lead:lead?{...lead,convertedPatientAppId:lead.convertedPatientId||''}:null,interactions:localRows('interactions').filter(row=>row.leadId===id),tasks:localRows('tasks').filter(row=>row.leadId===id).sort((a,b)=>String(a.dueAt).localeCompare(String(b.dueAt))),invitations:localRows('invitations').filter(row=>row.leadId===id),media:localRows('media').filter(row=>row.leadId===id),quotes:quotes.filter(row=>row.leadId===id),events:localRows('events').filter(row=>row.leadId===id),quoteEvents:localRows('quoteEvents').filter(row=>row.leadId===id)}
  }
  const clinicId=await remoteClinicId()
  const {error:expiryError}=await supabase.rpc('expire_lead_quotes',{p_lead_id:id})
  if(expiryError)throw expiryError
  const [leadResult,interactionsResult,tasksResult,invitationsResult,mediaResult,quotesResult,eventsResult,quoteEventsResult,consentsResult]=await Promise.all([
    supabase.from('leads').select('*').eq('clinic_id',clinicId).eq('id',id).single(),
    supabase.from('lead_interactions').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('follow_up_tasks').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('due_at',{ascending:true}),
    supabase.from('consultation_invitations').select('id,channel,status,booking_slug,expires_at,first_opened_at,completed_at,created_at').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_media').select('id,session_id,storage_path,mime_type,size_bytes,quality_status,created_at,photo_view_definitions(label,code)').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_quotes').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_events').select('id,event_type,metadata,actor_id,created_at').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_quote_events').select('id,quote_id,previous_status,status,created_at').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('consent_records').select('id,session_id,accepted,recorded_at').eq('clinic_id',clinicId).eq('lead_id',id).eq('consent_type','guided_photos').order('recorded_at',{ascending:false}).order('id',{ascending:false})
  ])
  const failure=[leadResult,interactionsResult,tasksResult,invitationsResult,mediaResult,quotesResult,eventsResult,quoteEventsResult,consentsResult].find(result=>result.error)
  if(failure)throw failure.error
  let convertedPatientAppId=''
  if(leadResult.data.converted_patient_id){const {data}=await supabase.from('patients').select('app_id').eq('clinic_id',clinicId).eq('id',leadResult.data.converted_patient_id).maybeSingle();convertedPatientAppId=data?.app_id||''}
  const latestConsent=new Map();for(const row of consentsResult.data){if(!latestConsent.has(row.session_id))latestConsent.set(row.session_id,row.accepted)}
  const media=await Promise.all(mediaResult.data.filter(row=>latestConsent.get(row.session_id)).map(async row=>{const {data,error:signError}=await supabase.storage.from('lead-media').createSignedUrl(row.storage_path,900);if(signError)throw signError;return {id:row.id,path:row.storage_path,url:data?.signedUrl||'',label:row.photo_view_definitions?.label||'Photo',code:row.photo_view_definitions?.code||'',mimeType:row.mime_type,size:row.size_bytes,qualityStatus:row.quality_status,createdAt:row.created_at}}))
  return {
    lead:{...leadFromRow(leadResult.data),convertedPatientAppId},
    interactions:interactionsResult.data.map(row=>({id:row.id,leadId:row.lead_id,channel:row.channel,direction:row.direction,summary:row.summary,outcome:row.outcome||'',createdAt:row.created_at})),
    tasks:tasksResult.data.map(row=>({id:row.id,leadId:row.lead_id,title:row.title,dueAt:row.due_at,status:row.status})),
    invitations:invitationsResult.data.map(row=>({id:row.id,channel:row.channel,status:row.status,bookingSlug:row.booking_slug,expiresAt:row.expires_at,firstOpenedAt:row.first_opened_at,completedAt:row.completed_at,createdAt:row.created_at})),
    media,
    quotes:quotesResult.data.map(row=>({id:row.id,leadId:row.lead_id,title:row.title,amount:Number(row.amount),currency:row.currency,status:row.status,validUntil:row.valid_until||'',notes:row.notes||'',createdAt:row.created_at})),
    events:eventsResult.data.map(row=>({id:row.id,leadId:id,type:row.event_type,metadata:row.metadata,createdAt:row.created_at})),
    quoteEvents:quoteEventsResult.data.map(row=>({id:row.id,leadId:id,quoteId:row.quote_id,previousStatus:row.previous_status,status:row.status,createdAt:row.created_at}))
  }
}

export async function addLeadInteraction(leadId,payload){
  if(!supabaseEnabled){
    const row={id:crypto.randomUUID(),leadId,...payload,createdAt:new Date().toISOString()};const rows=localRows('interactions');rows.unshift(row);saveLocal('interactions',rows)
    const leads=localRows('leads');saveLocal('leads',leads.map(item=>item.id===leadId?{...item,lastContactAt:row.createdAt,status:item.status==='Nouveau'?'Contacte':item.status}:item));return row
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('lead_interactions').insert({clinic_id:clinicId,lead_id:leadId,channel:payload.channel,direction:payload.direction||'Sortant',summary:payload.summary,outcome:payload.outcome||null}).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,channel:data.channel,direction:data.direction,summary:data.summary,outcome:data.outcome||'',createdAt:data.created_at}
}

export async function createLeadInvitation(leadId,channel='Lien'){
  if(!supabaseEnabled){
    const token=crypto.randomUUID().replaceAll('-','')+crypto.randomUUID().replaceAll('-','').slice(0,16);const now=new Date();const expires=new Date(now.getTime()+14*86400000)
    const row={id:crypto.randomUUID(),leadId,token,channel,status:'Envoyee',bookingSlug:'consultation',createdAt:now.toISOString(),expiresAt:expires.toISOString()}
    const rows=localRows('invitations');rows.unshift(row);saveLocal('invitations',rows);await updateLead(leadId,{status:'Invitation envoyee'});return {id:row.id,token,path:`/intake/${token}`,expiresAt:row.expiresAt}
  }
  const {data,error}=await supabase.rpc('create_consultation_invitation',{p_lead_id:leadId,p_channel:channel,p_booking_slug:'consultation',p_expires_days:14})
  if(error)throw error
  return data
}

export async function revokeLeadInvitation(id){
  if(!supabaseEnabled){const rows=localRows('invitations');saveLocal('invitations',rows.map(row=>row.id===id?{...row,status:'Revoquee'}:row));return true}
  const {error}=await supabase.rpc('revoke_consultation_invitation',{p_id:id})
  if(error)throw error
  return true
}

export async function createFollowUpTask(leadId,payload){
  if(!supabaseEnabled){
    const row={id:crypto.randomUUID(),leadId,title:payload.title,dueAt:payload.dueAt,status:'A faire',createdAt:new Date().toISOString()};const rows=localRows('tasks');rows.unshift(row);saveLocal('tasks',rows);return row
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('follow_up_tasks').insert({clinic_id:clinicId,lead_id:leadId,title:payload.title,due_at:payload.dueAt,status:'A faire'}).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,dueAt:data.due_at,status:data.status}
}

export async function completeFollowUpTask(id){
  if(!supabaseEnabled){
    let changed=null;const rows=localRows('tasks').map(row=>row.id===id?(changed={...row,status:'Terminee',completedAt:new Date().toISOString()}):row);saveLocal('tasks',rows);return changed
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('follow_up_tasks').update({status:'Terminee',completed_at:new Date().toISOString()}).eq('clinic_id',clinicId).eq('id',id).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,dueAt:data.due_at,status:data.status}
}

export async function createLeadQuote(leadId,payload){
  if(!supabaseEnabled){const row={id:crypto.randomUUID(),leadId,...payload,status:'Brouillon',currency:payload.currency||'MAD',createdAt:new Date().toISOString()};const rows=localRows('quotes');rows.unshift(row);saveLocal('quotes',rows);saveLocal('quoteEvents',[{id:crypto.randomUUID(),leadId,quoteId:row.id,status:'Brouillon',createdAt:row.createdAt},...localRows('quoteEvents')]);return row}
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('lead_quotes').insert({clinic_id:clinicId,lead_id:leadId,title:payload.title,amount:Number(payload.amount),currency:payload.currency||'MAD',status:'Brouillon',valid_until:payload.validUntil||null,notes:payload.notes||null}).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,amount:Number(data.amount),currency:data.currency,status:data.status,validUntil:data.valid_until||'',notes:data.notes||'',createdAt:data.created_at}
}

export async function updateLeadQuoteStatus(id,status){
  if(!supabaseEnabled){let changed=null;const previous=localRows('quotes');const old=previous.find(row=>row.id===id);if(!old)throw new Error('Devis introuvable.');if(['Accepte','Refuse','Expire'].includes(old.status)||old.status==='Brouillon'&&status==='Accepte')throw new Error('Transition de devis impossible.');const rows=previous.map(row=>row.id===id?(changed={...row,status}):row);saveLocal('quotes',rows);saveLocal('quoteEvents',[{id:crypto.randomUUID(),leadId:old.leadId,quoteId:id,previousStatus:old.status,status,createdAt:new Date().toISOString()},...localRows('quoteEvents')]);return changed}
  const clinicId=await remoteClinicId();const {data,error}=await supabase.from('lead_quotes').update({status,updated_at:new Date().toISOString()}).eq('clinic_id',clinicId).eq('id',id).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,amount:Number(data.amount),currency:data.currency,status:data.status,validUntil:data.valid_until||'',notes:data.notes||'',createdAt:data.created_at}
}

export async function convertLeadToPatient(leadId){
  if(!supabaseEnabled){
    const leads=localRows('leads');const lead=leads.find(row=>row.id===leadId);if(!lead)throw new Error('Lead unavailable')
    const patients=JSON.parse(localStorage.getItem('dentalflow:patients')||'[]');const normalized=lead.phone?.replace(/\D/g,'');const matched=patients.find(row=>row.id===lead.convertedPatientId||(normalized&&row.phone?.replace(/\D/g,'')===normalized)||(lead.email&&row.email?.toLowerCase()===lead.email.toLowerCase()))
    if(!matched&&!normalized&&!lead.email)throw new Error('Contact requis avant conversion.')
    const patientId=matched?.id||crypto.randomUUID();if(!matched){patients.unshift({id:patientId,firstName:lead.firstName,lastName:lead.lastName,phone:lead.phone,email:lead.email,status:'Actif',createdAt:new Date().toISOString().slice(0,10)});localStorage.setItem('dentalflow:patients',JSON.stringify(patients))}
    await updateLead(leadId,{status:'Converti',convertedPatientId:patientId});return {patientId,existing:Boolean(matched)}
  }
  const {data,error}=await supabase.rpc('convert_lead_to_patient',{p_lead_id:leadId})
  if(error)throw error
  return data
}

export async function getPublicIntake(token){
  if(!supabaseEnabled){
    const invitation=localRows('invitations').find(row=>row.token===token&&row.status!=='Revoquee'&&new Date(row.expiresAt)>new Date())
    if(!invitation)return null
    const lead=localRows('leads').find(row=>row.id===invitation.leadId)
    return lead?{clinicName:'Dental Spa',clinicAddress:'Casablanca',firstName:lead.firstName,bookingSlug:invitation.bookingSlug||'consultation',expiresAt:invitation.expiresAt,completed:invitation.status==='Completee'}:null
  }
  const {data,error}=await supabase.rpc('public_acquisition_intake_page',{p_token:token})
  if(error)throw error
  return data
}

export async function submitPublicIntake(token,payload){
  if(!supabaseEnabled){
    const invitations=localRows('invitations');const invitation=invitations.find(row=>row.token===token&&row.status!=='Revoquee'&&row.status!=='Completee'&&new Date(row.expiresAt)>new Date())
    if(!invitation)throw new Error('Invitation unavailable')
    if(payload.consent!==true||!payload.firstName?.trim()||!payload.phone?.trim()||payload.phone.trim().length<6||!payload.concern?.trim()||payload.concern.trim().length<3)throw new Error('Intake fields and contact consent required')
    const sessions=localRows('sessions');const existing=sessions.find(row=>row.invitationId===invitation.id);const reference=`INT-${crypto.randomUUID().replaceAll('-','').slice(0,10).toUpperCase()}`
    const row={id:existing?.id||crypto.randomUUID(),leadId:invitation.leadId,invitationId:invitation.id,answers:payload,status:'Completee',submittedAt:new Date().toISOString(),reference}
    saveLocal('sessions',[row,...sessions.filter(item=>item.invitationId!==invitation.id)])
    saveLocal('invitations',invitations.map(item=>item.id===invitation.id?{...item,status:'Completee',completedAt:new Date().toISOString()}:item))
    await updateLead(invitation.leadId,{firstName:payload.firstName,lastName:payload.lastName,phone:payload.phone,email:payload.email,concern:payload.concern,status:'Qualifie'})
    return {success:true,bookingSlug:invitation.bookingSlug||'consultation',reference}
  }
  const {data,error}=await supabase.rpc('public_submit_lead_intake',{p_token:token,p_payload:payload})
  if(error)throw error
  return data
}

export async function uploadLeadMedia(token,viewCode,file){
  if(!supabaseEnabled){const row={id:crypto.randomUUID(),viewCode,size:file.size,contentType:file.type,qualityStatus:'A verifier',local:true};return row}
  const body=new FormData();body.append('token',token);body.append('viewCode',viewCode);body.append('file',file);body.append('photoConsent','true')
  const {data,error}=await supabase.functions.invoke('acquisition-media',{body})
  if(error)throw error
  if(data?.error)throw new Error(data.error)
  return data
}

export async function withdrawLeadMedia(token){
  if(!supabaseEnabled)return {success:true}
  const body=new FormData();body.append('token',token);body.append('action','withdraw')
  const {data,error}=await supabase.functions.invoke('acquisition-media',{body})
  if(error)throw error
  if(data?.error)throw new Error(data.error)
  return data
}
