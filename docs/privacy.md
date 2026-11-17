# Privacy Policy — Sessions (session-remote)

_Last updated: 2026-11-16_

**English**

Sessions is a remote control for Claude Code sessions running on **your own Mac**.

- **We collect no data.** The app has no analytics, no tracking, no ads, no third-party SDKs and no account.
  The developer runs no server and never receives anything you do in the app.
- **The only server the app talks to is the address you enter** (or scan from the pairing QR code): the
  session-remote service you installed on your own Mac, usually reached over your own Tailscale network.
  Session lists, conversations, your replies and photos you choose to send go only between your iPhone and that Mac.
- **Stored on the iPhone:** the Mac's address and access code (app settings, the Keychain, and an App Group
  shared with the home-screen widget), unsent drafts. Deleting the app removes them.
- **Photos:** only the photos you pick are read, and they are sent only to your Mac.
- **Notifications:** if you allow notifications, the push token is sent only to your own Mac.
  Builds distributed through TestFlight cannot receive pushes from other people's Macs, because sending requires
  the developer's private key; in practice the public build receives no push notifications.
- **Demo mode** ("Take a Look (Demo Mode)" on the pairing screen) uses built-in sample data and makes no network requests.

Questions: open an issue at <https://github.com/bruuucechang/session-remote/issues>.

---

**繁體中文**

Sessions 是用 iPhone 操作**你自己 Mac 上** Claude Code 的遙控器。

- **不收集任何資料。** 沒有分析、追蹤、廣告、第三方套件，也不用註冊帳號。開發者沒有架任何伺服器，收不到你在 app 裡做的任何事。
- **app 只連你填的網址**（或掃配對 QR code 得到的）：也就是你裝在自己 Mac 上的 session-remote 服務，通常走你自己的 Tailscale。
  session 列表、對話、你的回覆、你選來傳的照片，只在你的 iPhone 和那台 Mac 之間傳。
- **存在 iPhone 上的**：Mac 的網址與通行碼（app 設定、鑰匙圈，以及跟主畫面小工具共用的 App Group）、還沒送出的草稿。刪掉 app 就一起刪掉。
- **照片**：只讀你挑的那幾張，只傳給你的 Mac。
- **通知**：允許通知的話，推播 token 只送給你自己的 Mac。TestFlight 版收不到別人 Mac 送的推播（送推播要開發者的私鑰），所以公開版實際上沒有推播。
- **展示模式**（配對頁的「先看看」）用 app 內建的假資料，不連網。

有問題請到 <https://github.com/bruuucechang/session-remote/issues> 開 issue。
