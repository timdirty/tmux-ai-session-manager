# ═══════════════════════════════════════════════════════════════════
# tmux 工作流整合  （Claude Code / Codex 感知版）
#   ta  — 全功能 session picker（ctrl-n/d/r/x）
#   tn  — 快速新建命名 session
#   tk  — 快速刪除 session
#   tc  — 建 session + 自動開 claude（一鍵工作流）
# ═══════════════════════════════════════════════════════════════════

ta() {
  command -v fzf &>/dev/null || { echo "需要 fzf：brew install fzf" >&2; return 1; }

  # ── tmux server 未啟動 ──
  if ! tmux info &>/dev/null 2>&1; then
    printf "tmux 未啟動，開新 session？[名稱/Enter 取消] "
    read -r _n; [[ -n "$_n" ]] && tmux new-session -s "$_n"; return
  fi

  # ── 無任何 session → 建立 ──
  if ! tmux list-sessions &>/dev/null 2>&1; then
    printf "無 session，名稱（Enter 用 main）: "
    read -r _n; _n="${_n:-main}"
    [[ -n "$TMUX" ]] \
      && tmux new-session -d -s "$_n" -c "$PWD" && tmux switch-client -t "$_n" \
      || tmux new-session -s "$_n" -c "$PWD"
    return
  fi

  # ── 只有 1 個 → 直接 attach ──
  local _cnt; _cnt=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$_cnt" -eq 1 ]]; then
    local _only; _only=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    printf "→ %s\n" "$_only"
    [[ -n "$TMUX" ]] && tmux switch-client -t "$_only" || tmux attach -t "$_only"
    return
  fi

  # ── 收集各 session 的 active window + pane 資訊 ──
  declare -A _ppath _pcmd
  while IFS='|' read -r _sn _wa _pa _cmd _path; do
    [[ "$_wa" == "1" && "$_pa" == "1" && -z "${_ppath[$_sn]}" ]] \
      && { _ppath[$_sn]="$_path"; _pcmd[$_sn]="$_cmd"; }
  done < <(tmux list-panes -a \
    -F '#{session_name}|#{window_active}|#{pane_active}|#{pane_current_command}|#{pane_current_path}' \
    2>/dev/null)

  local _list="" _now; _now=$(date +%s)

  while IFS='|' read -r _sess _att _wins _ts; do
    local _p="${_ppath[$_sess]:-$HOME}" _c="${_pcmd[$_sess]:-zsh}"

    # ── 工具偵測 ──
    # Claude Code: process name = version string (e.g. 2.1.168) OR path in .claude/worktrees
    local _tool _tcol _tkey
    if [[ "$_p" == *".claude/worktrees"* || "$_c" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      _tool="🤖 Claude"; _tcol=$'\033[1;34m'; _tkey="claude"
    elif [[ "$_c" == "codex" ]]; then
      _tool="💡 Codex"; _tcol=$'\033[1;35m'; _tkey="codex"
    elif [[ "$_c" == "nvim" || "$_c" == "vim" ]]; then
      _tool="📝 vim"; _tcol=$'\033[32m'; _tkey="vim"
    elif [[ "$_c" == "node" || "$_c" == "npm" || "$_c" == "npx" ]]; then
      _tool="⬡ node"; _tcol=$'\033[33m'; _tkey="node"
    elif [[ "$_c" == "python"* ]]; then
      _tool="🐍 python"; _tcol=$'\033[32m'; _tkey="py"
    else
      _tool="$ $_c"; _tcol=$'\033[90m'; _tkey="shell"
    fi

    # ── Claude worktree 路徑解析 ──
    local _proj_path="$_p" _wt=""
    if [[ "$_p" == *"/.claude/worktrees/"* ]]; then
      _proj_path="${_p%%/.claude/worktrees/*}"
      _wt="${_p##*/.claude/worktrees/}"
      _wt="${_wt%%/*}"
    fi

    # ── git info ──
    local _proj _br _gtop
    if [[ -n "$_wt" ]]; then
      _gtop=$(git -C "$_proj_path" rev-parse --show-toplevel 2>/dev/null)
      if [[ -n "$_gtop" ]]; then
        _proj=$(basename "$_gtop")
        _br=$(git -C "$_p" branch --show-current 2>/dev/null)
      else
        _proj=$(basename "$_proj_path"); _br=""
      fi
    else
      _gtop=$(git -C "$_p" rev-parse --show-toplevel 2>/dev/null)
      if [[ -n "$_gtop" ]]; then
        _proj=$(basename "$_gtop")
        _br=$(git -C "$_p" branch --show-current 2>/dev/null)
      else
        _proj=$(basename "$_p"); _br=""
      fi
    fi
    [[ -z "$_proj" ]] && _proj=$(basename "$_p")

    # ── time-ago ──
    local _diff=$(( _now - _ts )) _ago
    if   (( _diff < 60    )); then _ago="${_diff}s"
    elif (( _diff < 3600  )); then _ago="$(( _diff / 60 ))m"
    elif (( _diff < 86400 )); then _ago="$(( _diff / 3600 ))h"
    else                           _ago="$(( _diff / 86400 ))d"
    fi

    # ── ANSI 色碼 ──
    local G=$'\033[32m' DIM=$'\033[90m' B=$'\033[1m' YL=$'\033[33m'
    local CY=$'\033[36m' BL=$'\033[34m' MG=$'\033[35m' R=$'\033[0m'

    local _dot _dc
    [[ "$_att" != "0" ]] && { _dot="●"; _dc="$G"; } || { _dot="○"; _dc="$DIM"; }

    local _sc="$B"
    [[ "$_tkey" == "claude" ]] && _sc="${B}${BL}"
    [[ "$_tkey" == "codex"  ]] && _sc="${B}${MG}"

    local _meta=""
    [[ -n "$_br" ]] && _meta+=" ${YL}${_br}${R}"
    [[ -n "$_wt" ]] && _meta+=" ${DIM}[wt:${_wt}]${R}"

    _list+="${_sess}|${_dc}${_dot}${R} ${_sc}${_sess}${R}  ${CY}${_proj}${R}${_meta}  ${_tcol}${_tool}${R}  ${DIM}${_ago} · ${_wins}w${R}"$'\n'
  done < <(tmux list-sessions \
    -F '#{session_name}|#{session_attached}|#{session_windows}|#{session_activity}' 2>/dev/null)

  # ── reload script（ctrl-d in-place 刪除後重整列表）──
  local _ta_reload_script="/tmp/ta_reload_$$.sh"
  {
    printf '#!/bin/zsh\n'
    printf '_now=$(date +%%s)\n'
    printf 'declare -A _pp _pc\n'
    printf 'while IFS="|" read -r _sn _wa _pa _cmd _path; do\n'
    printf '  [[ "$_wa" == "1" && "$_pa" == "1" && -z "${_pp[$_sn]}" ]] && { _pp[$_sn]="$_path"; _pc[$_sn]="$_cmd"; }\n'
    printf 'done < <(tmux list-panes -a -F '"'"'#{session_name}|#{window_active}|#{pane_active}|#{pane_current_command}|#{pane_current_path}'"'"' 2>/dev/null)\n'
    printf 'while IFS="|" read -r _s _att _wins _ts; do\n'
    printf '  _p="${_pp[$_s]:-$HOME}"; _c="${_pc[$_s]:-zsh}"\n'
    printf '  if [[ "$_p" == *".claude/worktrees"* || "$_c" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then\n'
    printf '    _tk=claude; _tcol=$'"'"'\\033[1;34m'"'"'; _tool="🤖 Claude"\n'
    printf '  elif [[ "$_c" == "codex" ]]; then\n'
    printf '    _tk=codex; _tcol=$'"'"'\\033[1;35m'"'"'; _tool="💡 Codex"\n'
    printf '  else\n'
    printf '    _tk=shell; _tcol=$'"'"'\\033[90m'"'"'; _tool="$_c"\n'
    printf '  fi\n'
    printf '  _pp2="$_p"; _wt=""\n'
    printf '  [[ "$_p" == *"/.claude/worktrees/"* ]] && { _pp2="${_p%%%%/.claude/worktrees/*}"; _wt="${_p##*/.claude/worktrees/}"; _wt="${_wt%%%%/*}"; }\n'
    printf '  if [[ -n "$_wt" ]]; then\n'
    printf '    _gtop=$(git -C "$_pp2" rev-parse --show-toplevel 2>/dev/null)\n'
    printf '    if [[ -n "$_gtop" ]]; then _proj=$(basename "$_gtop"); _br=$(git -C "$_p" branch --show-current 2>/dev/null)\n'
    printf '    else _proj=$(basename "$_pp2"); _br=""; fi\n'
    printf '  else\n'
    printf '    _gtop=$(git -C "$_p" rev-parse --show-toplevel 2>/dev/null)\n'
    printf '    if [[ -n "$_gtop" ]]; then _proj=$(basename "$_gtop"); _br=$(git -C "$_p" branch --show-current 2>/dev/null)\n'
    printf '    else _proj=$(basename "$_p"); _br=""; fi\n'
    printf '  fi\n'
    printf '  [[ -z "$_proj" ]] && _proj=$(basename "$_p")\n'
    printf '  _diff=$(( _now - _ts ))\n'
    printf '  if ((_diff<60)); then _ago="${_diff}s"; elif ((_diff<3600)); then _ago="$((_diff/60))m"\n'
    printf '  elif ((_diff<86400)); then _ago="$((_diff/3600))h"; else _ago="$((_diff/86400))d"; fi\n'
    printf '  G=$'"'"'\\033[32m'"'"'; DIM=$'"'"'\\033[90m'"'"'; B=$'"'"'\\033[1m'"'"'; YL=$'"'"'\\033[33m'"'"'\n'
    printf '  CY=$'"'"'\\033[36m'"'"'; BL=$'"'"'\\033[34m'"'"'; MG=$'"'"'\\033[35m'"'"'; R=$'"'"'\\033[0m'"'"'\n'
    printf '  [[ "$_att" != "0" ]] && { _dot="●"; _dc="$G"; } || { _dot="○"; _dc="$DIM"; }\n'
    printf '  _sc="$B"; [[ "$_tk" == "claude" ]] && _sc="${B}${BL}"; [[ "$_tk" == "codex" ]] && _sc="${B}${MG}"\n'
    printf '  _meta=""; [[ -n "$_br" ]] && _meta+=" ${YL}${_br}${R}"; [[ -n "$_wt" ]] && _meta+=" ${DIM}[wt:${_wt}]${R}"\n'
    printf '  printf "%%s|%%s%%s%%s %%s%%s%%s  %%s%%s%%s%%s  %%s%%s%%s  %%s%%s · %%sw%%s\\n" \\\n'
    printf '    "$_s" "$_dc" "$_dot" "$R" "$_sc" "$_s" "$R" "$CY" "$_proj" "$R" "$_meta" "$_tcol" "$_tool" "$R" "$DIM" "$_ago" "$_wins" "$R"\n'
    printf 'done < <(tmux list-sessions -F '"'"'#{session_name}|#{session_attached}|#{session_windows}|#{session_activity}'"'"' 2>/dev/null)\n'
  } > "$_ta_reload_script"
  chmod +x "$_ta_reload_script"

  # ── ctrl-x helper（become() 用）──
  local _ta_cx_script="/tmp/ta_cx_$$.sh"
  cat > "$_ta_cx_script" << 'CXEOF'
#!/bin/zsh
SESS="$1"
[[ -z "$SESS" ]] && exit 1
PINFO=$(tmux list-panes -a \
  -F '#{session_name}|#{window_active}|#{pane_active}|#{pane_current_path}|#{pane_current_command}' \
  2>/dev/null | awk -F'|' -v s="$SESS" '$1==s && $2=="1" && $3=="1" {print $4"|"$5; exit}')
CWD="${PINFO%%|*}"; CMD="${PINFO##*|}"
[[ -z "$CWD" ]] && CWD="$HOME"
if [[ "$CWD" == *"/.claude/worktrees/"* || "$CMD" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  tmux new-window -t "$SESS" -n "claude" -c "$CWD" "claude -c"
else
  tmux new-window -t "$SESS" -n "claude" -c "$CWD" "claude"
fi
if [[ -n "$TMUX" ]]; then exec tmux switch-client -t "$SESS"
else exec tmux attach -t "$SESS"; fi
CXEOF
  chmod +x "$_ta_cx_script"
  trap "rm -f '$_ta_reload_script' '$_ta_cx_script'" EXIT INT TERM

  # ── fzf 選單 ──
  local _out _key _sel
  _out=$(printf '%s' "$_list" \
    | fzf \
        --ansi \
        --prompt=" ❐ tmux  " \
        --delimiter='|' \
        --with-nth=2 \
        --height=80% \
        --min-height=8 \
        --reverse \
        --border=rounded \
        --border-label=' sessions ' \
        --border-label-pos=3 \
        --info=right \
        --pointer='▶' \
        --marker='✓' \
        --color='border:#555555,label:#aaaaaa,pointer:#61afef,hl:#e5c07b,hl+:#e5c07b' \
        --header=$'  enter:attach  ctrl-x:resume-ai  ctrl-d:delete↺  ctrl-n:new  ctrl-r:rename\n' \
        --bind "ctrl-d:execute-silent(tmux kill-session -t {1} 2>/dev/null)+reload(zsh '$_ta_reload_script')" \
        --bind "ctrl-x:become(zsh '$_ta_cx_script' {1})" \
        --preview='
          S={1}
          DIM=$'"'"'\033[90m'"'"'; B=$'"'"'\033[1m'"'"'; YL=$'"'"'\033[33m'"'"'
          GR=$'"'"'\033[32m'"'"'; RD=$'"'"'\033[31m'"'"'; CY=$'"'"'\033[36m'"'"'; R=$'"'"'\033[0m'"'"'

          PINFO=$(tmux list-panes -a \
            -F "#{session_name}|#{window_active}|#{pane_active}|#{pane_id}|#{pane_current_path}|#{pane_current_command}" \
            2>/dev/null | awk -F"|" -v s="$S" '"'"'$1==s && $2=="1" && $3=="1" {print $4"|"$5"|"$6; exit}'"'"')
          PANE_ID="${PINFO%%|*}"; rest="${PINFO#*|}"; P="${rest%%|*}"; CMD="${rest##*|}"
          PP="${P%%/.claude/worktrees/*}"; [[ "$PP" == "$P" ]] && PP="$P"
          WT=""; [[ "$P" == *"/.claude/worktrees/"* ]] && WT="${P##*/.claude/worktrees/}" && WT="${WT%%/*}"
          IS_CLAUDE=0
          [[ "$P" == *".claude/worktrees"* || "$CMD" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && IS_CLAUDE=1

          if [[ -n "$PANE_ID" ]]; then
            printf "${B}── Pane${R}${DIM} ───────────────────────────────${R}\n"
            tmux capture-pane -t "$PANE_ID" -p 2>/dev/null | tail -8 | sed "s/^/  /"
            printf "\n"
          fi

          printf "${B}── Windows${R}${DIM} ─────────────────────────────${R}\n"
          tmux list-windows -t "$S" \
            -F "  #{window_index} #{?window_active,▶ ,  }#{window_name}  ${DIM}#{window_panes}p${R}" \
            2>/dev/null

          printf "\n${B}── Path${R}${DIM} ─────────────────────────────────${R}\n"
          if [[ -n "$WT" ]]; then
            printf "  ${DIM}wt: %s${R}\n  ${DIM}%s${R}\n" "$WT" "$PP"
          else
            printf "  ${DIM}%s${R}\n" "$P"
          fi

          GG=""
          git -C "$P"  rev-parse --is-inside-work-tree &>/dev/null && GG="$P"
          [[ -z "$GG" ]] && git -C "$PP" rev-parse --is-inside-work-tree &>/dev/null && GG="$PP"
          if [[ -n "$GG" ]]; then
            BR=$(git -C "$GG" branch --show-current 2>/dev/null)
            printf "\n${B}── Git${R}${DIM} ──────────────────────────────────${R}\n"
            printf "  ${CY}%s${R}\n" "$BR"
            GS=$(git -C "$GG" status -s 2>/dev/null | head -6)
            if [[ -n "$GS" ]]; then
              printf "%s\n" "$GS" | while IFS= read -r line; do
                case "$line" in
                  M*|" M"*) printf "  ${YL}%s${R}\n" "$line" ;;
                  A*|" A"*) printf "  ${GR}%s${R}\n" "$line" ;;
                  D*|" D"*) printf "  ${RD}%s${R}\n" "$line" ;;
                  "??"*)    printf "  ${DIM}%s${R}\n" "$line" ;;
                  *)        printf "  %s\n" "$line" ;;
                esac
              done
            else
              printf "  ${DIM}(clean)${R}\n"
            fi
            printf "\n${B}── Commits${R}${DIM} ─────────────────────────────${R}\n"
            git -C "$GG" log --oneline --color=always -5 2>/dev/null | sed "s/^/  /"
          fi
        ' \
        --preview-window='right:46%:border-left:wrap' \
        --expect='ctrl-n,ctrl-r')

  _key=$(printf '%s' "$_out" | head -1)
  _sel=$(printf '%s' "$_out" | sed -n '2p' | cut -d'|' -f1)

  rm -f "$_ta_reload_script" "$_ta_cx_script" 2>/dev/null
  trap - EXIT INT TERM

  case "$_key" in
    ctrl-n)
      printf "新 session 名稱: "; read -r _n; [[ -z "$_n" ]] && return
      [[ -n "$TMUX" ]] \
        && tmux new-session -d -s "$_n" -c "$PWD" && tmux switch-client -t "$_n" \
        || tmux new-session -s "$_n" -c "$PWD"
      ;;
    ctrl-r)
      [[ -z "$_sel" ]] && return
      printf "改名 '%s' → " "$_sel"; read -r _new
      [[ -n "$_new" ]] && tmux rename-session -t "$_sel" "$_new"
      ta
      ;;
    *)
      [[ -z "$_sel" ]] && return
      [[ -n "$TMUX" ]] && tmux switch-client -t "$_sel" || tmux attach -t "$_sel"
      ;;
  esac
}

