import { remoteClinicId, supabase, supabaseEnabled } from './supabase'

const LOCAL_PREFIX = 'dentalflow:acquisition:'

function localRows(name){ return JSON.parse(localStorage.getItem(LOCAL_PREFIX+name)||'[]') }
function saveLocal(name,rows){ localStorage.setItem(LOCAL_PREFIX+name,JSON.stringify(rows)) }

function leadFromRow(row){
  return {
    id:row.id,firstName:row.first_name,lastName:row.last_name||'',phone:row.phone||'',email:row.email||'',
    source:row.source,status:row.status,priority:row.priority,ownerId:row.owner_id||'',concern:row.concern||'',notes:row.notes||'',
    lastContactAt:row.last_contact_at||'',nextFollowUpAt:row.next_follow_up_at||'',createdAt:row.created_at,updatedAt:row.updated_at
  }
}

function leadToRow(data,clinicId){
  return {
    clinic_id:clinicId,first_name:data.firstName.trim(),last_name:(data.lastName||'').trim(),phone:(data.phone||'').trim()||null,
    email:(data.email||'').trim()||null,source:data.source||'Direct',status:data.status||'Nouveau',priority:data.priority||'Normale',
    concern:(data.concern||'').trim()||null,notes:(data.notes||'').trim()||null,next_follow_up_at:data.nextFollowUpAt||null,updated_at:new Date().toISOString()
  }
}

export async function listLeads(){
  if(!supabaseEnabled) return localRows('leads').sort((a,b)=>String(b.createdAt).localeCompare(String(a.createdAt)))
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('leads').select('*').eq('clinic_id',clinicId).order('created_at',{ascending:false})
  if(error)throw error
  return data.map(leadFromRow)
}

