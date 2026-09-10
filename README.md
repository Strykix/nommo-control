# Nommo Control

App macOS (SwiftUI) pour explorer et piloter en Bluetooth les enceintes Razer Nommo V2 Pro,
en particulier leur éclairage Chroma.

## À lire avant de commencer

Razer ne publie pas le protocole d'éclairage du Nommo V2 Pro, et Synapse n'existe pas sur
macOS. Cette app ne peut donc pas garantir que l'éclairage réagira : elle est conçue comme
un **outil de rétro-ingénierie utilisable**, pas comme un clone de Synapse.

Deux limites structurelles à connaître :

1. **CoreBluetooth ne voit que le Bluetooth Low Energy.** Si l'enceinte s'appaire comme
   périphérique audio classique (BR/EDR), elle n'apparaîtra pas dans le scan BLE. L'onglet
   « Bluetooth classique » liste alors les appareils appairés et leurs enregistrements SDP,
   ce qui permet de voir s'il existe un canal RFCOMM exploitable.
2. **Chez Razer, le Chroma passe habituellement par l'USB (HID).** Si c'est le cas ici,
   aucune commande Bluetooth ne pilotera les LED, et il faudra passer par l'USB — auquel cas
   la piste à suivre est le protocole implémenté par [OpenRazer](https://openrazer.github.io).

L'app permet de trancher empiriquement laquelle de ces situations est la vôtre.

## Construire et lancer

Nécessite macOS 13+ et les outils en ligne de commande Xcode.

Le code évite volontairement `@State` : dans les SDK récents c'est une macro dont le plugin
(`SwiftUIMacros`) est livré avec Xcode complet mais absent des Command Line Tools, ce qui
casse la compilation avec ces derniers seuls. Si une future modification en réintroduit une,
installez Xcode et pointez la toolchain dessus avec
`sudo xcode-select -s /Applications/Xcode.app`.

```bash
./scripts/build-app.sh
open ".build/Nommo Control.app"
```

Au premier lancement, macOS demande l'autorisation Bluetooth. Si le refus a été enregistré
par erreur : Réglages Système → Confidentialité et sécurité → Bluetooth.

## Comment s'en servir

**1. Trouver l'appareil.** Onglet latéral → *Scanner*. La case « Razer uniquement » filtre
sur le nom et sur l'identifiant constructeur Razer (`0x0157`) présent dans les trames
d'annonce. Si rien n'apparaît, décochez le filtre, puis regardez l'onglet
« Bluetooth classique ».

**2. Explorer.** Une fois connecté, l'onglet *Explorateur GATT* liste tous les services et
caractéristiques avec leurs propriétés. Les candidats intéressants sont les caractéristiques
inscriptibles hors services standard (Battery, Device Information, etc.) — typiquement un
service avec un UUID 128 bits propriétaire. Activez `notify` dessus : beaucoup de protocoles
propriétaires répondent, et ces réponses sont la meilleure source d'information.

**3. Envoyer.** L'onglet *Éclairage* propose deux encodages :

- **Rapport Razer (90 o)** — la trame HID utilisée par les périphériques Razer
  (`status`, `transaction_id`, `command_class`, `command_id`, arguments, CRC en XOR des
  octets 2 à 87). C'est l'hypothèse à tester en premier, car les appareils Razer qui
  exposent un canal BLE tunnellisent souvent cette même structure.
- **Modèle personnalisé** — une chaîne hexadécimale libre où `{R}`, `{G}`, `{B}` et
  `{BRIGHTNESS}` sont substitués à l'envoi. C'est ce que vous utiliserez une fois le vrai
  format identifié.

Tout le trafic est horodaté dans l'onglet *Journal*, copiable pour analyse.

## Structure

```
Sources/RazerNommoControl/
  RazerNommoControlApp.swift      point d'entrée SwiftUI
  Bluetooth/
    BluetoothManager.swift        CoreBluetooth : scan, connexion, lecture/écriture, journal
    ClassicBluetoothScanner.swift IOBluetooth : appareils classiques appairés + SDP
    Models.swift                  modèles de vue + encodage/décodage hexadécimal
  Lighting/
    RazerReport.swift             construction de la trame Razer 90 octets
    LightingController.swift      couleur/effet → octets
  Views/                          interface SwiftUI
```

## Pistes si le BLE ne donne rien

- Sniffer le trafic depuis un PC sous Synapse (Wireshark + USBPcap, ou un dongle BLE) pour
  capturer les vraies trames, puis les rejouer via le modèle personnalisé.
- Vérifier en USB : si le contrôleur se présente comme périphérique HID, `hidapi` permet
  d'envoyer les mêmes rapports Razer sans driver noyau sur macOS.
- Regarder ce qu'OpenRazer connaît déjà des identifiants produit Razer côté enceintes.

## État

Le code n'a pas été compilé : il a été écrit dans un environnement Linux sans toolchain
Swift ni matériel Bluetooth. Attendez-vous à d'éventuels ajustements au premier build.
