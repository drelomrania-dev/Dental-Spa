import React from 'react'
import { ShieldX } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useData } from '../DataContext'

export default function RequirePermission({permission,permissions=[],roles=[],children}){
  const {can,currentUser,loading}=useData()
  if(loading)return null
  const required=permission?[permission,...permissions]:permissions
  if(required.some(item=>can(item))||roles.includes(currentUser?.role))return children
  return <main className="access-denied"><ShieldX size={42}/><h1>Accès refusé</h1><p>Votre rôle ne permet pas d’ouvrir ce module.</p><Link className="primary-btn" to="/">Retour au tableau de bord</Link></main>
}
