# session-remote

## 埠位

| | |
|---|---|
| web | 5390 |
| api | 5391 |

由 `proj new` 分配，已登記在 `~/Projects/office/projects.json`，不會跟其他專案相撞。

## 指令

```bash
proj start session-remote
proj logs session-remote -f
proj stop session-remote
```

## 作業圖

`project-map.json` 是這個專案的工作關係圖與 SOP，Dashboard 在
[/map](http://localhost:5250/map?p=session-remote) 渲染。

`proj new` 只填了埠；**節點與 SOP 要自己補**。步驟裡的 `touches` 指回節點的
id，那是關係圖與 SOP 唯一的接點。踩過的坑寫進步驟的 `trap`——那一欄的用途
是讓下一個人（或下一個 session）不用再踩一次。格式見 `~/Projects/office/CLAUDE.md`。