export async function createLead(payload){
  if(!supabaseEnabled){
    const now=new Date().toISOString();const row={id:crypto.randomUUID(),...payload,status:payload.status||'Nouveau',priority:payload.priority||'Normale',createdAt:now,updatedAt:now}
    const rows=localRows('leads');rows.unshift(row);saveLocal('leads',rows);return row
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('leads').insert(leadToRow(payload,clinicId)).select('*').single()
  if(error)throw error
  return leadFromRow(data)
}

export async function updateLead(id,patch){
  if(!supabaseEnabled){
    let changed=null;const rows=localRows('leads').map(row=>row.id===id?(changed={...row,...patch,updatedAt:new Date().toISOString()}):row);saveLocal('leads',rows);return changed
  }
  const clinicId=await remoteClinicId();const row={}
  const map={firstName:'first_name',lastName:'last_name',phone:'phone',email:'email',source:'source',status:'status',priority:'priority',concern:'concern',notes:'notes',nextFollowUpAt:'next_follow_up_at'}
  Object.entries(map).forEach(([key,column])=>{if(Object.prototype.hasOwnProperty.call(patch,key))row[column]=patch[key]||null})
  row.updated_at=new Date().toISOString()
  const {data,error}=await supabase.from('leads').update(row).eq('clinic_id',clinicId).eq('id',id).select('*').single()
  if(error)throw error
  return leadFromRow(data)
}

export async function getLeadBundle(id){
  if(!supabaseEnabled){
    return {lead:localRows('leads').find(row=>row.id===id)||null,interactions:localRows('interactions').filter(row=>row.leadId===id),tasks:localRows('tasks').filter(row=>row.leadId===id),invitations:localRows('invitations').filter(row=>row.leadId===id),media:localRows('media').filter(row=>row.leadId===id),quotes:localRows('quotes').filter(row=>row.leadId===id)}
  }
  const clinicId=await remoteClinicId()
  const [leadResult,interactionsResult,tasksResult,invitationsResult,mediaResult,quotesResult]=await Promise.all([
    supabase.from('leads').select('*').eq('clinic_id',clinicId).eq('id',id).single(),
    supabase.from('lead_interactions').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('follow_up_tasks').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('due_at',{ascending:true}),
    supabase.from('consultation_invitations').select('id,channel,status,booking_slug,expires_at,first_opened_at,completed_at,created_at').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_media').select('id,storage_path,mime_type,size_bytes,quality_status,created_at,photo_view_definitions(label,code)').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false}),
    supabase.from('lead_quotes').select('*').eq('clinic_id',clinicId).eq('lead_id',id).order('created_at',{ascending:false})
  ])
  const failure=[leadResult,interactionsResult,tasksResult,invitationsResult,mediaResult,quotesResult].find(result=>result.error)
  if(failure)throw failure.error
  const media=await Promise.all(mediaResult.data.map(async row=>{const {data}=await supabase.storage.from('lead-media').createSignedUrl(row.storage_path,3600);return {id:row.id,path:row.storage_path,url:data?.signedUrl||'',label:row.photo_view_definitions?.label||'Photo',code:row.photo_view_definitions?.code||'',mimeType:row.mime_type,size:row.size_bytes,qualityStatus:row.quality_status,createdAt:row.created_at}}))
  return {
    lead:leadFromRow(leadResult.data),
    interactions:interactionsResult.data.map(row=>({id:row.id,leadId:row.lead_id,channel:row.channel,direction:row.direction,summary:row.summary,outcome:row.outcome||'',createdAt:row.created_at})),
    tasks:tasksResult.data.map(row=>({id:row.id,leadId:row.lead_id,title:row.title,dueAt:row.due_at,status:row.status})),
    invitations:invitationsResult.data.map(row=>({id:row.id,channel:row.channel,status:row.status,bookingSlug:row.booking_slug,expiresAt:row.expires_at,firstOpenedAt:row.first_opened_at,completedAt:row.completed_at,createdAt:row.created_at})),
    media,
    quotes:quotesResult.data.map(row=>({id:row.id,leadId:row.lead_id,title:row.title,amount:Number(row.amount),currency:row.currency,status:row.status,validUntil:row.valid_until||'',notes:row.notes||'',createdAt:row.created_at}))
  }
}

export async function addLeadInteraction(leadId,payload){
  if(!supabaseEnabled){
    const row={id:crypto.randomUUID(),leadId,...payload,createdAt:new Date().toISOString()};const rows=localRows('interactions');rows.unshift(row);saveLocal('interactions',rows)
    await updateLead(leadId,{status:payload.status||'Contacte',lastContactAt:row.createdAt});return row
  }
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('lead_interactions').insert({clinic_id:clinicId,lead_id:leadId,channel:payload.channel,direction:payload.direction||'Sortant',summary:payload.summary,outcome:payload.outcome||null}).select('*').single()
  if(error)throw error
  await supabase.from('leads').update({status:payload.status||'Contacte',last_contact_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('clinic_id',clinicId).eq('id',leadId)
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
  if(!supabaseEnabled){const row={id:crypto.randomUUID(),leadId,...payload,status:'Brouillon',currency:'MAD',createdAt:new Date().toISOString()};const rows=localRows('quotes');rows.unshift(row);saveLocal('quotes',rows);return row}
  const clinicId=await remoteClinicId()
  const {data,error}=await supabase.from('lead_quotes').insert({clinic_id:clinicId,lead_id:leadId,title:payload.title,amount:Number(payload.amount),currency:'MAD',status:'Brouillon',valid_until:payload.validUntil||null,notes:payload.notes||null}).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,amount:Number(data.amount),currency:data.currency,status:data.status,validUntil:data.valid_until||'',notes:data.notes||'',createdAt:data.created_at}
}

export async function updateLeadQuoteStatus(id,status){
  if(!supabaseEnabled){let changed=null;const rows=localRows('quotes').map(row=>row.id===id?(changed={...row,status}):row);saveLocal('quotes',rows);return changed}
  const clinicId=await remoteClinicId();const {data,error}=await supabase.from('lead_quotes').update({status,updated_at:new Date().toISOString()}).eq('clinic_id',clinicId).eq('id',id).select('*').single()
  if(error)throw error
  return {id:data.id,leadId:data.lead_id,title:data.title,amount:Number(data.amount),currency:data.currency,status:data.status,validUntil:data.valid_until||'',notes:data.notes||'',createdAt:data.created_at}
}

export async function convertLeadToPatient(leadId){
  if(!supabaseEnabled){
    const leads=localRows('leads');const lead=leads.find(row=>row.id===leadId);if(!lead)throw new Error('Lead unavailable')
    const patientId=crypto.randomUUID();const patients=JSON.parse(localStorage.getItem('dentalflow:patients')||'[]');patients.unshift({id:patientId,firstName:lead.firstName,lastName:lead.lastName,phone:lead.phone,email:lead.email,status:'Actif',createdAt:new Date().toISOString().slice(0,10)});localStorage.setItem('dentalflow:patients',JSON.stringify(patients));await updateLead(leadId,{status:'Converti'});return {patientId,existing:false}
  }
  const {data,error}=await supabase.rpc('convert_lead_to_patient',{p_lead_id:leadId})
  if(error)throw error
  return data
}

export async function getPublicIntake(token){
  if(!supabaseEnabled){
    const invitation=localRows('invitations').find(row=>row.token===token&&new Date(row.expiresAt)>new Date())
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
    const invitations=localRows('invitations');const invitation=invitations.find(row=>row.token===token&&new Date(row.expiresAt)>new Date())
    if(!invitation)throw new Error('Invitation unavailable')
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
  const body=new FormData();body.append('token',token);body.append('viewCode',viewCode);body.append('file',file)
  const {data,error}=await supabase.functions.invoke('acquisition-media',{body})
  if(error)throw error
  if(data?.error)throw new Error(data.error)
  return data
}
