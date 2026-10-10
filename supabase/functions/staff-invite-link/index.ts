import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const allowedOrigins=new Set(["https://dental-spa-taupe.vercel.app","http://localhost:5173","http://127.0.0.1:5173"])
function cors(origin:string|null){return {"Access-Control-Allow-Origin":origin&&allowedOrigins.has(origin)?origin:"https://dental-spa-taupe.vercel.app","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"}}
function json(body:unknown,status:number,origin:string|null){return new Response(JSON.stringify(body),{status,headers:{...cors(origin),"Content-Type":"application/json"}})}
async function sha256Hex(value:string){const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value));return Array.from(new Uint8Array(bytes)).map(byte=>byte.toString(16).padStart(2,"0")).join("")}

Deno.serve(async request=>{
  const origin=request.headers.get("origin")
  if(request.method==="OPTIONS")return new Response("ok",{headers:cors(origin)})
  if(request.method!=="POST")return json({error:"Method not allowed"},405,origin)
  try{
    const projectUrl=Deno.env.get("SUPABASE_URL")
    const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    const authorization=request.headers.get("authorization")||""
    if(!projectUrl||!serviceKey)return json({error:"Service unavailable"},503,origin)
    if(!authorization.startsWith("Bearer "))return json({error:"Authentication required"},401,origin)
    const admin=createClient(projectUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}})
    const {data:userData,error:userError}=await admin.auth.getUser(authorization.slice(7))
    if(userError||!userData.user)return json({error:"Authentication required"},401,origin)
    const {data:staff,error:staffError}=await admin.from("staff_profiles").select("clinic_id,role,active").eq("id",userData.user.id).maybeSingle()
    if(staffError)throw staffError
    if(!staff?.active||staff.role!=="administrator")return json({error:"Staff management denied"},403,origin)
    const body=await request.json()
    const token=String(body?.token||"")
    const redirectTo=String(body?.redirectTo||"")
    if(!/^[A-Za-z0-9_-]{32,128}$/.test(token))return json({error:"Invitation unavailable"},400,origin)
    let redirect:URL
    try{redirect=new URL(redirectTo)}catch{return json({error:"Invalid redirect"},400,origin)}
    if(!allowedOrigins.has(redirect.origin)||!redirect.pathname.startsWith("/join/"))return json({error:"Invalid redirect"},400,origin)
    const hash=await sha256Hex(token)
    const {data:invitation,error:inviteError}=await admin.from("staff_invitations").select("id,email,status,expires_at").eq("clinic_id",staff.clinic_id).eq("token_hash",hash).maybeSingle()
    if(inviteError)throw inviteError
    if(!invitation||invitation.status!=="pending"||new Date(invitation.expires_at)<=new Date())return json({error:"Invitation unavailable"},404,origin)
    let generated=await admin.auth.admin.generateLink({type:"invite",email:invitation.email,options:{redirectTo:redirect.toString()}})
    if(generated.error&&generated.error.message.toLowerCase().includes("already"))generated=await admin.auth.admin.generateLink({type:"magiclink",email:invitation.email,options:{redirectTo:redirect.toString()}})
    if(generated.error)throw generated.error
    const actionLink=generated.data.properties?.action_link
    if(!actionLink)throw new Error("Action link unavailable")
    return json({invitationId:invitation.id,actionLink,expiresAt:invitation.expires_at},200,origin)
  }catch(error){console.error("staff-invite-link",error);return json({error:"Unable to generate staff access link"},500,origin)}
})
