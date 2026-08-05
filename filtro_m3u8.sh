#!/bin/bash

# ---------------------------------------------------------------------------
# Percorsi fissi
# ---------------------------------------------------------------------------

DESKTOP="$HOME/Desktop"
M3U8_INPUT="$DESKTOP/Playlist.m3u8"

# ---------------------------------------------------------------------------
# Verifica file sorgenti
# ---------------------------------------------------------------------------

if [ ! -f "$M3U8_INPUT" ]; then
    osascript - "$M3U8_INPUT" <<'AS'
on run argv
    display dialog "File non trovato:" & return & (item 1 of argv) buttons {"OK"} default button "OK" with icon stop with title "Filtro M3U8"
end run
AS
    exit 1
fi

# ---------------------------------------------------------------------------
# Selezione file lista tracce
# ---------------------------------------------------------------------------

LISTA_FILE=$(osascript <<'AS'
set f to choose file with prompt "Seleziona il file TXT con la lista tracce (Artista - Titolo):"
POSIX path of f
AS
)

if [ -z "$LISTA_FILE" ]; then
    osascript -e 'display dialog "Nessun file lista selezionato." buttons {"OK"} default button "OK" with icon stop with title "Filtro M3U8"'
    exit 1
fi

# ---------------------------------------------------------------------------
# Nome del file di output (solo nome, senza estensione)
# ---------------------------------------------------------------------------

NOME_OUTPUT=$(osascript <<'AS'
set risposta to text returned of (display dialog "Nome del file M3U8 risultante (senza estensione):" default answer "playlist_filtrata" buttons {"Annulla", "OK"} default button "OK" with title "Filtro M3U8")
risposta
AS
)

if [ -z "$NOME_OUTPUT" ]; then
    osascript -e 'display dialog "Nome non inserito." buttons {"OK"} default button "OK" with icon stop with title "Filtro M3U8"'
    exit 1
fi

M3U8_OUTPUT="$DESKTOP/${NOME_OUTPUT}.m3u8"
NOTFOUND_OUTPUT="$DESKTOP/${NOME_OUTPUT}_non_trovate.txt"

# ---------------------------------------------------------------------------
# File temporanei
# ---------------------------------------------------------------------------

TMP_LOG=$(mktemp /tmp/m3u8_log_XXXXXX.txt)

# ---------------------------------------------------------------------------
# Elaborazione con awk
# ---------------------------------------------------------------------------

awk \
    -v lista_file="$LISTA_FILE" \
    -v logfile="$TMP_LOG" \
    -v notfound_file="$NOTFOUND_OUTPUT" \
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
    gsub(/\.[Mm][Pp]3$/, "", b)
    return b
}

function word_overlap(a, b,    wa, wb, na, nb, i, j, common, total) {
    na = split(normalize(a), wa, " ")
    nb = split(normalize(b), wb, " ")
    common = 0
    total = na + nb
    if (total == 0) return 0
    for (i = 1; i <= na; i++) {
        if (length(wa[i]) < 3) continue
        for (j = 1; j <= nb; j++) {
            if (wa[i] == wb[j]) {
                common++
                break
            }
        }
    }
    return int(200 * common / total)
}

function do_match(ta, tt, fa, ft, wa, wt,    c, a1, t1, t1c, wt_n, wt_c, wa_n, score_t, score_a) {
    wa_n = normalize(wa)
    wt_n = normalize(wt)
    wt_c = normalize(clean_title(wt))

    for (c = 1; c <= 2; c++) {
        if (c == 1) { a1 = ta; t1 = tt }
        else        { a1 = fa; t1 = ft }
        if (t1 == "") continue
        a1  = normalize(a1)
        t1  = normalize(t1)
        t1c = normalize(clean_title( (c==1) ? tt : ft ))

        if (a1 == wa_n && t1 == wt_n)  return 1
        if (a1 == wa_n && t1c == wt_c) return 1
        if (wa_n != "" && (index(a1,wa_n)>0 || index(wa_n,a1)>0) && t1c == wt_c) return 1

        score_t = word_overlap(wt_c, t1c)
        score_a = (wa_n != "") ? word_overlap(wa_n, a1) : 80
        if (score_t >= 80 && score_a >= 50) return 1

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

# ---------------------------------------------------------------------------
# Riepilogo
# ---------------------------------------------------------------------------

LAST_LINE=$(tail -1 "$TMP_LOG")
N_MATCHED=$(echo "$LAST_LINE" | cut -d'|' -f1)
N_TOTAL=$(echo "$LAST_LINE" | cut -d'|' -f2)
N_NOT=$(( N_TOTAL - N_MATCHED ))

MSG="Operazione completata!

Tracce cercate:  $N_TOTAL
Trovate:         $N_MATCHED
Non trovate:     $N_NOT

File M3U8:  ${NOME_OUTPUT}.m3u8"

if [ "$N_NOT" -gt 0 ]; then
    MSG="$MSG
Non trovate: ${NOME_OUTPUT}_non_trovate.txt"
fi

osascript - "$MSG" <<'AS'
on run argv
    display dialog (item 1 of argv) buttons {"OK"} default button "OK" with icon note with title "Filtro M3U8 - Completato"
end run
AS

rm -f "$TMP_LOG"
exit 0