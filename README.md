# tmux AI Session Manager

tmux session 管理工具，深度整合 **Claude Code** 與 **Codex** 工作流。

## 指令一覽

| 指令 | 說明 |
|------|------|
| `ta` | 全功能 fzf session 選單 |
| `tn [名稱]` | 快速建立新 session（slug 化 + 防重複）|
| `tk [名稱]` | 刪除 session（有確認提示）|
| `tc [目錄]` | 一鍵建 session + 開 Claude Code |
| `tR` | 批次重命名所有數字 session 為專案名稱 |
| `tl` | 快速列表（非互動，可 pipe）|

## ta 選單外觀

```
● ◉ flb-bot        Flb Bot Fun…  master  ✓  2m
○   FLB-COURSE…    FLB-COURSE-s  …ree-pre0607  ⏳  5m
○   timdirty        timdirty                    8m
```

**顏色標示：**
- 綠色 `●` = 已連線，灰色 `○` = 閒置
- 藍色粗體 = Claude Code session
- 紫色粗體 = Codex session
- `✓` = Claude idle，`⏳` = busy，`⏸` = waiting

## 快捷鍵

| 鍵 | 動作 |
|----|------|
| `Enter` | Attach / switch-client |
| `↑` / `↓` | 上下選擇（或 `ctrl-k` / `ctrl-j`，Termius 友善）|
| `ctrl-x` | Resume Claude Code / Codex（開新 window）|
| `ctrl-d` | 原地刪除 session（列表即時重整，fzf 不關閉）|
| `ctrl-n` | 建立新命名 session |
| `ctrl-r` | 重新命名 session（預填專案 slug）|
| `?` | Toggle preview 面板 |

## Preview 面板（`?` 開啟）

- Claude Code 狀態（status / version / session ID / conversation title）
- Codex 最近 thread（sqlite 查詢）
- Pane 最後輸出（看 Claude 正在做什麼）
- Windows 列表
- 路徑 + worktree 名稱與兄弟 worktree
- Git branch + status（彩色 M/A/D/?）+ 最近 5 commits
- MCP server 列表

## 安裝

```zsh
# 1. 下載並加入 ~/.zshrc
curl -fsSL https://raw.githubusercontent.com/timdirty/tmux-ai-session-manager/main/tmux-session-manager.zsh >> ~/.zshrc

# 2. 建立外部腳本目錄
mkdir -p ~/.local/bin

# 3. 下載外部腳本（preview / ctrl-x handler / auto-rename）
curl -fsSL https://raw.githubusercontent.com/timdirty/tmux-ai-session-manager/main/bin/ta-preview > ~/.local/bin/ta-preview
curl -fsSL https://raw.githubusercontent.com/timdirty/tmux-ai-session-manager/main/bin/ta-cx > ~/.local/bin/ta-cx
curl -fsSL https://raw.githubusercontent.com/timdirty/tmux-ai-session-manager/main/bin/tmux-autoname > ~/.local/bin/tmux-autoname
chmod +x ~/.local/bin/ta-preview ~/.local/bin/ta-cx ~/.local/bin/tmux-autoname

# 4. 載入
source ~/.zshrc
```

### tmux after-new-session hook（自動命名）

在 `~/.tmux.conf` 加一行：

```
set-hook -g after-new-session 'run-shell -b "~/.local/bin/tmux-autoname \"#{session_name}\" \"#{pane_current_path}\""'
```

## 依賴

- **tmux** ≥ 3.2（`brew install tmux`）
- **fzf** ≥ 0.35（`brew install fzf`）
- **zsh**（macOS 預設）
- **git**（取 branch / status 資訊，無 git repo 時自動跳過）
- **python3**（Claude 狀態偵測，選配）

## Claude Code 偵測原理

Claude Code 在 tmux 中的 `pane_current_command` 顯示為版本號（如 `2.1.168`），
路徑為 `project/.claude/worktrees/WORKTREE_NAME`。

`ta` 同時偵測兩者，自動識別並標色。Claude session 狀態（busy/waiting/idle）
透過 `~/.claude/sessions/*.json` 一次批次掃描，不會因 session 數量變慢。

## tc 工作流範例

```zsh
# 在 ~/dev/myproject 開一個完整的 Claude Code 工作環境
tc ~/dev/myproject
# → 建立 session "myproject"
# → window 0: zsh shell
# → window 1: claude -c（續最近對話）
# → 自動切換到 window 1
```

## 授權

MIT
