# Acquisition & Conversion — P0

## Parcours livré

1. L’équipe crée un prospect depuis **Acquisition** et le fait avancer dans le pipeline.
2. Les appels, messages, notes, relances et devis restent attachés à sa fiche.
3. Une invitation génère un jeton opaque, stocké uniquement sous forme de hash SHA-256.
4. Le patient complète le formulaire mobile, peut envoyer trois photos guidées et donne son consentement explicite.
5. Le patient choisit ensuite son rendez-vous dans le calendrier public.
6. L’accueil peut convertir le prospect en patient sans créer de doublon téléphone/email.

## Sécurité

- Toutes les tables métiers portent `clinic_id` et utilisent RLS.
- Les rôles `administrator` et `assistant` gèrent le pipeline; les praticiens conservent la lecture et peuvent consigner une interaction.
- Les RPC publiques ne retournent aucune donnée interne et exigent un jeton valide, non expiré et non révoqué.
- Les photos sont limitées à JPEG/PNG/WebP, 8 Mo, stockées dans le bucket privé `lead-media`.
- Le téléversement public passe par l’Edge Function `acquisition-media`, qui valide le hash du jeton avant toute écriture.
- L’équipe consulte les photos via des URL signées d’une heure.
- La migration révoque explicitement l’exécution anonyme des fonctions réservées au personnel.

## Vérification

- Build : `npm run build` (ou Vite via le runtime Node fourni par Codex).
- Test SQL transactionnel : exécuter `supabase/tests/acquisition_p0.sql` sur une base de développement.
- Test manuel mobile : créer une invitation, ouvrir `/intake/<token>`, parcourir les quatre étapes, vérifier que l’envoi final exige le consentement.
- Test média négatif : l’Edge Function doit répondre `401` à un jeton inconnu et ne créer aucun objet.

## Déploiement

Variables Vercel requises :

- `VITE_DATA_BACKEND=supabase`
- `VITE_SUPABASE_URL=<project URL>`
- `VITE_SUPABASE_ANON_KEY=<publishable key>`
- `VITE_USE_FIREBASE=false`

L’Edge Function utilise automatiquement `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` dans l’environnement Supabase; ces valeurs ne doivent jamais être exposées au navigateur.
