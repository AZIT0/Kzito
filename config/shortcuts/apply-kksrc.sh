#!/usr/bin/env bash
# Aplica shortcuts/config.kksrc ([comp][Global Shortcuts]) vía D-Bus.
# Solo shell + gdbus. Compara contra el estado EN VIVO (el demonio no
# persiste al archivo hasta cerrar sesión). Dos fases: liberar, asignar.
# Omite [StandardShortcuts] (son por app). Uso: apply-kksrc.sh [config.kksrc]
set -uo pipefail

KKSRC="${1:-$(cd "$(dirname "$0")" && pwd)/config.kksrc}"
CURRENT=~/.config/kglobalshortcutsrc
DEST=org.kde.kglobalaccel
OBJ=/kglobalaccel
M=org.kde.KGlobalAccel

declare -A SECFRIEND wanting
comp=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^\[.*\]$ && "$line" != *"="* ]]; then
    sec="${line##*[}"; sec="${sec%]}"
    comp="$sec"
  elif [[ -n "$comp" && "$line" == *"="* ]]; then
    k="${line%%=*}"; v="${line#*=}"
    [[ "$k" == "_k_friendly_name" ]] && SECFRIEND["$comp"]="$v" || wanting["$comp|$k"]="$v"
  fi
done < "$CURRENT"

declare -A WANT
wcomp=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  if [[ "$line" =~ ^\[(.+)\]\[Global\ Shortcuts\]$ ]]; then
    wcomp="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^\[.*\]$ ]]; then
    wcomp=""
  elif [[ -n "$wcomp" && "$line" == *"="* ]]; then
    WANT["$wcomp|${line%%=*}"]="${line#*=}"
  fi
done < "$KKSRC"

