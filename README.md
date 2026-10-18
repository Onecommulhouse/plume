# Plume

App de dictée vocale pour Mac, faite par ONE COM.

Maintiens **Option droite**, parle, relâche : le texte s'écrit là où se trouve ton curseur, dans n'importe quelle app.

- **Transcription 100 % locale** avec Whisper (WhisperKit), la voix ne quitte jamais le Mac.
- **Mise au propre par Claude** (optionnelle) : ponctuation, hésitations retirées, corrections. Seul le texte est envoyé.
- **Tableau de bord** : mots dictés, vitesse, temps gagné, graphique des 14 derniers jours, répartition par app.
- **Historique** et **dictionnaire** de mots personnalisés (noms de clients, marques…).

## Installer

Télécharge [Plume.dmg](https://github.com/Onecommulhouse/plume/releases/latest/download/Plume.dmg), ouvre-le et glisse Plume dans Applications. C'est la seule installation à faire : ensuite, Plume se met à jour toute seule.

## Mises à jour automatiques

Chaque envoi sur `main` qui compile correctement devient une nouvelle version :

1. GitHub Actions compile Plume, la signe avec le certificat Developer ID de ONE COM et l'envoie à Apple pour notarisation.
2. `scripts/publish-update.sh` publie une *Release* GitHub avec le `.dmg`, une archive `.zip` signée (clé EdDSA, secret `SPARKLE_PRIVATE_KEY`) et `appcast.xml`. Les notes de version reprennent le message du commit.
3. Les Plume installées consultent `appcast.xml` toutes les heures (Sparkle), téléchargent la nouvelle version et se relancent d'elles-mêmes dès qu'aucune dictée n'est en cours.

Un commit qui contient `[skip ci]` ne publie rien.

La clé publique est inscrite dans `project.yml` (`SUPublicEDKey`). La clé privée n'existe que dans les secrets GitHub et dans une copie de sauvegarde : si elle est perdue, les Plume déjà installées refuseront les nouvelles versions.

Pour savoir où en est la notarisation chez Apple : onglet *Actions* → *Vérifier la notarisation* → *Run workflow*.

## Compilation

En local (Mac avec Xcode 26) :

```bash
brew install xcodegen
xcodegen generate
open Plume.xcodeproj
```

## Licences

- WhisperKit, Argmax : MIT (`LICENSES/WhisperKit-MIT.txt`)
- Sparkle, mises à jour automatiques : MIT (`LICENSES/Sparkle-MIT.txt`)
- Recherche de la touche de collage selon le clavier, adaptée d'OpenWhispr : MIT (`LICENSES/OpenWhispr-MIT.txt`)
- Police Montserrat : SIL Open Font License (`Plume/Resources/Fonts/Montserrat-OFL.txt`)
