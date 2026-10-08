-- =====================================================================
-- 02_features_churn.sql
-- Ingeniería de features por cliente para un modelo de churn.
--
-- Entrada : tabla online_retail (cargada por main.py)
-- Salida  : tabla customer_features, una fila por cliente
-- Motor   : SQLite 3.25+ (soporte de funciones de ventana)
--
-- Ventana de análisis
--   * Desde 2010-12-01 (inclusive) hasta 2011-12-01 (exclusive):
--     12 meses COMPLETOS.
--   * Diciembre 2011 se excluye porque el dataset termina el 2011-12-09;
--     un mes parcial subestimaría el gasto del "último mes" y sesgaría
--     la feature de tendencia.
--   * La fecha de corte (2011-12-01) es el "hoy" del modelo: toda feature
--     se calcula solo con información anterior a esa fecha.
--
-- Funciones de ventana utilizadas
--   * LAG()            -> días entre pedidos consecutivos
--   * ROW_NUMBER()     -> número de orden del pedido dentro del cliente
--   * AVG() OVER       -> promedio histórico del gasto mensual (Trend)
--   * SUM()/COUNT() OVER -> meses con compra y meses como cliente
--   * RANK()           -> ranking de clientes por gasto total
--   * NTILE()          -> scores RFM en quintiles
-- =====================================================================

DROP TABLE IF EXISTS customer_features;

CREATE TABLE customer_features AS

WITH parametros AS (
    SELECT
        '2010-12-01' AS fecha_inicio,
        '2011-12-01' AS fecha_corte,                               -- exclusive
        '2011-11-01' AS mes_ultimo                                 -- último mes completo
),

-- ---------------------------------------------------------------------
-- 1. Líneas de venta válidas
--    Se descartan: clientes anónimos, cancelaciones (factura 'C...'),
--    cantidades <= 0, precios <= 0 y fechas fuera de la ventana.
-- ---------------------------------------------------------------------
lineas_validas AS (
    SELECT
        ret.customer_id,
        ret.invoice_no,
        ret.invoice_ts,
        ret.quantity * ret.unit_price AS importe_linea
    FROM online_retail AS ret
    CROSS JOIN parametros AS par
    WHERE ret.customer_id IS NOT NULL
      AND SUBSTR(ret.invoice_no, 1, 1) <> 'C'
      AND ret.quantity   > 0
      AND ret.unit_price > 0
      AND ret.invoice_ts >= par.fecha_inicio
      AND ret.invoice_ts <  par.fecha_corte
),

-- ---------------------------------------------------------------------
-- 2. Pedidos: una fila por factura (cliente + invoice_no)
-- ---------------------------------------------------------------------
pedidos AS (
    SELECT
        lin.customer_id,
        lin.invoice_no,
        MIN(lin.invoice_ts)    AS fecha_pedido,
        SUM(lin.importe_linea) AS importe_pedido
    FROM lineas_validas AS lin
    GROUP BY
        lin.customer_id,
        lin.invoice_no
),

-- ---------------------------------------------------------------------
-- 3. Secuencia de pedidos por cliente (funciones de ventana LAG y ROW_NUMBER)
-- ---------------------------------------------------------------------
pedidos_secuencia AS (
    SELECT
        ped.customer_id,
        ped.invoice_no,
        ped.fecha_pedido,
        ped.importe_pedido,
        ROW_NUMBER() OVER (
            PARTITION BY ped.customer_id
            ORDER BY ped.fecha_pedido, ped.invoice_no
        ) AS nro_pedido,
        JULIANDAY(DATE(ped.fecha_pedido))
          - JULIANDAY(DATE(LAG(ped.fecha_pedido) OVER (
                PARTITION BY ped.customer_id
                ORDER BY ped.fecha_pedido, ped.invoice_no
            ))) AS dias_desde_pedido_anterior
    FROM pedidos AS ped
),

-- ---------------------------------------------------------------------
-- 4. Métricas RFM base y de comportamiento por cliente
-- ---------------------------------------------------------------------
metricas_cliente AS (
    SELECT
        seq.customer_id,
        DATE(MIN(seq.fecha_pedido))                     AS fecha_primer_pedido,
        DATE(MAX(seq.fecha_pedido))                     AS fecha_ultimo_pedido,
        COUNT(DISTINCT seq.invoice_no)                  AS frequency,
        SUM(seq.importe_pedido)                         AS monetary,
        AVG(seq.importe_pedido)                         AS ticket_promedio,
        AVG(seq.dias_desde_pedido_anterior)             AS dias_promedio_entre_pedidos
    FROM pedidos_secuencia AS seq
    GROUP BY
        seq.customer_id
),

-- ---------------------------------------------------------------------
-- 5. Cancelaciones dentro de la misma ventana
--    Se cuentan aparte: son una señal de insatisfacción útil para churn.
-- ---------------------------------------------------------------------
cancelaciones AS (
    SELECT
        ret.customer_id,
        COUNT(DISTINCT ret.invoice_no) AS cantidad_cancelaciones
    FROM online_retail AS ret
    CROSS JOIN parametros AS par
    WHERE ret.customer_id IS NOT NULL
      AND SUBSTR(ret.invoice_no, 1, 1) = 'C'
      AND ret.invoice_ts >= par.fecha_inicio
      AND ret.invoice_ts <  par.fecha_corte
    GROUP BY
        ret.customer_id
),

-- ---------------------------------------------------------------------
-- 6. Grilla cliente x mes
--    Cada cliente tiene una fila por mes desde su primera compra hasta el
--    último mes completo, compre o no ese mes. Así los meses sin compras
--    valen 0 (y no faltan), lo que es clave para un promedio correcto.
-- ---------------------------------------------------------------------
meses AS (
    SELECT DISTINCT
        DATE(lin.invoice_ts, 'start of month') AS mes
    FROM lineas_validas AS lin
),

