# tmux AI Session Manager

tmux session 管理工具，深度整合 **Claude Code** 與 **Codex** 工作流。

## 功能

| 指令 | 說明 |
|------|------|
| `ta` | 全功能 fzf session 選單 |
| `tn [名稱]` | 快速建立新 session |
| `tk [名稱]` | 快速刪除 session |
| `tc [目錄]` | 一鍵建 session + 開 Claude Code |

## ta 選單功能

```
● 0  Flb-Bot-AI  worktree-main  🤖 Claude  [wt:0607]  2m · 3w
○ 1  FLB-COURSE  worktree-pre   🤖 Claude  [wt:pre]   5h · 1w
```

**顏色標示：**
- 綠色 `●` = 已連線，灰色 `○` = 閒置
- 藍色粗體 = Claude Code session
- 紫色粗體 = Codex session

**右側 Preview 面板：**
- Pane 最後輸出（看 Claude 正在做什麼）
- Windows 列表
- 路徑 + worktree 名稱
- Git branch + status（彩色 M/A/D/?）+ 最近 5 commits

**快捷鍵：**

| 鍵 | 動作 |
|----|------|
| `Enter` | Attach / switch-client |
| `ctrl-x` | 在該 session 開新 Claude Code window |
| `ctrl-d` | 原地刪除 session（列表即時重整，不關閉 fzf）|
| `ctrl-n` | 建立新命名 session |
| `ctrl-r` | 重新命名 session |

## 安裝

```zsh
# 下載並加入 ~/.zshrc
curl -fsSL https://raw.githubusercontent.com/timdirty/tmux-ai-session-manager/main/tmux-session-manager.zsh >> ~/.zshrc
source ~/.zshrc
```

或手動複製 `tmux-session-manager.zsh` 內容貼入 `~/.zshrc`，再執行：

```zsh
source ~/.zshrc
```

## 依賴

- **tmux** ≥ 3.2 （`brew install tmux`）
- **fzf** ≥ 0.35 （`brew install fzf`）
- **zsh**（macOS 預設）
- **git**（取 branch / status 資訊，無 git repo 時自動跳過）

## Claude Code 偵測原理

Claude Code 在 tmux 中的 `pane_current_command` 顯示為版本號（如 `2.1.168`），
路徑為 `project/.claude/worktrees/WORKTREE_NAME`。

`ta` 同時偵測兩者，自動識別並標色。

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
