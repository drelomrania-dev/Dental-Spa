import { initializeApp } from 'firebase/app'
import { getFirestore } from 'firebase/firestore'

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID
}

// Local storage is the intentional default. Firebase becomes active only after
// the operator explicitly opts in with VITE_USE_FIREBASE=true.
export const firebaseEnabled = import.meta.env.VITE_USE_FIREBASE === 'true' && Boolean(firebaseConfig.apiKey && firebaseConfig.projectId && firebaseConfig.appId)
export const firebaseApp = firebaseEnabled ? initializeApp(firebaseConfig) : null
export const db = firebaseEnabled ? getFirestore(firebaseApp) : null
