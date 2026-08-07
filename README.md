# Filtro M3U8

Script bash per macOS che filtra una playlist **M3U8** mantenendo solo le tracce presenti in una **lista testuale** di riferimento (formato `Artista - Titolo`). Utile ad esempio per estrarre da una playlist globale di Rekordbox esportata solo i brani di una scaletta specifica (es. tracklist DiscoClassic).

In questo modo è possibile creare delle nuove playlist in modo del tutto automatizzato senza selezionare le traccie singolarmente.

Lo script confronta ogni traccia della playlist sia con i **metadati del tag `#EXTINF`** sia con il **nome del file audio**, usando un matching fuzzy tollerante a maiuscole/minuscole, accenti, "feat.", "Radio Edit", anni tra parentesi, ecc.

---

## Cosa fa

1. Legge la playlist M3U8 di partenza ottenuta esportando la playlist globale di Rekordbox (All Tracks)
2. Legge un file di testo con la lista dei brani desiderati (uno per riga: `Artista - Titolo`).
3. Per ogni brano della lista, cerca una corrispondenza nella playlist (confrontando sia il tag `EXTINF` che il nome del file).
4. Scrive una nuova playlist M3U8 contenente solo le tracce trovate.
5. Genera un file di testo con l'elenco dei brani **non trovati**, se presenti.
6. Mostra un riepilogo finale (tracce cercate, trovate, percentuale, non trovate).

---

## Requisiti

- macOS (usa `osascript`/AppleScript per i dialog in modalità interattiva).
- `bash`, `awk` (preinstallati su macOS).
- Nessuna dipendenza esterna.

> Lo script funziona anche in modalità **non interattiva** (da terminale, cron, o richiamato da un altro tool), senza bisogno di macOS per la sola elaborazione awk — solo i dialog grafici richiedono `osascript`.

---

## Formato dei file

### Playlist M3U8 di ingresso

Formato standard M3U8 con tag `EXTINF`:

```
#EXTM3U
#EXTINF:180,Donna Summer - I Feel Love
/Music/Donna Summer - I Feel Love.mp3
#EXTINF:210,Chic - Le Freak
/Music/Chic - Le Freak (Radio Edit).mp3
```

### File lista tracce (TXT)

Un brano per riga, nel formato `Artista - Titolo`. Righe vuote o che iniziano con `#` vengono ignorate (utile per commenti):

```
# Tracklist puntata 12
Donna Summer - I Feel Love
Chic - Le Freak
Earth Wind Fire - September
```

Se manca l'artista, è sufficiente scrivere solo il titolo.

---

## Utilizzo

### Modalità interattiva (Automator / doppio click)

Se lanci lo script senza argomenti, viene chiesto tutto tramite finestre di dialogo macOS:

```bash
./filtro_m3u8.sh
```

Passi richiesti a schermo:

1. Verifica automatica che `~/Desktop/Playlist.m3u8` esista (percorso fisso di partenza).
2. Scelta del file TXT con la lista tracce (finestra "Seleziona file").
3. Inserimento del nome del file M3U8 risultante (senza estensione).
4. Se un file con lo stesso nome esiste già sul Desktop, viene chiesta conferma prima di sovrascriverlo.
5. Messaggio finale con il riepilogo dell'operazione.

**Uso con Automator:** importa lo script in un'azione "Esegui script shell" con shell `/bin/bash`, passaggio input "come argomenti" non necessario in modalità interattiva.

### Modalità da riga di comando (non interattiva)

Utile per automazioni, integrazioni con altri script, o Claude Code:

```bash
./filtro_m3u8.sh /percorso/Playlist.m3u8 /percorso/lista.txt nome_output
```

Argomenti posizionali:

| # | Argomento       | Descrizione                                              |
|---|-----------------|-----------------------------------------------------------|
| 1 | `M3U8_INPUT`    | Percorso della playlist M3U8 di partenza                  |
| 2 | `LISTA_FILE`    | Percorso del file TXT con la lista tracce                 |
| 3 | `NOME_OUTPUT`   | Nome (senza estensione) dei file di output                |

Se fornisci **tutti e tre** gli argomenti, lo script non apre nessuna finestra di dialogo, sovrascrive senza chiedere conferma, e stampa il riepilogo su stdout (utile per loggare in automazioni).

Esempio:

```bash
./filtro_m3u8.sh ~/Desktop/Playlist.m3u8 ~/Desktop/tracklist_puntata12.txt puntata12_filtrata
```

---

## Output generati (sul Desktop)

