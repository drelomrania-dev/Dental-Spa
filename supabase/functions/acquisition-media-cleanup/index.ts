import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

// Invoke from a trusted scheduled job with the service-role bearer key. Each
// run processes at most 100 eligible media records; repeat until removed=0.
Deno.serve(async request=>{
  if(request.method!=="POST")return new Response("Method not allowed",{status:405})
  const url=Deno.env.get("SUPABASE_URL")
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if(!url||!key)return new Response("Service unavailable",{status:503})
  if(request.headers.get("authorization")!==`Bearer ${key}`)return new Response("Unauthorized",{status:401})

  const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}})
  try{
    const {data:media,error:mediaError}=await admin.rpc("acquisition_media_cleanup_candidates",{p_limit:100})
    if(mediaError)throw mediaError
    if(!media?.length)return Response.json({removed:0})
    const {error:storageError}=await admin.storage.from("lead-media").remove(media.map(item=>item.storage_path))
    if(storageError)throw storageError
    const {error:deleteError}=await admin.from("lead_media").delete().in("id",media.map(item=>item.media_id))
    if(deleteError)throw deleteError
    return Response.json({removed:media.length})
  }catch(error){
    console.error("acquisition-media-cleanup",error)
    return Response.json({error:"Cleanup failed"},{status:500})
  }
})
