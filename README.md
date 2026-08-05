# Filtro M3U8

Script bash per macOS che filtra una playlist M3U8 tenendo solo le tracce presenti in una lista testuale (formato `Artista - Titolo`), usando un matching "fuzzy" per gestire differenze di formattazione, feat., remix, anni, ecc. Produce una nuova playlist M3U8 con solo i brani trovati e un file di testo con quelli non trovati.

## Cosa fa

1. Cerca sul Desktop il file `Playlist.m3u8` (percorso fisso) e verifica che esista.
2. Chiede di selezionare un file `.txt` contenente la lista dei brani desiderati, uno per riga, nel formato `Artista - Titolo`.
3. Chiede il nome (senza estensione) da dare al file M3U8 di output.
4. Per ogni traccia della playlist di partenza (`#EXTINF` + percorso file), confronta artista/titolo — sia quelli dichiarati nel tag `#EXTINF`, sia quelli ricavati dal nome del file — con ogni voce della lista desiderata, usando più criteri di corrispondenza (vedi sotto).
5. Scrive in un nuovo file M3U8 solo le tracce che hanno trovato una corrispondenza.
6. Scrive in un file di testo separato le voci della lista che **non** sono state trovate nella playlist.
7. Mostra un dialog di riepilogo con il numero di tracce cercate, trovate e non trovate.

## Logica di matching

Lo script normalizza il testo (minuscolo, accenti rimossi, spazi ripuliti) e "ripulisce" i titoli da elementi che spesso variano tra le fonti:
- anni tra parentesi o in coda (es. `- 1998`, `(1998)`)
- indicazioni come `(Testo)`, `(Lyrics)`, `Con Testo`
- suffissi come `Radio Edit`, `Short`, `Small Mix`, `Remix`, `Version`
- featuring (`feat.` / `ft.`)

Una traccia è considerata trovata se si verifica **una qualsiasi** di queste condizioni (confrontando sia i dati del tag `#EXTINF` sia quelli ricavati dal nome file):
- artista e titolo coincidono esattamente (dopo normalizzazione)
- artista coincide e il titolo "ripulito" coincide
- l'artista è contenuto nell'altro (o viceversa) e il titolo ripulito coincide
- punteggio di sovrapposizione parole: titolo ≥ 80% e artista ≥ 50% (parole di almeno 3 caratteri)
- artista e titolo ripulito sono uno contenuto nell'altro, per titoli/testi più lunghi di 4 caratteri

## Requisiti

- **macOS** (usa `osascript` per i dialog) con `awk` e `bash` (preinstallati di sistema)
- Un file `Playlist.m3u8` presente sul **Desktop** dell'utente
- Un file di testo con la lista dei brani desiderati, una riga per brano, nel formato:
  ```
  Artista - Titolo
  ```
  Le righe vuote o che iniziano con `#` vengono ignorate.

## Utilizzo

```bash
chmod +x filtro_m3u8.sh
./filtro_m3u8.sh
```

1. Se `~/Desktop/Playlist.m3u8` non esiste, viene mostrato un errore e lo script termina.
2. Seleziona il file `.txt` con la lista dei brani da cercare.
3. Inserisci il nome (senza estensione) per il file M3U8 risultante (default: `playlist_filtrata`).
4. Attendi l'elaborazione (gestita da `awk`, senza output a schermo durante il processo).
5. Alla fine appare un dialog con il riepilogo: tracce cercate, trovate, non trovate.

## Output

Tutti i file vengono salvati sul **Desktop**:
- `<nome_scelto>.m3u8` — playlist filtrata, contenente solo le tracce trovate (con relativo tag `#EXTINF` e percorso file originale).
- `<nome_scelto>_non_trovate.txt` — elenco (uno per riga, `Artista - Titolo`) delle voci della lista non trovate nella playlist di partenza. Viene creato solo se ci sono effettivamente brani non trovati.

## Note e limiti

- Il percorso del file M3U8 di input è fisso (`~/Desktop/Playlist.m3u8`): per usare un file diverso, va rinominato/spostato oppure modificata la variabile `M3U8_INPUT` nello script.
- Il matching è euristico: con librerie molto ampie o titoli molto simili tra loro (es. cover, remix diversi dello stesso brano) può produrre falsi positivi o mancare corrispondenze corrette.
- Ogni traccia della playlist di partenza può soddisfare al massimo una voce della lista desiderata (il primo match trovato "consuma" la voce, tramite il flag `found[i]`).
- Il formato atteso per `#EXTINF` è quello standard `#EXTINF:durata,Artista - Titolo`; tag con formati diversi potrebbero non essere interpretati correttamente.
- Il file di log temporaneo (`/tmp/m3u8_log_*.txt`) viene rimosso automaticamente a fine esecuzione.
