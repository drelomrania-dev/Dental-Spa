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

let firebaseStorePromise = null

export function getFirebaseStore(){
  if(!firebaseEnabled) return Promise.resolve(null)
  if(!firebaseStorePromise){
    firebaseStorePromise = Promise.all([import('firebase/app'), import('firebase/firestore')]).then(([appModule, firestoreModule]) => {
      const app = appModule.initializeApp(firebaseConfig)
      const db = firestoreModule.getFirestore(app)
      return { db, ...firestoreModule }
    })
  }
  return firebaseStorePromise
}
