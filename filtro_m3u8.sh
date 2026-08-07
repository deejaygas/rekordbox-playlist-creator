#!/bin/bash

# ---------------------------------------------------------------------------
# Filtro M3U8 - filtra una playlist M3U8 in base a una lista tracce
#              (Artista - Titolo) fornita in un file di testo.
#
# Uso interattivo (Automator/doppio click):
#   ./filtro_m3u8.sh
#
# Uso da riga di comando (automazioni, Claude Code, cron, ecc.):
#   ./filtro_m3u8.sh /percorso/Playlist.m3u8 /percorso/lista.txt nome_output
#
# Se uno o più argomenti non vengono forniti, lo script chiede
# interattivamente tramite dialog di macOS (comportamento originale).
# ---------------------------------------------------------------------------

set -o pipefail

# ---------------------------------------------------------------------------
# Parametri di matching (soglie regolabili senza toccare la logica awk)
# ---------------------------------------------------------------------------

SOGLIA_TITOLO="${SOGLIA_TITOLO:-80}"     # % overlap parole minimo sul titolo
SOGLIA_ARTISTA="${SOGLIA_ARTISTA:-50}"   # % overlap parole minimo sull'artista
MIN_LEN_PAROLA="${MIN_LEN_PAROLA:-3}"    # lunghezza minima parola considerata nel matching

# Se impostato a 1, il file di log dettagliato viene conservato sul Desktop
# invece di essere eliminato a fine esecuzione.
DEBUG="${DEBUG:-0}"

# ---------------------------------------------------------------------------
# Percorsi fissi
# ---------------------------------------------------------------------------

DESKTOP="$HOME/Desktop"

# ---------------------------------------------------------------------------
# Funzione di utilità per mostrare un dialog di errore ed uscire
# ---------------------------------------------------------------------------

errore_e_esci() {
    local msg="$1"
    osascript - "$msg" <<'AS'
on run argv
    display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon stop with title "Filtro M3U8"
end run
AS
    exit 1
}

# ---------------------------------------------------------------------------
# Input: da argomenti CLI se presenti, altrimenti via dialog interattivi
# ---------------------------------------------------------------------------

M3U8_INPUT="${1:-$DESKTOP/Playlist.m3u8}"
LISTA_FILE="${2:-}"
NOME_OUTPUT="${3:-}"

MODALITA_CLI=0
if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then
    MODALITA_CLI=1
fi

# --- Verifica file M3U8 sorgente -------------------------------------------