# "Meta+Shift+Q" -> int Qt. Falla (1) si no codificable.
key_int() {
  local combo="$1" mods=0 key="" part
  [[ "$combo" == "Meta" ]] && { echo 16777250; return 0; }
  IFS='+' read -ra parts <<< "$combo"
  for part in "${parts[@]}"; do
    case "$part" in
      Meta) mods=$((mods | 0x10000000)) ;;
      Ctrl) mods=$((mods | 0x04000000)) ;;
      Shift) mods=$((mods | 0x02000000)) ;;
      Alt) mods=$((mods | 0x08000000)) ;;
      Return) key=0x01000004 ;;
      Enter) key=0x01000005 ;;
      Tab) key=0x01000003 ;;
      F[0-9]|F[0-9][0-9])
        num="${part#F}"; key=$((0x01000030 + num)) ;;
      *)
        if [[ ${#part} -eq 1 ]]; then
          [[ "$part" =~ [a-z] ]] && part="${part^}"
          key=$(printf '%d' "'$part")
        else
          return 1
        fi ;;
    esac
  done
  [[ -z "$key" ]] && return 1
  echo $((mods | key))
}

gcall() { gdbus call --session --dest "$DEST" --object-path "$OBJ" --method "$M.$1" "${@:2}"; }

declare -A COMPFCACHE
comp_friendly() { # unique -> friendly (cacheado)
  local comp="$1"
  if [[ -z "${COMPFCACHE[$comp]+x}" ]]; then
    local f
    f=$(gcall allMainComponents 2>/dev/null | tr ',' '\n' | grep -A1 -F "'$comp'" | tail -n 1 | tr -d " ']}\t")
    COMPFCACHE["$comp"]="$f"
  fi
  echo "${COMPFCACHE[$comp]}"
}

owner_ok() { # key comp action
  gcall action "$1" 2>/dev/null | grep -qF "'$2', '$3'"
}

# claves en vivo de una acción -> "1 2 3" (vacío si ninguna)
live_keys() { # comp action compf friendly
  local out
  out=$(gcall shortcut "['$1', '$2', '$3', '$4']" 2>/dev/null) || { echo ""; return; }
  echo "$out" | grep -o '[0-9]\+' | tr '\n' ' '
}

changed=0; skipped=0
declare -a warned=() clears=() sets=()
for id in "${!WANT[@]}"; do
  comp="${id%%|*}"; action="${id#*|}"
  value="${WANT[$id]}"
  if [[ -z "${wanting[$id]+x}" ]]; then
    if [[ -n "${value// }" ]]; then
      # registrado pero sin entrada en archivo: friendly real por D-Bus
      cf=$(comp_friendly "$comp")
      if [[ -z "$cf" ]]; then
        warned+=("$comp/$action: app no registrada, abrila y reintentá"); continue
      fi
      if [[ "$action" == "_launch" ]]; then
        af="${comp%.desktop}"; af="${af#org.kde.}"; af="${af^}"
      else
        af="$action"
      fi
      wanting["$id"]="x,x,$af"
      SECFRIEND["$comp"]="$cf"
    else
      continue
    fi
  fi
  # codificar deseado
  keys=(); ok=1
  if [[ -n "${value// }" ]]; then
    IFS=';' read -ra alts <<< "$value"
    for a in "${alts[@]}"; do
      a="$(echo "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      k=$(key_int "$a") || { ok=0; break; }
      keys+=("$k")
    done
  fi
  if [[ $ok -eq 0 ]]; then
    # si el archivo ya trae lo mismo, es equivalente: omitir sin ruido
    raw="${wanting[$id]:-}"
    if [[ -n "$raw" ]]; then
      if [[ "$raw" == *","* ]]; then fcur="${raw#*,}"; fcur="${fcur%%,*}"; else fcur="$raw"; fi
      norm() { echo "$1" | sed 's/\\t/;/g' | tr ';' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sort | tr '\n' ';'; }
      if [[ "$(norm "$fcur")" == "$(norm "$value")" ]]; then
        skipped=$((skipped + 1)); continue
      fi
    fi
    warned+=("$comp/$action: tecla especial, omitido ($value)"); continue
  fi
  # friendly reales (del archivo o estimados)
  raw="${wanting[$id]:-}"
  friendly="${raw#*,*,}"
  compf="${SECFRIEND[$comp]:-$comp}"
  live=$(live_keys "$comp" "$action" "$compf" "$friendly")
  want_sorted=$(printf '%s\n' "${keys[@]:-}" | sort -n | tr '\n' ' ')
  live_sorted=$(printf '%s\n' $live | sort -n | tr '\n' ' ' 2>/dev/null)
  if [[ "$want_sorted" == "$live_sorted" ]]; then
    skipped=$((skipped + 1)); continue
  fi
  keylist=$(IFS=,; echo "[${keys[*]}]")
  if [[ ${#keys[@]} -eq 0 ]]; then
    clears+=("$comp|$action|$compf|$friendly")
  else
    sets+=("$comp|$action|$compf|$friendly|$keylist")
  fi
done

if [[ ${#clears[@]} -gt 0 ]]; then
for op in "${clears[@]}"; do
  IFS='|' read -r c a cf af <<< "$op"
  if gcall setForeignShortcut "['$c', '$a', '$cf', '$af']" "[]" >/dev/null 2>&1; then
    changed=$((changed + 1))
  else
    warned+=("$c/$a: D-Bus rechazo el cambio")
  fi
done
fi
if [[ ${#sets[@]} -gt 0 ]]; then
for op in "${sets[@]}"; do
  IFS='|' read -r c a cf af kl <<< "$op"
  if gcall setForeignShortcut "['$c', '$a', '$cf', '$af']" "$kl" >/dev/null 2>&1; then
    changed=$((changed + 1))
  else
    warned+=("$c/$a: D-Bus rechazo el cambio")
  fi
done
fi

echo "Aplicados: $changed | sin cambios: $skipped"
if [[ ${#warned[@]} -gt 0 ]]; then
for w in "${warned[@]}"; do echo "AVISO: $w"; done
fi
