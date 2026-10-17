# Plume

App de dictée vocale pour Mac, faite par ONE COM.

Maintiens **Option droite**, parle, relâche : le texte s'écrit là où se trouve ton curseur, dans n'importe quelle app.

- **Transcription 100 % locale** avec Whisper (WhisperKit), la voix ne quitte jamais le Mac.
- **Mise au propre par Claude** (optionnelle) : ponctuation, hésitations retirées, corrections. Seul le texte est envoyé.
- **Tableau de bord** : mots dictés, vitesse, temps gagné, graphique des 14 derniers jours, répartition par app.
- **Historique** et **dictionnaire** de mots personnalisés (noms de clients, marques…).

## Compilation

L'app est compilée automatiquement par GitHub Actions (`.github/workflows/build.yml`) sur un Mac à chaque envoi sur `main`. Le fichier `Plume.zip` est disponible dans l'onglet *Actions*, rubrique *Artifacts*.

En local (Mac avec Xcode 26) :

```bash
brew install xcodegen
xcodegen generate
open Plume.xcodeproj
```

## Licences

- WhisperKit, Argmax : MIT (`LICENSES/WhisperKit-MIT.txt`)
- Recherche de la touche de collage selon le clavier, adaptée d'OpenWhispr : MIT (`LICENSES/OpenWhispr-MIT.txt`)
- Police Montserrat : SIL Open Font License (`Plume/Resources/Fonts/Montserrat-OFL.txt`)
