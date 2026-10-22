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
    const action=String(form.get("action")||"upload")
    if(!/^[A-Za-z0-9_-]{32,128}$/.test(token))return json({error:"Invitation unavailable"},401)
    if(!["upload","withdraw"].includes(action))return json({error:"Invalid action"},400)
    if(action==="upload"){
      if(!/^[a-z0-9-]{2,40}$/.test(viewCode))return json({error:"Invalid photo view"},400)
      if(!(file instanceof File))return json({error:"Photo required"},400)
      if(file.size<1||file.size>8*1024*1024)return json({error:"Photo must be smaller than 8 MB"},413)
      if(!["image/jpeg","image/png","image/webp"].includes(file.type))return json({error:"Unsupported image format"},415)
      const header=new Uint8Array(await file.slice(0,12).arrayBuffer())
      const ascii=(from:number,to:number)=>String.fromCharCode(...header.slice(from,to))
      const valid=file.type==="image/jpeg"?header[0]===0xff&&header[1]===0xd8&&header[2]===0xff:
        file.type==="image/png"?header[0]===0x89&&ascii(1,4)==="PNG":ascii(0,4)==="RIFF"&&ascii(8,12)==="WEBP"
      if(!valid)return json({error:"File content does not match image format"},415)
      if(String(form.get("photoConsent"))!=="true")return json({error:"Photo consent required"},400)
    }

    const projectUrl=Deno.env.get("SUPABASE_URL")
    const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if(!projectUrl||!serviceKey)return json({error:"Service unavailable"},503)
    const admin=createClient(projectUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})
    const hash=await sha256Hex(token)
    const {data:invitation,error:invitationError}=await admin.from("consultation_invitations")
      .select("id,clinic_id,lead_id,status,expires_at")
      .eq("token_hash",`\\x${hash}`).maybeSingle()
    if(invitationError)throw invitationError
    if(!invitation||["Revoquee","Expiree"].includes(invitation.status)||new Date(invitation.expires_at)<=new Date()||(action==="upload"&&invitation.status==="Completee"))return json({error:"Invitation unavailable"},401)

    const {data:existingSession,error:sessionReadError}=await admin.from("intake_sessions").select("id").eq("invitation_id",invitation.id).maybeSingle()
    if(sessionReadError)throw sessionReadError
    let sessionId=existingSession?.id
    if(!sessionId){
      if(action==="withdraw")return json({success:true})
      const {data:created,error:createError}=await admin.from("intake_sessions").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,invitation_id:invitation.id,status:"En cours",answers:{}}).select("id").single()
      if(createError)throw createError
      sessionId=created.id
    }

    if(action==="withdraw"){
      const {error:consentError}=await admin.from("consent_records").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,session_id:sessionId,consent_type:"guided_photos",accepted:false,policy_version:"1.0",evidence:{source:"public-intake",action:"withdraw"}})
      if(consentError)throw consentError
      const {data:media,error:mediaReadError}=await admin.from("lead_media").select("id,storage_path").eq("clinic_id",invitation.clinic_id).eq("session_id",sessionId)
      if(mediaReadError)throw mediaReadError
      if(media?.length){
        const {error:removeError}=await admin.storage.from("lead-media").remove(media.map(item=>item.storage_path))
        if(removeError)throw removeError
        const {error:deleteError}=await admin.from("lead_media").delete().eq("clinic_id",invitation.clinic_id).eq("session_id",sessionId)
        if(deleteError)throw deleteError
      }
      return json({success:true})
    }

    const {data:view,error:viewError}=await admin.from("photo_view_definitions").select("id,capture_protocols!inner(active)")
      .eq("clinic_id",invitation.clinic_id).eq("code",viewCode).eq("capture_protocols.active",true).maybeSingle()
    if(viewError)throw viewError
    if(!view)return json({error:"Photo view unavailable"},400)
    const {count:existingView,error:existingViewError}=await admin.from("lead_media").select("id",{count:"exact",head:true}).eq("clinic_id",invitation.clinic_id).eq("session_id",sessionId).eq("view_definition_id",view.id)
    if(existingViewError)throw existingViewError
    if(existingView)return json({error:"This photo view was already uploaded"},409)
    const {count:photoCount,error:countError}=await admin.from("lead_media").select("id",{count:"exact",head:true}).eq("clinic_id",invitation.clinic_id).eq("session_id",sessionId)
    if(countError)throw countError
    if((photoCount||0)>=3)return json({error:"Maximum three photos"},413)

    const {error:consentError}=await admin.from("consent_records").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,session_id:sessionId,consent_type:"guided_photos",accepted:true,policy_version:"1.0",evidence:{source:"public-intake",viewCode}})
    if(consentError)throw consentError

    const extension=file.type==="image/png"?"png":file.type==="image/webp"?"webp":"jpg"
    const storagePath=`${invitation.clinic_id}/${invitation.lead_id}/${sessionId}/${viewCode}-${crypto.randomUUID()}.${extension}`
    const {error:uploadError}=await admin.storage.from("lead-media").upload(storagePath,file,{contentType:file.type,upsert:false,cacheControl:"3600"})
    if(uploadError)throw uploadError
    const {data:media,error:mediaError}=await admin.from("lead_media").insert({clinic_id:invitation.clinic_id,lead_id:invitation.lead_id,session_id:sessionId,view_definition_id:view.id,storage_path:storagePath,mime_type:file.type,size_bytes:file.size,quality_status:"A verifier"}).select("id,storage_path,quality_status").single()
    if(mediaError){await admin.storage.from("lead-media").remove([storagePath]);throw mediaError}
    return json({id:media.id,viewCode,path:media.storage_path,size:file.size,contentType:file.type,qualityStatus:media.quality_status})
  }catch(error){
    console.error("acquisition-media",error)
    return json({error:"Unable to store photo"},500)
  }
})
