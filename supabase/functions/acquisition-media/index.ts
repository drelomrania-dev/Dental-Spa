import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const corsHeaders={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods":"POST, OPTIONS"
}

function json(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}})}

async function sha256Hex(value:string){
  const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value))
  return Array.from(new Uint8Array(bytes)).map(byte=>byte.toString(16).padStart(2,"0")).join("")
}

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders})
  if(request.method!=="POST")return json({error:"Method not allowed"},405)
  try{
    const form=await request.formData()
    const token=String(form.get("token")||"")
    const viewCode=String(form.get("viewCode")||"")
    const file=form.get("file")
    if(!/^[A-Za-z0-9_-]{32,128}$/.test(token))return json({error:"Invitation unavailable"},401)
    if(!/^[a-z0-9-]{2,40}$/.test(viewCode))return json({error:"Invalid photo view"},400)
    if(!(file instanceof File))return json({error:"Photo required"},400)
    if(file.size<1||file.size>8*1024*1024)return json({error:"Photo must be smaller than 8 MB"},413)
    if(!["image/jpeg","image/png","image/webp"].includes(file.type))return json({error:"Unsupported image format"},415)

    const projectUrl=Deno.env.get("SUPABASE_URL")
    const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if(!projectUrl||!serviceKey)return json({error:"Service unavailable"},503)
    const admin=createClient(projectUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})
    const hash=await sha256Hex(token)
    const {data:invitation,error:invitationError}=await admin.from("consultation_invitations")
      .select("id,clinic_id,lead_id,status,expires_at")
      .eq("token_hash",`\\x${hash}`).maybeSingle()
    if(invitationError)throw invitationError
    if(!invitation||["Revoquee","Expiree"].includes(invitation.status)||new Date(invitation.expires_at)<=new Date())return json({error:"Invitation unavailable"},401)

    const {data:existingSession,error:sessionReadError}=await admin.from("intake_sessions").select("id").eq("invitation_id",invitation.id).maybeSingle()
    if(sessionReadError)throw sessionReadError
    let sessionId=existingSession?.id
    if(!sessionId){
      const {data:created,error:createError}=await admin.from("intake_sessions").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,invitation_id:invitation.id,status:"En cours",answers:{}}).select("id").single()
      if(createError)throw createError
      sessionId=created.id
    }

    const extension=file.type==="image/png"?"png":file.type==="image/webp"?"webp":"jpg"
    const storagePath=`${invitation.clinic_id}/${invitation.lead_id}/${sessionId}/${viewCode}-${crypto.randomUUID()}.${extension}`
    const {error:uploadError}=await admin.storage.from("lead-media").upload(storagePath,file,{contentType:file.type,upsert:false,cacheControl:"3600"})
    if(uploadError)throw uploadError
    const {data:media,error:mediaError}=await admin.from("lead_media").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,session_id:sessionId,storage_path:storagePath,mime_type:file.type,size_bytes:file.size,quality_status:"A verifier"}).select("id,storage_path,quality_status").single()
    if(mediaError){await admin.storage.from("lead-media").remove([storagePath]);throw mediaError}
    return json({id:media.id,viewCode,path:media.storage_path,size:file.size,contentType:file.type,qualityStatus:media.quality_status})
  }catch(error){
    console.error("acquisition-media",error)
    return json({error:"Unable to store photo"},500)
  }
})
