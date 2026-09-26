-- Secara bawaan PUBLIC boleh CONNECT ke setiap database. Isolasi tenant
-- bergantung pada pencabutan hak itu: role milik satu service hanya boleh
-- masuk ke database-nya sendiri. Skrip jatah tenant mencabutnya juga untuk
-- setiap database baru.
REVOKE CONNECT, TEMPORARY ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT, TEMPORARY ON DATABASE template1 FROM PUBLIC;
