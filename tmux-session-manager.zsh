# ═══════════════════════════════════════════════════════════════════
# tmux 工作流整合  （Claude Code / Codex 感知版 · COMPACT CLARITY）
#   ta   — session picker (enter/ctrl-n/d/r/x/?:preview)
#   tn   — 快速新建命名 session（防重複）
#   tk   — 刪除 session（直接呼叫有確認提示）
#   tc   — 建 session + 自動開 claude（window 0=shell, 1=claude）
#   tR   — 批次重命名所有數字 session 為專案名稱
#   tl   — 快速列表（非互動，可 pipe）
#
# DISPLAY FORMAT（COMPACT CLARITY，~50 visible chars）：
#   DOT  ICON  NAME(10)  PROJECT(16)  BRANCH_LEFT(12)  STATUS  AGO
#   ● ◉ flb-bot        Flb Bot Fun…  …-pre0607  ✓  2m
#
# 外部腳本（~/.local/bin/）：
#   tmux-autoname  — after-new-session hook，自動命名數字 session
#   ta-preview     — fzf preview（Claude/Codex 狀態 + git + MCP）
#   ta-cx          — ctrl-x resume AI handler（claude -r 精準 resume）
#
# ~/.tmux.conf 加一行：
#   set-hook -g after-new-session 'run-shell -b "~/.local/bin/tmux-autoname \"#{session_name}\" \"#{pane_current_path}\""'
# ═══════════════════════════════════════════════════════════════════

# ── _ta_slug: slugify to kebab-case (LC_ALL=C for non-ASCII paths) ──
_ta_slug() {
  printf '%s' "$1" | LC_ALL=C tr -cs 'A-Za-z0-9_-' '-' | sed 's/--*/-/g;s/^-//;s/-$//'
}