# ── tn: 快速新建命名 session（預設名稱 = basename $PWD）──
tn() {
  local _n="${1:-$(basename "$PWD")}"
  if [[ -n "$TMUX" ]]; then
    tmux new-session -d -s "$_n" -c "$PWD" && tmux switch-client -t "$_n"
  else
    tmux new-session -s "$_n" -c "$PWD"
  fi
}

# ── tk: 快速刪除 session（無參數 → fzf 選）──
tk() {
  if [[ -n "$1" ]]; then
    tmux kill-session -t "$1"
  else
    local _s
    _s=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
      | fzf --prompt="  kill  " --height=40% --reverse --border=rounded)
    [[ -n "$_s" ]] && tmux kill-session -t "$_s"
  fi
}

# ── tc: 建立 session + 自動開 claude（一鍵工作流）──
# 用法：tc [目錄]   → session 名稱 = basename 目錄
#       tc          → 用 $PWD
tc() {
  local _dir="${1:-$PWD}"
  _dir="${_dir/#\~/$HOME}"
  [[ "$_dir" != /* ]] && _dir="$PWD/$_dir"

  if [[ ! -d "$_dir" ]]; then
    printf "tc: 目錄不存在：%s\n" "$_dir" >&2; return 1
  fi

  local _sname; _sname=$(basename "$_dir")

  if tmux has-session -t "$_sname" 2>/dev/null; then
    printf "→ session '%s' 已存在，attach\n" "$_sname"
    [[ -n "$TMUX" ]] && tmux switch-client -t "$_sname" || tmux attach -t "$_sname"
    return
  fi

  tmux new-session -d -s "$_sname" -c "$_dir" -n "shell"
  tmux new-window -t "$_sname" -n "claude" -c "$_dir" "claude -c"
  tmux select-window -t "$_sname:1"

  printf "tc: session '%s' 已建立（shell:0 + claude:1）\n" "$_sname"
  [[ -n "$TMUX" ]] && tmux switch-client -t "$_sname" || tmux attach -t "$_sname"
}
