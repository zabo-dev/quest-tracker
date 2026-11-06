# Quest Tracker

Seite: https://zabo-dev.github.io/quest-tracker/

## Einrichten (Kumpel)
1. `git clone https://github.com/zabo-dev/quest-tracker`
2. Ordner `kit/WarlockPath` und `kit/QuestShare` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren, im Spiel beide aktivieren.
3. `kit\Quest-Sync starten.bat` doppelklicken, beim ersten Start den Token einfügen (wird lokal in `kit\token.txt` gespeichert, nie hochgeladen).
   Optional: `kit\Automatisch mit Windows starten.bat`.
4. Im Spiel `/wp sync`. Nach 1–2 Minuten zeigt die Seite den Abgleich.

Updates: `git pull`, danach die Addon-Ordner neu kopieren.
Details: `kit/LIESMICH.txt`

## Seite bearbeiten
`index.html` gehört euch: Design und Aufbau frei ändern, der Server überschreibt sie nicht mehr.
Der Server schreibt nur `data/state.json` (Aufbau steht oben in `index.html` als Kommentar).
Vor dem Bearbeiten `git pull`, weil der Server laufend `data/` aktualisiert.