| File                                  | Contenuto                                             |
|----------------------------------------|--------------------------------------------------------|
| `<nome_output>.m3u8`                   | Playlist filtrata, solo con le tracce trovate           |
| `<nome_output>_non_trovate.txt`        | Elenco dei brani della lista **non** trovati nella playlist (creato solo se ce ne sono) |
| `<nome_output>_log.txt`                | Log dettagliato OK/NO per ogni brano (solo se `DEBUG=1`, vedi sotto) |

---

## Opzioni avanzate (variabili d'ambiente)

Puoi regolare il comportamento del matching senza modificare lo script, tramite variabili d'ambiente:

```bash
SOGLIA_TITOLO=85 SOGLIA_ARTISTA=60 ./filtro_m3u8.sh ~/Desktop/Playlist.m3u8 ~/Desktop/lista.txt output
```

| Variabile         | Default | Descrizione                                                                 |
|-------------------|---------|-------------------------------------------------------------------------------|
| `SOGLIA_TITOLO`   | `80`    | % minima di parole in comune sul titolo per considerarlo un match fuzzy       |
| `SOGLIA_ARTISTA`  | `50`    | % minima di parole in comune sull'artista per considerarlo un match fuzzy     |
| `MIN_LEN_PAROLA`  | `3`     | Lunghezza minima (caratteri) di una parola per essere considerata nel confronto fuzzy. Abbassa a `2` se le tue tracklist contengono spesso sigle brevi (es. "DJ", "Mr") |
| `DEBUG`           | `0`     | Se impostato a `1`, salva il log dettagliato di ogni match/non-match in `<nome_output>_log.txt` sul Desktop, invece di eliminarlo a fine esecuzione |

Esempio con log di debug attivo:

```bash
DEBUG=1 ./filtro_m3u8.sh ~/Desktop/Playlist.m3u8 ~/Desktop/lista.txt output
```

---

## Come funziona il matching (in breve)

Per ogni brano della lista, lo script confronta sia i metadati `EXTINF` sia il nome del file, applicando in cascata:

1. **Match esatto** — artista e titolo normalizzati (minuscolo, senza accenti) sono identici.
2. **Match su titolo "pulito"** — uguale a (1), ma ignorando anno tra parentesi, "feat.", "Radio Edit", "Remix", "Lyrics/Testo", ecc.
3. **Match con artista in sottostringa** — es. "Chic" combacia con "Chic featuring Alfa" se il titolo pulito coincide.
4. **Match fuzzy per overlap di parole** — se almeno l'`SOGLIA_TITOLO`% delle parole del titolo e l'`SOGLIA_ARTISTA`% delle parole dell'artista coincidono.
5. **Fallback per sottostringa reciproca** — ultima rete di sicurezza per titoli/artisti troncati o abbreviati.

Se nessuna delle 5 strategie produce un match, il brano finisce nell'elenco "non trovate".

---

## Note e limiti conosciuti

- La normalizzazione degli accenti copre i principali caratteri latini ed europei (incluse ø/å); alfabeti non latini (cirillico, ecc.) non vengono trascritti.
- Il primo brano della lista che soddisfa il match "vince": se la playlist contiene due versioni diverse dello stesso brano (es. originale + remix con lo stesso titolo pulito), viene selezionata la prima trovata in ordine di playlist.
- Se il nome del file di output contiene caratteri come `/`, `\` o `:`, questi vengono rimossi automaticamente per sicurezza.
- Estensioni audio riconosciute nel nome file: `mp3, flac, wav, m4a, aac, ogg, wma, aiff/aif, alac, opus`.

---

## Risoluzione problemi

| Sintomo                                      | Possibile causa / soluzione                                                             |
|-----------------------------------------------|--------------------------------------------------------------------------------------------|
| "File non trovato" all'avvio                  | Verifica il percorso della playlist M3U8 (default `~/Desktop/Playlist.m3u8`)              |
| Troppi falsi negativi (brani presenti ma non trovati) | Abbassa `SOGLIA_TITOLO`/`SOGLIA_ARTISTA`, oppure attiva `DEBUG=1` e controlla il log per capire dove si ferma il match |
| Troppi falsi positivi (brani sbagliati abbinati) | Aumenta le soglie, o verifica che titoli molto brevi non vengano confusi tra loro          |
| Lo script si blocca sulla scelta del file      | Assicurati di avere i permessi di Automazione/Accessibilità per Terminale/Script Editor in Preferenze di Sistema → Privacy e Sicurezza |