gasto_por_mes AS (
    SELECT
        lin.customer_id,
        DATE(lin.invoice_ts, 'start of month') AS mes,
        SUM(lin.importe_linea)                 AS gasto
    FROM lineas_validas AS lin
    GROUP BY
        lin.customer_id,
        DATE(lin.invoice_ts, 'start of month')
),

grilla_cliente_mes AS (
    SELECT
        mcl.customer_id,
        mes.mes,
        COALESCE(gpm.gasto, 0) AS gasto_mes
    FROM metricas_cliente AS mcl
    INNER JOIN meses AS mes
        ON mes.mes >= DATE(mcl.fecha_primer_pedido, 'start of month')
    LEFT JOIN gasto_por_mes AS gpm
        ON  gpm.customer_id = mcl.customer_id
        AND gpm.mes         = mes.mes
),

-- ---------------------------------------------------------------------
-- 7. Tendencia (Trend) con AVG() OVER (PARTITION BY ...)
--    Promedio histórico = promedio del gasto mensual de los meses
--    ANTERIORES al mes evaluado (ROWS ... 1 PRECEDING), para no incluir
--    el propio último mes en su referencia.
-- ---------------------------------------------------------------------
tendencia_mensual AS (
    SELECT
        gcm.customer_id,
        gcm.mes,
        gcm.gasto_mes,
        AVG(gcm.gasto_mes) OVER (
            PARTITION BY gcm.customer_id
            ORDER BY gcm.mes
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS gasto_promedio_historico,
        SUM(CASE WHEN gcm.gasto_mes > 0 THEN 1 ELSE 0 END) OVER (
            PARTITION BY gcm.customer_id
        ) AS meses_con_compra,
        COUNT(*) OVER (
            PARTITION BY gcm.customer_id
        ) AS meses_como_cliente
    FROM grilla_cliente_mes AS gcm
),

tendencia_ultimo_mes AS (
    SELECT
        tdm.customer_id,
        tdm.gasto_mes                         AS gasto_ultimo_mes,
        tdm.gasto_promedio_historico,
        tdm.meses_con_compra,
        tdm.meses_como_cliente
    FROM tendencia_mensual AS tdm
    CROSS JOIN parametros AS par
    WHERE tdm.mes = par.mes_ultimo
)

-- ---------------------------------------------------------------------
-- 8. Dataset final de features (una fila por cliente)
-- ---------------------------------------------------------------------
SELECT
    mcl.customer_id,

    -- Recency, Frequency, Monetary
    CAST(JULIANDAY(par.fecha_corte) - JULIANDAY(mcl.fecha_ultimo_pedido) AS INTEGER)
                                                                   AS recency_dias,
    mcl.frequency,
    ROUND(mcl.monetary, 2)                                         AS monetary,

    -- Comportamiento complementario
    ROUND(mcl.ticket_promedio, 2)                                  AS ticket_promedio,
    CAST(JULIANDAY(par.fecha_corte) - JULIANDAY(mcl.fecha_primer_pedido) AS INTEGER)
                                                                   AS antiguedad_dias,
    -- Con un solo pedido no hay intervalo observado: se usa el tiempo
    -- transcurrido desde ese pedido (cota inferior del intervalo real).
    ROUND(
        COALESCE(
            mcl.dias_promedio_entre_pedidos,
            JULIANDAY(par.fecha_corte) - JULIANDAY(mcl.fecha_ultimo_pedido)
        ), 1
    )                                                              AS dias_promedio_entre_pedidos,
    tum.meses_con_compra,
    ROUND(tum.meses_con_compra * 1.0 / tum.meses_como_cliente, 3)  AS ratio_meses_activos,
    COALESCE(can.cantidad_cancelaciones, 0)                        AS cantidad_cancelaciones,

    -- Trend: último mes completo vs. promedio histórico mensual
    ROUND(tum.gasto_ultimo_mes, 2)                                 AS gasto_ultimo_mes,
    ROUND(COALESCE(tum.gasto_promedio_historico, 0), 2)            AS gasto_promedio_historico,
    ROUND(
        tum.gasto_ultimo_mes - COALESCE(tum.gasto_promedio_historico, tum.gasto_ultimo_mes), 2
    )                                                              AS trend_delta_gasto,
    CASE
        WHEN tum.gasto_promedio_historico IS NULL THEN 1           -- sin historia previa
        ELSE 0
    END                                                            AS es_cliente_nuevo,

    -- Rankings y scores con funciones de ventana
    -- (customer_id se usa como desempate para que los quintiles sean reproducibles)
    RANK() OVER (ORDER BY ROUND(mcl.monetary, 2) DESC)             AS ranking_monetary,
    NTILE(5) OVER (
        ORDER BY mcl.fecha_ultimo_pedido ASC, mcl.customer_id
    )                                                              AS score_r,   -- 5 = más reciente
    NTILE(5) OVER (
        ORDER BY mcl.frequency ASC, mcl.monetary ASC, mcl.customer_id
    )                                                              AS score_f,   -- 5 = más frecuente
    NTILE(5) OVER (
        ORDER BY mcl.monetary ASC, mcl.customer_id
    )                                                              AS score_m    -- 5 = mayor gasto

FROM metricas_cliente AS mcl
CROSS JOIN parametros AS par
INNER JOIN tendencia_ultimo_mes AS tum
    ON tum.customer_id = mcl.customer_id
LEFT JOIN cancelaciones AS can
    ON can.customer_id = mcl.customer_id;

CREATE UNIQUE INDEX idx_customer_features_id ON customer_features (customer_id);
