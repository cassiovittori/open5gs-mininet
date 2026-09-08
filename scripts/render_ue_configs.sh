#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$REPO_ROOT/configs/runtime"

shopt -s nullglob
ue_files=("$RUNTIME_DIR"/ue*.yaml)
if [[ ${#ue_files[@]} -eq 0 ]]; then
  echo "[render] Nenhum ue*.yaml em $RUNTIME_DIR — rode scripts/render_slice_configs.py primeiro."
  exit 1
fi

# O gNB e dual-homed (core + acesso). Um `range` sobre .Networks concatenaria os dois
# IPs numa string so ("10.33.33.1810.34.0.5") sem dar erro, e o UE nunca acharia o gNB.
# Os UEs falam com a perna de ACESSO, entao o indice da rede tem que ser explicito.
ACCESS_NETWORK="${FAIR5G_ACCESS_NETWORK:-fair5g-access}"
GNB_IP="$(sudo docker inspect -f "{{index .NetworkSettings.Networks \"$ACCESS_NETWORK\" \"IPAddress\"}}" gnb)"
if [[ -z "$GNB_IP" ]]; then
  echo "[render] Não consegui obter IP do container gnb."
  exit 1
fi

echo "[render] gnb ip: $GNB_IP"

patch_gnb_search_list () {
  local target="$1"
  local tmp="${target}.tmp"

  # substitui bloco gnbSearchList por um único item (ip do gnb)
  awk -v ip="$GNB_IP" '
    BEGIN {inlist=0}
    /^gnbSearchList:/ {
      print "gnbSearchList:"
      print "  - " ip
      inlist=1
      next
    }
    inlist==1 {
      # pula linhas de lista (começam com espaço + "-")
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) next
      # se acabou a lista, volta a imprimir normalmente
      inlist=0
    }
    {print}
  ' "$target" > "$tmp"
  mv "$tmp" "$target"
}

for f in "${ue_files[@]}"; do
  patch_gnb_search_list "$f"
  echo "[render] atualizado: $f"
done