if [ ! -f "$M3U8_INPUT" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: file non trovato: $M3U8_INPUT" >&2
        exit 1
    fi
    errore_e_esci "File non trovato:
$M3U8_INPUT"
fi

# --- Selezione file lista tracce (solo se non passato da CLI) --------------

if [ -z "$LISTA_FILE" ]; then
    LISTA_FILE=$(osascript <<'AS'
set f to choose file with prompt "Seleziona il file TXT con la lista tracce (Artista - Titolo):"
POSIX path of f
AS
)
fi

if [ -z "$LISTA_FILE" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: nessun file lista tracce specificato." >&2
        exit 1
    fi
    errore_e_esci "Nessun file lista selezionato."
fi

if [ ! -f "$LISTA_FILE" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: file lista non trovato: $LISTA_FILE" >&2
        exit 1
    fi
    errore_e_esci "File lista non trovato:
$LISTA_FILE"
fi

# --- Nome del file di output (solo nome, senza estensione) ------------------

if [ -z "$NOME_OUTPUT" ]; then
    NOME_OUTPUT=$(osascript <<'AS'
set risposta to text returned of (display dialog "Nome del file M3U8 risultante (senza estensione):" default answer "playlist_filtrata" buttons {"Annulla", "OK"} default button "OK" with title "Filtro M3U8")
risposta
AS
)
fi

if [ -z "$NOME_OUTPUT" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: nome file di output non specificato." >&2
        exit 1
    fi
    errore_e_esci "Nome non inserito."
fi

# --- Sanificazione del nome output (evita path traversal / caratteri illegali) ---

NOME_OUTPUT=$(printf '%s' "$NOME_OUTPUT" | tr -d '/\\:' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if [ -z "$NOME_OUTPUT" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: nome file di output non valido dopo la sanificazione." >&2
        exit 1
    fi
    errore_e_esci "Nome file non valido."
fi

M3U8_OUTPUT="$DESKTOP/${NOME_OUTPUT}.m3u8"
NOTFOUND_OUTPUT="$DESKTOP/${NOME_OUTPUT}_non_trovate.txt"
LOG_OUTPUT="$DESKTOP/${NOME_OUTPUT}_log.txt"

# --- Conferma sovrascrittura se il file di output esiste già ---------------

if [ -f "$M3U8_OUTPUT" ]; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Attenzione: $M3U8_OUTPUT esiste già e verrà sovrascritto." >&2
    else
        RISPOSTA=$(osascript <<AS
set risposta to button returned of (display dialog "Il file ${NOME_OUTPUT}.m3u8 esiste già sul Desktop.
Sovrascriverlo?" buttons {"Annulla", "Sovrascrivi"} default button "Annulla" with icon caution with title "Filtro M3U8")
risposta
AS
)
        if [ "$RISPOSTA" != "Sovrascrivi" ]; then
            exit 0
        fi
    fi
fi

# ---------------------------------------------------------------------------
# File temporanei + pulizia automatica anche in caso di errore/uscita anticipata
# ---------------------------------------------------------------------------

TMP_LOG=$(mktemp /tmp/m3u8_log_XXXXXX.txt) || {
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore: impossibile creare il file temporaneo di log." >&2
        exit 1
    fi
    errore_e_esci "Impossibile creare il file temporaneo di log."
}

cleanup() {
    if [ "$DEBUG" -eq 1 ]; then
        cp -f "$TMP_LOG" "$LOG_OUTPUT" 2>/dev/null
    fi
    rm -f "$TMP_LOG"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Elaborazione con awk
# ---------------------------------------------------------------------------

awk \
    -v lista_file="$LISTA_FILE" \
    -v logfile="$TMP_LOG" \
    -v notfound_file="$NOTFOUND_OUTPUT" \
    -v soglia_titolo="$SOGLIA_TITOLO" \
    -v soglia_artista="$SOGLIA_ARTISTA" \
    -v min_len_parola="$MIN_LEN_PAROLA" \
'
function to_lower(s,    i,c,out) {
    out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c >= "A" && c <= "Z") c = tolower(c)
        out = out c
    }
    return out
}

function normalize(s,    r) {
    r = to_lower(s)
    gsub(/[àáâä]/, "a", r)
    gsub(/[èéêë]/, "e", r)
    gsub(/[ìíîï]/, "i", r)
    gsub(/[òóôö]/, "o", r)
    gsub(/[ùúûü]/, "u", r)
    gsub(/[ç]/,    "c", r)
    gsub(/[ñ]/,    "n", r)
    gsub(/[øØ]/,   "o", r)
    gsub(/[åÅ]/,   "a", r)
    gsub(/[–—]/,   "-", r)
    gsub(/[ \t]+/, " ", r)
    gsub(/^[ \t]+|[ \t]+$/, "", r)
    return r
}

function clean_title(t,    r) {
    r = t
    gsub(/[ \t]*-[ \t]*[0-9][0-9][0-9][0-9][ \t]*$/, "", r)
    gsub(/[ \t]*\([0-9][0-9][0-9][0-9]\)[ \t]*$/, "", r)
    gsub(/[ \t]*\([Tt]esto[\/]?[Ll]yrics?\)/, "", r)
    gsub(/[ \t]*\([Ll]yrics?[\/]?[Tt]esto\)/, "", r)
    gsub(/[ \t]*\([Ll]yrics?\)/, "", r)
    gsub(/[Cc]on [Tt]esto/, "", r)
    gsub(/[ \t]*-[ \t]*[Rr]adio [Ee]dit[ \t]*$/, "", r)
    gsub(/[ \t]*-[ \t]*[Ss]hort[ \t]*$/, "", r)
    gsub(/[ \t]*-[ \t]*[Ss]mall [Mm]ix[ \t]*$/, "", r)
    gsub(/[ \t]*-[ \t]*[Rr]emix[ \t]*$/, "", r)
    gsub(/[ \t]*-[ \t]*[Vv]ersion[ \t]*$/, "", r)
    gsub(/[ \t]*[Ff]eat\.[^)]*/, "", r)
    gsub(/[ \t]*[Ff]t\.[^)]*/, "", r)
    gsub(/^[ \t]+|[ \t]+$/, "", r)
    return r
}

function split_at(line, parts,    idx, raw, a, t) {
    raw = line
    gsub(/^[ \t]*-[ \t]*/, "", raw)
    idx = index(raw, " - ")
    if (idx > 0) {
        a = substr(raw, 1, idx - 1)
        t = substr(raw, idx + 3)
    } else {
        a = ""
        t = raw
    }
    gsub(/^[ \t]+|[ \t]+$/, "", a)
    gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (index(a, "/") > 0)
        a = substr(a, 1, index(a, "/") - 1)
    gsub(/^[ \t]+|[ \t]+$/, "", a)
    parts[1] = a
    parts[2] = t
}

function basename_noext(path,    b, i) {
    b = path
    while ((i = index(b, "/")) > 0) b = substr(b, i + 1)
    gsub(/\.[Mm][Pp]3$/, "", b)
    gsub(/\.[Ff][Ll][Aa][Cc]$/, "", b)
    gsub(/\.[Ww][Aa][Vv]$/, "", b)
    gsub(/\.[Mm]4[Aa]$/, "", b)
    gsub(/\.[Aa][Aa][Cc]$/, "", b)
    gsub(/\.[Oo][Gg][Gg]$/, "", b)
    gsub(/\.[Ww][Mm][Aa]$/, "", b)
    gsub(/\.[Aa][Ii][Ff][Ff]?$/, "", b)
    gsub(/\.[Aa][Ll][Aa][Cc]$/, "", b)
    gsub(/\.[Oo][Pp][Uu][Ss]$/, "", b)
    return b
}

# Percentuale di parole (di lunghezza >= min_len_parola) in comune tra due stringhe.
function word_overlap(a, b,    wa, wb, na, nb, i, j, common, total) {
    na = split(normalize(a), wa, " ")
    nb = split(normalize(b), wb, " ")
    common = 0
    total = na + nb
    if (total == 0) return 0
    for (i = 1; i <= na; i++) {
        if (length(wa[i]) < min_len_parola) continue
        for (j = 1; j <= nb; j++) {
            if (wa[i] == wb[j]) {
                common++
                break
            }
        }
    }
    return int(200 * common / total)
}

# Confronta la traccia della playlist (tag EXTINF "ta/tt" e nome file "fa/ft")
# con una voce della lista desiderata (wa/wt), usando 4 strategie in cascata,
# dalla piu' stringente alla piu' permissiva.
function do_match(ta, tt, fa, ft, wa, wt,    c, a1, t1, t1c, wt_n, wt_c, wa_n, score_t, score_a) {
    wa_n = normalize(wa)
    wt_n = normalize(wt)
    wt_c = normalize(clean_title(wt))

    # c=1 -> confronta con i metadati del tag EXTINF
    # c=2 -> confronta con artista/titolo derivati dal nome del file
    for (c = 1; c <= 2; c++) {
        if (c == 1) { a1 = ta; t1 = tt }
        else        { a1 = fa; t1 = ft }
        if (t1 == "") continue
        a1  = normalize(a1)
        t1  = normalize(t1)
        t1c = normalize(clean_title( (c==1) ? tt : ft ))

        # 1) match esatto su artista e titolo normalizzati
        if (a1 == wa_n && t1 == wt_n)  return 1

        # 2) match esatto su artista e titolo "pulito" (senza feat/remix/anno/ecc.)
        if (a1 == wa_n && t1c == wt_c) return 1

        # 3) match su titolo pulito con artista in relazione di sottostringa
        if (wa_n != "" && (index(a1,wa_n)>0 || index(wa_n,a1)>0) && t1c == wt_c) return 1

        # 4) match fuzzy: percentuale di parole in comune sopra soglia
        score_t = word_overlap(wt_c, t1c)
        score_a = (wa_n != "") ? word_overlap(wa_n, a1) : 80
        if (score_t >= soglia_titolo && score_a >= soglia_artista) return 1

        # 5) fallback: sottostringa reciproca su titolo e artista puliti
        if (length(wt_c) > 4 && length(t1c) > 4) {
            if ((index(a1,wa_n)>0 || index(wa_n,a1)>0) &&
                (index(t1c,wt_c)>0 || index(wt_c,t1c)>0)) return 1
        }
    }
    return 0
}

BEGIN {
    n_wanted = 0
    while ((getline line < lista_file) > 0) {
        gsub(/\r/, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line == "" || substr(line,1,1) == "#") continue
        split_at(line, p)
        n_wanted++
        w_artist[n_wanted] = p[1]
        w_title[n_wanted]  = p[2]
        found[n_wanted]    = 0
    }
    close(lista_file)
    n_matched   = 0
    header_done = 0
    extinf      = ""
    cur_path    = ""
    header_line = "#EXTM3U"
}

/^#EXTM3U/ {
    header_line = $0
    next
}

/^#EXTINF:/ {
    extinf = $0
    next
}

!/^#/ && extinf != "" {
    cur_path = $0
    gsub(/\r/, "", cur_path)

    tag_raw = extinf
    sub(/^#EXTINF:[0-9]+,/, "", tag_raw)
    gsub(/^[ \t]*-[ \t]*/, "", tag_raw)
    split_at(tag_raw, pt)
    ta = pt[1]; tt = pt[2]

    bn = basename_noext(cur_path)
    split_at(bn, pf)
    fa = pf[1]; ft = pf[2]

    for (i = 1; i <= n_wanted; i++) {
        if (!found[i] && do_match(ta, tt, fa, ft, w_artist[i], w_title[i])) {
            if (!header_done) {
                print header_line
                header_done = 1
            }
            print extinf
            print cur_path
            found[i] = 1
            n_matched++
            print "OK|" w_artist[i] " - " w_title[i] "|" cur_path >> logfile
            break
        }
    }
    extinf   = ""
    cur_path = ""
    next
}

END {
    for (i = 1; i <= n_wanted; i++) {
        if (!found[i]) {
            label = (w_artist[i] != "") ? w_artist[i] " - " w_title[i] : w_title[i]
            print label >> notfound_file
            print "NO|" label >> logfile
        }
    }
    print n_matched "|" n_wanted >> logfile
}
' "$M3U8_INPUT" > "$M3U8_OUTPUT"

AWK_STATUS=$?

if [ "$AWK_STATUS" -ne 0 ]; then
    rm -f "$M3U8_OUTPUT"
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Errore durante l'elaborazione awk (codice $AWK_STATUS)." >&2
        exit 1
    fi
    errore_e_esci "Errore durante l'elaborazione (awk).
Nessun file è stato generato."
fi

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------

LAST_LINE=$(tail -1 "$TMP_LOG" 2>/dev/null)

if ! printf '%s' "$LAST_LINE" | grep -qE '^[0-9]+\|[0-9]+$'; then
    if [ "$MODALITA_CLI" -eq 1 ]; then
        echo "Attenzione: log di riepilogo non valido o assente." >&2
        exit 1
    fi
    errore_e_esci "Elaborazione terminata ma il riepilogo non è disponibile.
Controlla manualmente il file generato: ${NOME_OUTPUT}.m3u8"
fi

N_MATCHED=$(printf '%s' "$LAST_LINE" | cut -d'|' -f1)
N_TOTAL=$(printf '%s' "$LAST_LINE" | cut -d'|' -f2)
N_NOT=$(( N_TOTAL - N_MATCHED ))

if [ "$N_TOTAL" -gt 0 ]; then
    PERCENTUALE=$(( 100 * N_MATCHED / N_TOTAL ))
else
    PERCENTUALE=0
fi

MSG="Operazione completata!

Tracce cercate:  $N_TOTAL
Trovate:         $N_MATCHED ($PERCENTUALE%)
Non trovate:     $N_NOT

File M3U8:  ${NOME_OUTPUT}.m3u8"

if [ "$N_NOT" -gt 0 ]; then
    MSG="$MSG
Non trovate: ${NOME_OUTPUT}_non_trovate.txt"
fi

if [ "$MODALITA_CLI" -eq 1 ]; then
    echo "$MSG"
else
    osascript - "$MSG" <<'AS'
on run argv
    display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon note with title "Filtro M3U8 - Completato"
end run
AS
fi

exit 0
