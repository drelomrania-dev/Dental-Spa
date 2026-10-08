# DentalFlow — Dental Spa MVP

Interface française, mobile-first, pour les flux quotidiens d’un cabinet dentaire. La version déployée utilise Supabase Auth et PostgreSQL avec des politiques RLS par cabinet. Un mode localStorage reste disponible pour le développement hors ligne.

## Modules inclus

- Vue d’ensemble
- Patients
- Nouveau paiement + ticket imprimable
- Historique des paiements + export CSV
- Soldes à recevoir / plans de paiement ouverts
- Rendez-vous / bookings
- Praticiens
- Soins & tarifs
- Rapports simples
- Paramètres et configuration clinique
- Réservation publique `/book/consultation`
- Modèle de visites cliniques, plans de traitement, demandes de prix négociés et sessions de caisse

Le dépôt contient les fondations intégrées du MVP. Avant de charger de vraies données patients, validez les exigences réglementaires, la conservation des données et les sauvegardes applicables à votre cabinet.

## Fonctionnement des données

L’application utilise une couche `dataStore` unique :

- Supabase est utilisé lorsque `VITE_DATA_BACKEND=supabase` et que les variables Supabase sont renseignées ;
- le mode localStorage reste disponible si aucun backend distant n’est configuré ;
- l’intégration Firebase historique reste facultative.

La préparation Supabase est documentée dans `docs/SUPABASE_SETUP.md`. Le schéma et les migrations sont versionnés dans `supabase/`.

Collections :

- `patients`
- `treatments`
- `doctors`
- `appointments`
- `payments`
- `visits`, `treatmentPlans`, `priceRequests`, `collectionSessions`, `bookingLinks`, `staff`, `roles`, `auditEvents`

## Installation

```bash
npm install
cp .env.example .env
npm run dev
```

Puis ouvrir `http://localhost:5173`.

## Connexion Supabase

1. Créer un projet Supabase.
2. Exécuter le schéma et les migrations du dossier `supabase/`.
3. Copier les variables publiques du projet dans `.env.local` :

```env
VITE_DATA_BACKEND=supabase
VITE_SUPABASE_URL=https://PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=...
VITE_USE_FIREBASE=false
```

5. Relancer `npm run dev`.

## Important avant production

Ce prototype n'est pas encore un dossier médical électronique. Avant d’utiliser de vraies données patients :

- vérifier Supabase Auth et les rôles (administrateur, accueil, praticien, etc.) ;
- auditer régulièrement les politiques RLS par rôle et par clinique ;
- définir les règles de conservation/suppression des données ;
- journaliser les modifications sensibles ;
- vérifier les exigences réglementaires applicables à votre cabinet et à l’hébergement choisi.

Les politiques Supabase du dépôt isolent les données par cabinet. Ne publiez jamais une clé `service_role` dans une application web.

## Structure principale

```text
src/
  components/    composants de navigation et UI
  pages/         écrans métier
  services/      Supabase, Firebase optionnel et couche de données
  data/          données de démonstration
  DataContext.jsx
  App.jsx
  styles.css
```

## Prochaines évolutions recommandées

- Gestion complète des utilisateurs et invitations par rôle
- Échéancier détaillé pour chaque plan de paiement
- Rappels automatiques des échéances
- Vue calendrier semaine/mois avec disponibilités praticiens
- Dossier patient enrichi (sans mélanger la partie paiement avec le dossier médical tant que le périmètre n’est pas défini)
- Annulation/remboursement avec journal d’audit
- Numérotation de reçus configurable
- Impression thermique 80 mm
- Procédure de sauvegarde et restauration Supabase testée
