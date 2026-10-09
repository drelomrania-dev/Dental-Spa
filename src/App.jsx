import React from 'react'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { DataProvider } from './DataContext'
import Layout from './components/Layout'
import Dashboard from './pages/Dashboard'
import Patients from './pages/Patients'
import PatientProfile from './pages/PatientProfile'
import Payments from './pages/Payments'
import PaymentHistory from './pages/PaymentHistory'
import Receivables from './pages/Receivables'
import Appointments from './pages/Appointments'
import Doctors from './pages/Doctors'
import Treatments from './pages/Treatments'
import Reports from './pages/Reports'
import Settings from './pages/Settings'
import PublicBooking from './pages/PublicBooking'
import Clinical from './pages/Clinical'
import Approvals from './pages/Approvals'
import CollectionSessions from './pages/CollectionSessions'
import { AuthProvider } from './AuthContext'
import AuthGate from './components/AuthGate'
import PublicBookingRemote from './pages/PublicBookingRemote'
import { supabaseEnabled } from './services/supabase'
import RequirePermission from './components/RequirePermission'
import Acquisition from './pages/Acquisition'
import LeadProfile from './pages/LeadProfile'
import PublicIntake from './pages/PublicIntake'
import PublicManageBooking from './pages/PublicManageBooking'
import './styles.css'

function InternalRoutes(){ return <Routes><Route element={<Layout/>}>
    <Route path="/" element={<Dashboard/>}/>
    <Route path="/patients" element={<Patients/>}/>
    <Route path="/patients/:patientId" element={<PatientProfile/>}/>
    <Route path="/acquisition" element={<RequirePermission roles={['administrator','assistant','practitioner']}><Acquisition/></RequirePermission>}/>
    <Route path="/acquisition/:leadId" element={<RequirePermission roles={['administrator','assistant','practitioner']}><LeadProfile/></RequirePermission>}/>
    <Route path="/payments" element={<RequirePermission permission="payments.collect" roles={['administrator']}><Payments/></RequirePermission>}/>
    <Route path="/payment-history" element={<RequirePermission roles={['administrator']}><PaymentHistory/></RequirePermission>}/>
    <Route path="/receivables" element={<RequirePermission roles={['administrator']}><Receivables/></RequirePermission>}/>
    <Route path="/appointments" element={<Appointments/>}/>
    <Route path="/doctors" element={<Doctors/>}/>
    <Route path="/treatments" element={<Treatments/>}/>
    <Route path="/reports" element={<RequirePermission roles={['administrator']}><Reports/></RequirePermission>}/>
    <Route path="/settings" element={<RequirePermission roles={['administrator']}><Settings/></RequirePermission>}/>
    <Route path="/clinical" element={<RequirePermission permission="clinical.view" roles={['administrator']}><Clinical/></RequirePermission>}/>
    <Route path="/approvals" element={<RequirePermission permission="priceRequests.create" roles={['administrator']}><Approvals/></RequirePermission>}/>
    <Route path="/collection-sessions" element={<RequirePermission permission="sessions.own" roles={['administrator']}><CollectionSessions/></RequirePermission>}/>
  </Route></Routes> }

export default function App(){
  return <BrowserRouter><AuthProvider><Routes>
    <Route path="/book/:slug" element={supabaseEnabled?<PublicBookingRemote/>:<DataProvider><PublicBooking/></DataProvider>}/>
    <Route path="/manage-booking/:token" element={supabaseEnabled?<PublicManageBooking/>:<main className="public-booking"><div className="public-card"><h1>Gestion en ligne indisponible</h1><p>Activez Supabase pour utiliser ce lien sécurisé.</p></div></main>}/>
    <Route path="/intake/:token" element={<PublicIntake/>}/>
    <Route path="/*" element={<AuthGate><DataProvider><InternalRoutes/></DataProvider></AuthGate>}/>
  </Routes></AuthProvider></BrowserRouter>
}