# ── _ta_hint: best rename candidate (git remote > git-top > basename) ──
_ta_hint() {
  local _sp="$1" _spp _sg _remote _hint=""
  _spp="${_sp%%/.claude/worktrees/*}"
  _spp="${_spp%%/.codex/worktrees/*}"
  _sg=$(git -C "$_spp" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$_sg" ]]; then
    _remote=$(git -C "$_sg" remote get-url origin 2>/dev/null)
    if [[ -n "$_remote" ]]; then
      _hint="${_remote##*/}"; _hint="${_hint%.git}"; _hint="${_hint%.GIT}"
    fi
    [[ -z "$_hint" ]] && _hint=$(basename "$_sg")
  fi
  [[ -z "$_hint" ]] && _hint=$(basename "$_spp")
  _ta_slug "$_hint"
}

# ── _ta_build_list: output SESSION|DISPLAY lines for fzf ──
# Single source of truth — used by ta() initial load AND ctrl-d reload script.
_ta_build_list() {
  local G=$'\033[32m' DIM=$'\033[90m' B=$'\033[1m' YL=$'\033[33m'
  local CY=$'\033[36m' BL=$'\033[34m' MG=$'\033[35m' R=$'\033[0m' RD=$'\033[31m'
  local _now; _now=$(date +%s)

  # collect active pane per session
  declare -A _ppath _pcmd
  while IFS='|' read -r _sn _wa _pa _cmd _path; do
    [[ "$_wa" == "1" && "$_pa" == "1" && -z "${_ppath[$_sn]}" ]] \
      && { _ppath[$_sn]="$_path"; _pcmd[$_sn]="$_cmd"; }
  done < <(tmux list-panes -a \
    -F '#{session_name}|#{window_active}|#{pane_active}|#{pane_current_command}|#{pane_current_path}' \
    2>/dev/null)

  while IFS='|' read -r _sess _att _wins _ts; do
    local _p="${_ppath[$_sess]:-$HOME}" _c="${_pcmd[$_sess]:-zsh}"

    # tool detection
    local _tkey _icon _tcol
    if [[ "$_p" == *".claude/worktrees"* || "$_c" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      _tkey=claude; _icon=""; _tcol="${B}${BL}"
    elif [[ "$_c" == "codex" || "$_c" == "Codex" || "$_p" == *"/.codex/worktrees"* ]]; then
      _tkey=codex;  _icon="";  _tcol="${B}${MG}"
    elif [[ "$_c" == "nvim" || "$_c" == "vim" ]]; then
      _tkey=vim;    _icon="";  _tcol="${G}"
    elif [[ "$_c" == "python"* ]]; then
      _tkey=py;     _icon="";  _tcol="${G}"
    elif [[ "$_c" == "node" || "$_c" == "npm" || "$_c" == "npx" ]]; then
      _tkey=node;   _icon="";  _tcol="${YL}"
    else
      _tkey=shell;  _icon="$"; _tcol="${DIM}"
    fi

    # worktree parsing
    local _proj_path="$_p" _wt=""
    if [[ "$_p" == *"/.claude/worktrees/"* ]]; then
      _proj_path="${_p%%/.claude/worktrees/*}"
      _wt="${_p##*/.claude/worktrees/}"; _wt="${_wt%%/*}"
    fi

    # git project + branch
    local _proj _br _gtop
    if [[ -n "$_wt" ]]; then
      _gtop=$(git -C "$_proj_path" rev-parse --show-toplevel 2>/dev/null)
      if [[ -n "$_gtop" ]]; then
        _proj=$(basename "$_gtop"); _br=$(git -C "$_p" branch --show-current 2>/dev/null)
      else
        _proj=$(basename "$_proj_path"); _br=""
      fi
    else
      _gtop=$(git -C "$_p" rev-parse --show-toplevel 2>/dev/null)
      if [[ -n "$_gtop" ]]; then
        _proj=$(basename "$_gtop"); _br=$(git -C "$_p" branch --show-current 2>/dev/null)
      else
        _proj=$(basename "$_p"); _br=""
      fi
    fi
    [[ -z "$_proj" ]] && _proj=$(basename "$_p")

    # time-ago
    local _diff=$(( _now - _ts )) _ago
    if   (( _diff < 60    )); then _ago="${_diff}s"
    elif (( _diff < 3600  )); then _ago="$(( _diff / 60 ))m"
    elif (( _diff < 86400 )); then _ago="$(( _diff / 3600 ))h"
    else                           _ago="$(( _diff / 86400 ))d"
    fi

    # Claude live status shown inline (non-blocking python3 call)
    local _st_icon=""
    if [[ "$_tkey" == "claude" ]]; then
      local _st; _st=$(python3 - "$_p" "$_proj_path" 2>/dev/null <<'PYEOF2'
import json,os,glob,sys,subprocess
path,base=sys.argv[1],sys.argv[2]
sd=os.path.expanduser('~/.claude/sessions/'); best=None
for f in glob.glob(sd+'*.json'):
    try:
        d=json.load(open(f))
        if d.get('cwd') in (path,base) and isinstance(d.get('pid'),int):
            try: subprocess.check_call(['kill','-0',str(d['pid'])],stderr=subprocess.DEVNULL)
            except: continue
            if best is None or d.get('updatedAt',0)>best.get('updatedAt',0): best=d
    except: pass
if best: print(best.get('status',''))
PYEOF2
      )
      case "$_st" in
        busy)    _st_icon=" ${RD}⏳${R}" ;;
        waiting) _st_icon=" ${YL}⏸${R}" ;;
        idle)    _st_icon=" ${G}✓${R}" ;;
      esac
    fi

    # attach dot
    local _dot _dc
    [[ "$_att" != "0" ]] && { _dot="●"; _dc="$G"; } || { _dot="○"; _dc="$DIM"; }

    # session name colour by tool
    local _sc="$B"
    [[ "$_tkey" == "claude" ]] && _sc="${B}${BL}"
    [[ "$_tkey" == "codex"  ]] && _sc="${B}${MG}"

    # COMPACT CLARITY truncation — target ~50 visible chars
    #   session: right-truncate 10
    #   project: right-truncate 16
    #   branch:  LEFT-truncate 12  (…-pre0607 beats feat/my-p…)
    local _sess_d="${_sess:0:10}"; [[ ${#_sess} -gt 10 ]] && _sess_d+="…"
    local _proj_d="${_proj:0:16}"; [[ ${#_proj} -gt 16 ]] && _proj_d+="…"
    local _br_d=""
    if [[ -n "$_br" ]]; then
      if (( ${#_br} > 12 )); then _br_d="…${_br[-11,-1]}"
      else _br_d="$_br"; fi
    fi

    # assemble display line
    local _line="${_dc}${_dot}${R} ${_tcol}${_icon}${R} ${_sc}${_sess_d}${R}  ${CY}${_proj_d}${R}"
    [[ -n "$_br_d"    ]] && _line+="  ${YL}${_br_d}${R}"
    [[ -n "$_st_icon" ]] && _line+="${_st_icon}"
    _line+="  ${DIM}${_ago}${R}"

    local _slug; _slug=$(_ta_slug "$_proj")
    [[ -n "$_wt" ]] && _slug="${_slug:0:12}-${_wt:0:8}" || _slug="${_slug:0:20}"
    printf '%s|%s|%s\n' "$_sess" "$_slug" "$_line"
  done < <(tmux list-sessions \
    -F '#{session_name}|#{session_attached}|#{session_windows}|#{session_activity}' 2>/dev/null)
}

ta() {
  command -v fzf &>/dev/null || { printf "需要 fzf：brew install fzf\n" >&2; return 1; }

  # tmux server not running
  if ! tmux info &>/dev/null 2>&1; then
    printf "tmux 未啟動，開新 session？[名稱/Enter 取消] "
    read -r _n; [[ -n "$_n" ]] && tmux new-session -s "$_n"; return
  fi

  # no sessions at all
  if ! tmux list-sessions &>/dev/null 2>&1; then
    printf "無 session，名稱（Enter 用 main）: "
    read -r _n; _n="${_n:-main}"
    [[ -n "$TMUX" ]] \
      && tmux new-session -d -s "$_n" -c "$PWD" && tmux switch-client -t "$_n" \
      || tmux new-session -s "$_n" -c "$PWD"
    return
  fi

  # silently auto-rename any numeric sessions before showing picker
  {
    declare -A _ta_np
    while IFS='|' read -r _sn _wa _pa _path; do
      [[ "$_wa" == "1" && "$_pa" == "1" && -z "${_ta_np[$_sn]}" ]] && _ta_np[$_sn]="$_path"
    done < <(tmux list-panes -a \
      -F '#{session_name}|#{window_active}|#{pane_active}|#{pane_current_path}' 2>/dev/null)
    while IFS= read -r _s; do
      [[ "$_s" =~ ^[0-9]+$ ]] || continue
      ~/.local/bin/tmux-autoname "$_s" "${_ta_np[$_s]:-}" 2>/dev/null
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  }

  # only 1 session → attach directly
  local _cnt; _cnt=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$_cnt" -eq 1 ]]; then
    local _only; _only=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    printf "→ %s\n" "$_only"
    [[ -n "$TMUX" ]] && tmux switch-client -t "$_only" || tmux attach -t "$_only"
    return
  fi

  # build initial list
  local _list; _list=$(_ta_build_list)

  # reload script — sources this file and calls _ta_build_list (single source of truth)
  local _reload_f="/tmp/ta_reload_$$.sh"
  printf '#!/bin/zsh\nsource "%s" 2>/dev/null\n_ta_build_list\n' "${(%):-%x}" > "$_reload_f"
  chmod +x "$_reload_f"

  local _cn_f="/tmp/ta_cn_$$.sh"
  cat > "$_cn_f" << 'CNEOF'
#!/bin/zsh
printf 'New session name: ' >/dev/tty
read -r _n </dev/tty
[[ -z "$_n" ]] && exit 0
if tmux has-session -t "$_n" 2>/dev/null; then
  printf "Session '%s' already exists\n" "$_n" >/dev/tty; sleep 1
else
  tmux new-session -d -s "$_n" -c "$HOME" 2>/dev/null && printf "Created '%s'\n" "$_n" >/dev/tty
fi
CNEOF
  chmod +x "$_cn_f"

  local _cr_f="/tmp/ta_cr_$$.sh"
  cat > "$_cr_f" << 'CREOF'
#!/bin/zsh
SESS="$1"; HINT="$2"
printf "Rename '%s' → [%s]: " "$SESS" "$HINT" >/dev/tty
read -r _new </dev/tty
[[ -z "$_new" ]] && _new="$HINT"
[[ -z "$_new" || "$_new" == "$SESS" ]] && exit 0
if tmux has-session -t "$_new" 2>/dev/null; then
  printf "Name '%s' already exists\n" "$_new" >/dev/tty; sleep 1
else
  tmux rename-session -t "$SESS" "$_new" 2>/dev/null
fi
CREOF
  chmod +x "$_cr_f"

  trap "rm -f '$_reload_f' '$_cn_f' '$_cr_f'" EXIT INT TERM

  # adaptive preview window: hidden by default on narrow screens
  local _pw="right:44%,hidden,border-left"
  (( ${COLUMNS:-80} >= 120 )) && _pw="right:44%,border-left"

  local _out _key _sel
  _out=$(printf '%s\n' "$_list" \
    | fzf \
        --ansi \
        --prompt=" tmux  " \
        --delimiter='|' \
        --with-nth=3 \
        --height=80% \
        --min-height=6 \
        --reverse \
        --border=rounded \
        --border-label=' sessions ' \
        --border-label-pos=3 \
        --info=right \
        --pointer='▶' \
        --marker='✓' \
        --color='border:#555555,label:#aaaaaa,pointer:#61afef,hl:#e5c07b,hl+:#e5c07b' \
        --header=$'  enter:attach  ctrl-x:resume-ai  ctrl-d:delete↺  ctrl-n:new  ctrl-r:rename  ?:preview\n' \
        --bind "ctrl-d:execute-silent(tmux kill-session -t {1} 2>/dev/null)+reload(zsh '$_reload_f')" \
        --bind "ctrl-n:execute(zsh '$_cn_f')+reload(zsh '$_reload_f')" \
        --bind "ctrl-r:execute(zsh '$_cr_f' {1} {2})+reload(zsh '$_reload_f')" \
        --bind "ctrl-x:become($HOME/.local/bin/ta-cx {1})" \
        --bind "?:toggle-preview" \
        --preview="$HOME/.local/bin/ta-preview {1}" \
        --preview-window="$_pw")

  _sel=$(printf '%s' "$_out" | cut -d'|' -f1)

  rm -f "$_reload_f" "$_cn_f" "$_cr_f" 2>/dev/null
  trap - EXIT INT TERM

  [[ -z "$_sel" ]] && return
  [[ -n "$TMUX" ]] && tmux switch-client -t "$_sel" || tmux attach -t "$_sel"
}

# ── tn: 快速新建命名 session（防重複，slug 化）──
tn() {
  local _raw="${1:-$(basename "$PWD")}"
  local _n; _n=$(_ta_slug "$_raw"); [[ -z "$_n" ]] && _n="$_raw"
  if tmux has-session -t "$_n" 2>/dev/null; then
    printf "session '%s' 已存在，切換\n" "$_n"
    [[ -n "$TMUX" ]] && tmux switch-client -t "$_n" || tmux attach -t "$_n"
    return
  fi
  if [[ -n "$TMUX" ]]; then
    tmux new-session -d -s "$_n" -c "$PWD" && tmux switch-client -t "$_n"
  else
    tmux new-session -s "$_n" -c "$PWD"
  fi
}

# ── tk: 刪除 session（直接指定名稱時有確認；無參數 → fzf 選）──
tk() {
  if [[ -n "$1" ]]; then
    printf "刪除 session '%s'？[y/N] " "$1"
    read -r _ans
    [[ "$_ans" =~ ^[Yy]$ ]] && tmux kill-session -t "$1"
  else
    local _s
    _s=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
      | fzf --prompt="  kill  " --height=40% --reverse --border=rounded \
            --header='enter:delete  esc:cancel')
    if [[ -n "$_s" ]]; then
      printf "刪除 session '%s'？[y/N] " "$_s"
      read -r _ans
      [[ "$_ans" =~ ^[Yy]$ ]] && tmux kill-session -t "$_s"
    fi
  fi
}

# ── tc: 建 session + 開 claude（window 0=shell, window 1=claude -c）──
# 若 session 已存在 → 在現有 session 加開新 claude window
tc() {
  local _dir="${1:-$PWD}"
  _dir="${_dir/#\~/$HOME}"
  [[ "$_dir" != /* ]] && _dir="$PWD/$_dir"
  if [[ ! -d "$_dir" ]]; then
    printf "tc: 目錄不存在：%s\n" "$_dir" >&2; return 1
  fi
  local _sname; _sname=$(_ta_slug "$(basename "$_dir")")
  [[ -z "$_sname" ]] && _sname="session"
  if tmux has-session -t "$_sname" 2>/dev/null; then
    printf "→ session '%s' 已存在，加開 claude window\n" "$_sname"
    tmux new-window -t "$_sname" -n "claude" -c "$_dir" "claude -c"
    [[ -n "$TMUX" ]] && tmux switch-client -t "$_sname" || tmux attach -t "$_sname"
    return
  fi
  tmux new-session -d -s "$_sname" -c "$_dir" -n "shell"
  tmux new-window -t "$_sname" -n "claude" -c "$_dir" "claude -c"
  tmux select-window -t "$_sname:1"
  printf "tc: '%s' 已建立（shell:0  claude:1）\n" "$_sname"
  [[ -n "$TMUX" ]] && tmux switch-client -t "$_sname" || tmux attach -t "$_sname"
}

# ── tR: 批次重命名所有數字 session 為專案名稱 ──
# 用法：tR        → 執行
#       tR -n     → dry-run（只顯示，不執行）
tR() {
  local _dry=0; [[ "$1" == "-n" ]] && _dry=1
  local _renamed=0 _skipped=0
  declare -A _sp
  while IFS='|' read -r _sn _wa _pa _path; do
    [[ "$_wa" == "1" && "$_pa" == "1" && -z "${_sp[$_sn]}" ]] && _sp[$_sn]="$_path"
  done < <(tmux list-panes -a \
    -F '#{session_name}|#{window_active}|#{pane_active}|#{pane_current_path}' 2>/dev/null)

  while IFS= read -r _s; do
    [[ "$_s" =~ ^[0-9]+$ ]] || continue
    local _path="${_sp[$_s]:-}"
    local _hint; _hint=$(_ta_hint "${_path:-$HOME}")
    [[ -z "$_hint" || "$_hint" == "." ]] && { (( _skipped++ )); continue; }
    # collision-safe attempt
    local _attempt="$_hint" _i=2
    while tmux has-session -t "$_attempt" 2>/dev/null && [[ "$_attempt" != "$_s" ]]; do
      _attempt="${_hint:0:17}-${_i}"; (( _i++ ))
      [[ $_i -gt 9 ]] && { _attempt=""; break; }
    done
    [[ -z "$_attempt" || "$_attempt" == "$_s" ]] && { (( _skipped++ )); continue; }
    if [[ "$_dry" == "1" ]]; then
      printf "  would rename '%s' → '%s'\n" "$_s" "$_attempt"
    else
      tmux rename-session -t "$_s" "$_attempt" 2>/dev/null \
        && { printf "  renamed '%s' → '%s'\n" "$_s" "$_attempt"; (( _renamed++ )); } \
        || (( _skipped++ ))
    fi
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)

  [[ "$_dry" == "0" ]] && printf "tR: renamed %d  skipped %d\n" "$_renamed" "$_skipped"
}

# ── tl: 快速列出所有 session（非互動，可 pipe）──
# 用法：tl        → 彩色摘要
#       tl -p     → 純 session 名（供 script 使用）
tl() {
  if [[ "$1" == "-p" ]]; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null; return
  fi
  local _now; _now=$(date +%s)
  local G=$'\033[32m' DIM=$'\033[90m' B=$'\033[1m' R=$'\033[0m' CY=$'\033[36m'
  local BL=$'\033[34m' MG=$'\033[35m'
  while IFS='|' read -r _s _att _ts _cmd _path; do
    local _diff=$(( _now - _ts )) _ago
    if   (( _diff < 60    )); then _ago="${_diff}s"
    elif (( _diff < 3600  )); then _ago="$(( _diff / 60 ))m"
    elif (( _diff < 86400 )); then _ago="$(( _diff / 3600 ))h"
    else                           _ago="$(( _diff / 86400 ))d"
    fi
    local _dot _dc; [[ "$_att" != "0" ]] && { _dot="●"; _dc="$G"; } || { _dot="○"; _dc="$DIM"; }
    local _sc="$B"
    if [[ "$_path" == *".claude/worktrees"* || "$_cmd" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      _sc="${B}${BL}"
    elif [[ "$_cmd" == "codex" || "$_cmd" == "Codex" ]]; then
      _sc="${B}${MG}"
    fi
    printf "%s%s%s  %s%-18s%s  %s%-20s%s  %s%-8s%s  %s\n" \
      "$_dc" "$_dot" "$R" "$_sc" "$_s" "$R" "$CY" "$(basename "$_path")" "$R" \
      "$DIM" "$_cmd" "$R" "$_ago"
  done < <(tmux list-panes -a \
    -F '#{session_name}|#{session_attached}|#{session_activity}|#{pane_current_command}|#{pane_current_path}' \
    2>/dev/null | awk -F'|' '!seen[$1]++')
}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# The next line updates PATH for the Google Cloud SDK.
