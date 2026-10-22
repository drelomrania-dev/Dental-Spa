import React, { lazy, Suspense } from 'react'
import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { DataProvider } from './DataContext'
import Layout from './components/Layout'
const Dashboard = lazy(() => import('./pages/Dashboard'))
const Patients = lazy(() => import('./pages/Patients'))
const PatientProfile = lazy(() => import('./pages/PatientProfile'))
const Payments = lazy(() => import('./pages/Payments'))
const PaymentHistory = lazy(() => import('./pages/PaymentHistory'))
const Receivables = lazy(() => import('./pages/Receivables'))
const Appointments = lazy(() => import('./pages/Appointments'))
const Doctors = lazy(() => import('./pages/Doctors'))
const Treatments = lazy(() => import('./pages/Treatments'))
const Reports = lazy(() => import('./pages/Reports'))
const Settings = lazy(() => import('./pages/Settings'))
const PublicBooking = lazy(() => import('./pages/PublicBooking'))
const Clinical = lazy(() => import('./pages/Clinical'))
const Approvals = lazy(() => import('./pages/Approvals'))
const CollectionSessions = lazy(() => import('./pages/CollectionSessions'))
const Reminders = lazy(() => import('./pages/Reminders'))
import { AuthProvider } from './AuthContext'
import AuthGate from './components/AuthGate'
const PublicBookingRemote = lazy(() => import('./pages/PublicBookingRemote'))
import { supabaseEnabled } from './services/supabase'
import RequirePermission from './components/RequirePermission'
const Acquisition = lazy(() => import('./pages/Acquisition'))
const LeadProfile = lazy(() => import('./pages/LeadProfile'))
const PublicIntake = lazy(() => import('./pages/PublicIntake'))
const PublicManageBooking = lazy(() => import('./pages/PublicManageBooking'))
const StaffJoin = lazy(() => import('./pages/StaffJoin'))
import './styles.css'

function InternalRoutes(){ return <Routes><Route element={<Layout/>}>
    <Route path="/" element={<Dashboard/>}/>
    <Route path="/patients" element={<RequirePermission permission="patients.basic.view" roles={['administrator']}><Patients/></RequirePermission>}/>
    <Route path="/patients/:patientId" element={<RequirePermission permission="patients.basic.view" roles={['administrator']}><PatientProfile/></RequirePermission>}/>
    <Route path="/acquisition" element={<RequirePermission permission="acquisition.view" roles={['administrator']}><Acquisition/></RequirePermission>}/>
    <Route path="/acquisition/:leadId" element={<RequirePermission permission="acquisition.view" roles={['administrator']}><LeadProfile/></RequirePermission>}/>
    <Route path="/payments" element={<RequirePermission permission="payments.collect" roles={['administrator']}><Payments/></RequirePermission>}/>
    <Route path="/payment-history" element={<RequirePermission permission="payments.view.all" roles={['administrator']}><PaymentHistory/></RequirePermission>}/>
    <Route path="/receivables" element={<RequirePermission permission="payments.view.all" roles={['administrator']}><Receivables/></RequirePermission>}/>
    <Route path="/appointments" element={<RequirePermission permission="appointments.view" roles={['administrator']}><Appointments/></RequirePermission>}/>
    <Route path="/reminders" element={<RequirePermission permission="reminders.manage" roles={['administrator']}><Reminders/></RequirePermission>}/>
    <Route path="/doctors" element={<RequirePermission permissions={['services.view','services.manage','settings.manage']} roles={['administrator']}><Doctors/></RequirePermission>}/>
    <Route path="/treatments" element={<RequirePermission permissions={['services.view','services.manage','settings.manage']} roles={['administrator']}><Treatments/></RequirePermission>}/>
    <Route path="/reports" element={<RequirePermission permission="reports.finance" roles={['administrator']}><Reports/></RequirePermission>}/>
    <Route path="/settings" element={<RequirePermission permissions={['settings.manage','staff.manage','permissions.manage','audit.view']} roles={['administrator']}><Settings/></RequirePermission>}/>
    <Route path="/clinical" element={<RequirePermission permission="clinical.view" roles={['administrator']}><Clinical/></RequirePermission>}/>
    <Route path="/approvals" element={<RequirePermission permissions={['priceRequests.create','priceRequests.approve']} roles={['administrator']}><Approvals/></RequirePermission>}/>
    <Route path="/collection-sessions" element={<RequirePermission permissions={['sessions.own','sessions.manage']} roles={['administrator']}><CollectionSessions/></RequirePermission>}/>
  </Route></Routes> }

export default function App(){
  return <BrowserRouter><AuthProvider><Suspense fallback={<div className="loading-state">Chargement…</div>}><Routes>
    <Route path="/book/:slug" element={supabaseEnabled?<PublicBookingRemote/>:<DataProvider><PublicBooking/></DataProvider>}/>
    <Route path="/manage-booking/:token" element={supabaseEnabled?<PublicManageBooking/>:<main className="public-booking"><div className="public-card"><h1>Gestion en ligne indisponible</h1><p>Activez Supabase pour utiliser ce lien sécurisé.</p></div></main>}/>
    <Route path="/intake/:token" element={<PublicIntake/>}/>
    <Route path="/join/:token" element={<StaffJoin/>}/>
    <Route path="/*" element={<AuthGate><DataProvider><InternalRoutes/></DataProvider></AuthGate>}/>
  </Routes></Suspense></AuthProvider></BrowserRouter>
}
