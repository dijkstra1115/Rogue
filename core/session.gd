## 跨場景的啟動資訊（static var，整個程序存活期間有效）。
##
## main.gd 在啟動時寫入，之後任何場景（例如 arena 的 game_world）
## 都從這裡查詢執行模式，不必重複解析命令列或 feature。
##
## 刻意用 static var 而不是 autoload：不依賴場景樹，
## headless 測試（--script 模式）也能正常編譯與使用。
class_name Session
extends RefCounted

## 是否為專用伺服器模式（匯出帶 dedicated_server feature，或命令列 --server）
static var is_dedicated_server: bool = false

## --join <ip> 啟動參數（空字串代表沒有指定）
static var join_ip: String = ""

## --quit-after-ticks <n>：世界跑滿 n 個 tick 自動結束（headless 煙霧測試用；0 = 不啟用）
static var quit_after_ticks: int = 0

## --bot：本地輸入改用合成的繞圈移動（headless 測試預測/和解用；沒有真的輸入裝置也能動）
static var bot_mode: bool = false
