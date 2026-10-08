-- =====================================================================
-- 01_crear_tablas.sql
-- Crea la tabla de transacciones crudas donde main.py carga el CSV.
-- Motor: SQLite (incluido en Python, no requiere instalar nada).
-- =====================================================================

DROP TABLE IF EXISTS online_retail;

CREATE TABLE online_retail (
    invoice_no    TEXT    NOT NULL,   -- Nro. de factura ('C...' = cancelación)
    stock_code    TEXT,               -- Código de producto
    description   TEXT,               -- Descripción del producto
    quantity      INTEGER NOT NULL,   -- Unidades de la línea
    invoice_ts    TEXT    NOT NULL,   -- Fecha y hora, formato 'YYYY-MM-DD HH:MM:SS'
    unit_price    REAL    NOT NULL,   -- Precio unitario (GBP)
    customer_id   INTEGER,            -- NULL si la compra fue anónima
    country       TEXT                -- País del cliente
);
