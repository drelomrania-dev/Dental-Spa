export const seedData = {
  patients: [
    { id:'p1', firstName:'Salma', lastName:'Benali', phone:'+212 6 12 34 56 78', email:'salma@example.com', createdAt:'2026-10-01', status:'Actif' },
    { id:'p2', firstName:'Youssef', lastName:'Alaoui', phone:'+212 6 33 20 18 44', email:'youssef@example.com', createdAt:'2026-09-27', status:'Actif' },
    { id:'p3', firstName:'Nadia', lastName:'Berrada', phone:'+212 6 67 90 12 08', email:'nadia@example.com', createdAt:'2026-09-20', status:'Actif' },
    { id:'p4', firstName:'Omar', lastName:'Tazi', phone:'+212 6 80 40 14 21', email:'omar@example.com', createdAt:'2026-09-18', status:'Actif' }
  ],
  treatments: [
    { id:'t1', name:'Consultation', category:'Diagnostic', price:350, duration:30, active:true },
    { id:'t2', name:'Radiologie', category:'Diagnostic', price:250, duration:20, active:true },
    { id:'t3', name:'Détartrage', category:'Prévention', price:600, duration:45, active:true },
    { id:'t4', name:'Facette dentaire', category:'Esthétique', price:4500, duration:90, active:true },
    { id:'t5', name:'Couronne', category:'Prothèse', price:3200, duration:60, active:true },
    { id:'t6', name:'Traitement orthodontique', category:'Orthodontie', price:18000, duration:60, active:true },
    { id:'t7', name:'Implantologie', category:'Chirurgie', price:12000, duration:90, active:true }
  ],
  doctors: [
    { id:'d1', name:'Dr. A. Omrani', specialty:'Dentisterie esthétique', phone:'+212 5 22 00 00 01', email:'doctor@clinic.ma', availability:'Lun–Ven', color:'#7357f6', active:true },
    { id:'d2', name:'Dr. N. Karim', specialty:'Orthodontie', phone:'+212 5 22 00 00 02', email:'ortho@clinic.ma', availability:'Mar–Sam', color:'#1eb980', active:true },
    { id:'d3', name:'Dr. S. Amine', specialty:'Implantologie', phone:'+212 5 22 00 00 03', email:'implant@clinic.ma', availability:'Lun–Jeu', color:'#ff9f43', active:true }
  ],
  appointments: [
    { id:'a1', patientId:'p1', doctorId:'d1', date:'2026-10-07', time:'09:00', duration:45, reason:'Détartrage', status:'Confirmé' },
    { id:'a2', patientId:'p2', doctorId:'d3', date:'2026-10-07', time:'11:30', duration:60, reason:'Consultation implant', status:'Confirmé' },
    { id:'a3', patientId:'p3', doctorId:'d2', date:'2026-10-07', time:'14:00', duration:45, reason:'Contrôle orthodontie', status:'En attente' },
    { id:'a4', patientId:'p4', doctorId:'d1', date:'2026-10-08', time:'10:30', duration:30, reason:'Consultation', status:'Confirmé' }
  ],
  payments: [
    { id:'pay1', patientId:'p1', treatmentId:'t3', doctorId:'d1', date:'2026-10-07', total:600, paid:600, remaining:0, plan:'Comptant', method:'Carte', status:'Payé', reference:'REC-1001' },
    { id:'pay2', patientId:'p2', treatmentId:'t7', doctorId:'d3', date:'2026-10-07', total:12000, paid:4000, remaining:8000, plan:'3 fois', method:'Carte', status:'Partiel', reference:'REC-1002' },
    { id:'pay3', patientId:'p3', treatmentId:'t6', doctorId:'d2', date:'2026-10-06', total:18000, paid:3000, remaining:15000, plan:'Mensuel', method:'Virement', status:'Partiel', reference:'REC-0999' },
    { id:'pay4', patientId:'p4', treatmentId:'t1', doctorId:'d1', date:'2026-10-05', total:350, paid:350, remaining:0, plan:'Comptant', method:'Espèces', status:'Payé', reference:'REC-0998' }
  ],
  visits: [],
  treatmentPlans: [],
  priceRequests: [],
  collectionSessions: [],
  auditEvents: [],
  bookingLinks: [
    { id:'bl1', slug:'consultation', title:'Réserver une consultation', description:'Un premier échange avec notre équipe dentaire.', treatmentId:'t1', doctorId:'', duration:30, published:true, confirmationPolicy:'auto' }
  ],
  staff: [
    { id:'u1', name:'Administrateur', role:'administrator', email:'admin@dentalspa.ma', active:true },
    { id:'u2', name:'Accueil', role:'assistant', email:'accueil@dentalspa.ma', active:true },
    { id:'u3', name:'Dr. A. Omrani', role:'practitioner', email:'doctor@clinic.ma', active:true }
  ],
  roles: [
    { id:'role-admin', name:'Administrateur', permissions:['*'] },
    { id:'role-assistant', name:'Accueil', permissions:['appointments.view','appointments.create','patients.basic.view','patients.create','payments.collect','payments.receipt','priceRequests.create','sessions.own'] },
    { id:'role-practitioner', name:'Praticien', permissions:['appointments.view','patients.basic.view','clinical.view','clinical.edit','plans.create'] }
  ]
}
