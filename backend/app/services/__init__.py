"""業務邏輯。

規則：**不知道 HTTP，也不寫 SQL。** 不 import fastapi、不 import sqlalchemy。
要碰資料就叫 repositories。錯誤用自訂例外表達，由 routers 翻成狀態碼。

這一層是唯一值得單元測試的地方——它一旦沾到 HTTP 就要起 test client，
沾到 SQL 就要起資料庫，兩個都很快讓人放棄寫測試。
"""
