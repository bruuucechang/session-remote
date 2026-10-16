"""**唯一可以碰持久化的地方。**

這個專案目前沒有資料庫（scaffold 跑的是 --no-db）。之後要接的時候：

    1. 建 db/schema.sql，createdb <name>，psql -f 套用
    2. 在 backend/app/db.py 建 engine 與 get_session()
    3. 資料表的 ORM 對應放 backend/app/models/
    4. 存取邏輯**只**寫在這個目錄底下

規則不變：只有這裡能 import sqlalchemy 或寫 SQL，services 與 routers 都不行。
"""
