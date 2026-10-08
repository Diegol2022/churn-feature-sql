# Ingeniería de Features con SQL Analítico Avanzado

Pre-entrega: transformación de transacciones crudas de un e-commerce en un **dataset de entrenamiento con una fila por cliente**, listo para un modelo de predicción de abandono (**churn**). Todo el cálculo de features se hace en SQL, con CTEs, agregaciones y funciones de ventana.

El proyecto se ejecuta con **un solo comando** (`python main.py`). Solo necesita Python: la base de datos es SQLite, que viene incluida en Python, así que no hay que instalar ningún motor de base de datos ni paquetes adicionales.

---

## Cómo ejecutar el proyecto (paso a paso por terminal)

### Requisitos

- **Python 3.8 o superior** (trae SQLite 3.25+, necesario para las funciones de ventana).
- **Git**, para clonar el repositorio.

Para verificar que los tenés instalados, abrí una terminal y ejecutá:

```bash
python --version
git --version
```

> En Mac y Linux, si `python` no existe, usá `python3` en todos los comandos.
> En Windows podés usar PowerShell o la terminal de VS Code.

### Paso 1: Clonar el repositorio

```bash
git clone https://github.com/TU_USUARIO/churn-features-sql.git
cd churn-features-sql
```

### Paso 2: Crear el entorno virtual e instalar dependencias

El proyecto no tiene dependencias externas (`requirements.txt` está vacío a propósito), así que este paso es opcional. Se incluye porque es la práctica recomendada para aislar cada proyecto de Python.

En Mac / Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

En Windows (PowerShell):

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

> Si PowerShell bloquea la activación, ejecutá una vez `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` y volvé a intentarlo.

### Paso 3: Descargar el dataset

1. Descargá el dataset **Online Retail** desde Kaggle: <https://www.kaggle.com/datasets/carrie1/ecommerce-data> (botón *Download*). Se descarga un archivo `archive.zip` que contiene `data.csv`.
2. Copiá el archivo a la carpeta `data/` del proyecto. Tenés dos opciones (cualquiera funciona):
   - **Opción A:** copiar el zip tal cual, como `data/archive.zip`.
   - **Opción B:** descomprimirlo y dejar el CSV como `data/data.csv`.

El dataset no se incluye en el repositorio porque pesa 45 MB.

### Paso 4: Ejecutar el pipeline

Si dejaste el CSV como `data/data.csv` (opción B):

```bash
python main.py
```

Si dejaste el zip (opción A):

```bash
python main.py --input data/archive.zip
```

El proceso tarda entre 10 y 30 segundos y muestra algo así:

```
SQLite 3.45.1
[1/3] Cargando datos desde data/archive.zip ...
      541,909 filas cargadas en la tabla online_retail
[2/3] Ejecutando sql/02_features_churn.sql ...
      4,297 clientes en la tabla customer_features
[3/3] Exportando resultado a output/customer_features.csv ...

Resumen de features
  Clientes                        : 4,297
  Recency promedio (días)         : 91.5
  Frequency promedio (pedidos)    : 4.1
  Monetary promedio (GBP)         : 1,953.27
  Clientes con tendencia negativa : 2,886
...
```

### Paso 5: Ver los resultados

Se generan dos archivos en la carpeta `output/`:

| Archivo | Contenido |
|---|---|
| `output/customer_features.csv` | El dataset de features (una fila por cliente). Se abre con Excel, Google Sheets o pandas |
| `output/ecommerce.db` | La base SQLite con las tablas `online_retail` y `customer_features`, para hacer consultas propias |

Para consultar la base desde la terminal (opcional, requiere tener instalado el cliente `sqlite3`):

```bash
sqlite3 output/ecommerce.db "SELECT * FROM customer_features ORDER BY ranking_monetary LIMIT 10;"
```

También se puede abrir con cualquier cliente gráfico, como [DB Browser for SQLite](https://sqlitebrowser.org/) o DBeaver.

### Opciones del comando

```bash
python main.py --help
```

| Opción | Descripción | Valor por defecto |
|---|---|---|
| `--input` | Archivo de datos: `.csv` o `.zip` que lo contenga | `data/data.csv` |
| `--output` | CSV de salida con las features | `output/customer_features.csv` |
| `--db` | Archivo de base de datos SQLite | `output/ecommerce.db` |

### Problemas frecuentes

| Mensaje | Solución |
|---|---|
| `no se encontró el archivo de datos` | Revisá que el archivo esté en `data/` con el nombre correcto, o indicá la ruta con `--input` |
| `python: command not found` | Usá `python3` en lugar de `python` |
| `se necesita SQLite 3.25 o superior` | Actualizá Python a la versión 3.8 o superior |

---

## Estructura del repositorio

```
churn-features-sql/
├── main.py                         # Punto de entrada: ejecuta todo el pipeline
├── sql/
│   ├── 01_crear_tablas.sql         # Crea la tabla de transacciones crudas
│   └── 02_features_churn.sql       # Consulta principal de features (funciones de ventana)
├── data/                           # Acá va el dataset (no se versiona)
├── output/
│   └── customer_features_muestra.csv   # Muestra del resultado (top 50 clientes)
├── requirements.txt                # Dependencias (ninguna externa)
├── .gitignore
└── README.md
```

### Qué hace `main.py`

1. Crea la base `output/ecommerce.db` ejecutando `sql/01_crear_tablas.sql`.
2. Lee el CSV (o el zip), convierte los tipos de datos (la fecha pasa de `12/1/2010 8:26` a `2010-12-01 08:26:00`) y carga las 541.909 filas en la tabla `online_retail`.
3. Ejecuta `sql/02_features_churn.sql`, que crea la tabla `customer_features`. **Toda la lógica de features está en este archivo SQL**; Python solo orquesta la carga y la exportación.
4. Exporta `customer_features` a CSV y muestra un resumen por pantalla.

---

## Dataset

**Online Retail** (UCI Machine Learning Repository): 541.909 líneas de factura de una tienda online del Reino Unido que vende artículos de regalo, entre el 01/12/2010 y el 09/12/2011.

| Columna | Descripción |
|---|---|
| `InvoiceNo` | Número de factura. Si empieza con `C`, es una cancelación |
| `StockCode` | Código de producto |
| `Description` | Nombre del producto |
| `Quantity` | Unidades por línea |
| `InvoiceDate` | Fecha y hora de la factura |
| `UnitPrice` | Precio unitario (libras esterlinas) |
| `CustomerID` | Identificador del cliente (≈25% de las líneas no lo tiene) |
| `Country` | País del cliente |

## Decisiones de preparación de datos

**Limpieza.** Para calcular las features de compra se descartan las líneas sin `CustomerID` (no se pueden atribuir a nadie), las cancelaciones (`InvoiceNo` que empieza con `C`), las cantidades ≤ 0 y los precios ≤ 0 (ajustes contables y regalos). Las cancelaciones no se descartan del todo: se cuentan aparte como feature.

**Ventana temporal y fecha de corte.** Se usan los 12 meses completos entre el 01/12/2010 y el 30/11/2011. La **fecha de corte es el 01/12/2011**: es el "hoy" del modelo, y ninguna feature usa información posterior. Diciembre 2011 se excluye a propósito porque el dataset termina el día 9: un mes con 9 días de datos haría parecer que todos los clientes bajaron su gasto y sesgaría la feature de tendencia. Además, esos días posteriores al corte pueden usarse más adelante para construir la etiqueta de churn sin fuga de información. Las fechas están centralizadas en la CTE `parametros`.

**Manejo de nulos.** Se construye una grilla cliente × mes que incluye todos los meses desde la primera compra de cada cliente, compre o no en ellos. Los meses sin compras valen **0** (vía `LEFT JOIN` + `COALESCE`) en lugar de no existir. Esto es clave: si se promediaran solo los meses con compra, un cliente que dejó de comprar mostraría un promedio alto y engañoso. El resto de las agregaciones también devuelven 0 o un valor definido en vez de `NULL`, y el dataset final no tiene ningún nulo.

## Funciones de ventana utilizadas

| Función | Para qué se usa |
|---|---|
| `LAG() OVER (PARTITION BY customer_id ORDER BY fecha_pedido)` | Días transcurridos entre cada pedido y el anterior del mismo cliente |
| `ROW_NUMBER() OVER (PARTITION BY customer_id ...)` | Número de orden de cada pedido dentro del cliente |
| `AVG() OVER (PARTITION BY customer_id ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)` | Promedio histórico del gasto mensual, excluyendo el mes evaluado |
| `SUM() OVER (PARTITION BY customer_id)` / `COUNT() OVER (...)` | Meses con compra y meses como cliente, sin colapsar filas |
| `RANK() OVER (ORDER BY monetary DESC)` | Ranking de clientes por gasto total |
| `NTILE(5) OVER (...)` | Scores R, F y M en quintiles |

## Features generadas y su utilidad para churn

### Métricas RFM

| Feature | Cálculo | Por qué sirve para predecir churn |
|---|---|---|
| `recency_dias` | Días entre la fecha de corte y la última compra | Es la señal más fuerte de abandono: cuanto más tiempo pasa sin comprar, más probable es que el cliente ya se haya ido |
| `frequency` | Cantidad de pedidos únicos (`COUNT(DISTINCT invoice_no)`) | Los clientes que compran seguido tienen el hábito incorporado y abandonan menos; los de una sola compra son los de mayor riesgo |
| `monetary` | Gasto total acumulado (`SUM(quantity * unit_price)`) | Mide el valor del cliente y su compromiso con la tienda; también permite priorizar a quién retener |

### Tendencia (Trend)

| Feature | Cálculo | Por qué sirve para predecir churn |
|---|---|---|
| `gasto_ultimo_mes` | Gasto en noviembre 2011 (último mes completo); 0 si no compró | Actividad más reciente, a nivel mensual |
| `gasto_promedio_historico` | Promedio del gasto mensual en los meses previos, desde la primera compra del cliente (`AVG() OVER` con `ROWS ... 1 PRECEDING`) | Línea base del comportamiento normal de cada cliente |
| `trend_delta_gasto` | `gasto_ultimo_mes - gasto_promedio_historico` | Un valor negativo indica que el cliente está gastando menos que su propia costumbre. Captura el abandono **gradual**, que RFM no ve: un cliente puede tener buena frecuencia histórica y aun así estar desacelerándose |
| `es_cliente_nuevo` | 1 si su primera compra fue en el último mes (no tiene historia para comparar) | Para estos clientes el delta se fija en 0 de forma coherente; el flag le avisa al modelo que no es un "0 real" |

El promedio histórico se calcula **solo desde el primer mes de cada cliente**. Si se tomaran los 12 meses para todos, un cliente que llegó en septiembre tendría su promedio diluido por meses en los que todavía no existía.

### Features de comportamiento complementarias

| Feature | Cálculo | Por qué sirve para predecir churn |
|---|---|---|
| `ticket_promedio` | Gasto promedio por pedido | Diferencia clientes de compras grandes y esporádicas (mayoristas) de clientes de compras chicas y frecuentes, que tienen patrones de abandono distintos |
| `antiguedad_dias` | Días desde la primera compra hasta la fecha de corte | Los clientes recientes todavía no consolidaron el hábito y tienden a abandonar más |
| `dias_promedio_entre_pedidos` | Promedio de los intervalos calculados con `LAG()`. Para clientes con un solo pedido se usa el tiempo desde ese pedido (cota inferior del intervalo real) en lugar de `NULL` | Permite comparar la recencia con el ritmo propio del cliente: 60 días sin comprar es alarmante para quien compra cada semana, pero normal para quien compra cada dos meses |
| `meses_con_compra` | Meses con al menos una compra | Constancia del cliente a lo largo del tiempo |
| `ratio_meses_activos` | `meses_con_compra / meses_como_cliente` | Regularidad normalizada por antigüedad; un ratio bajo indica un cliente intermitente |
| `cantidad_cancelaciones` | Facturas canceladas en la ventana (0 si no tuvo) | Las cancelaciones y devoluciones suelen ser señal de insatisfacción |

### Rankings y scores

| Feature | Cálculo | Utilidad |
|---|---|---|
| `ranking_monetary` | `RANK()` por gasto total (1 = mayor gasto) | Priorizar campañas de retención sobre clientes de alto valor |
| `score_r`, `score_f`, `score_m` | Quintiles con `NTILE(5)`, donde 5 es siempre lo mejor (más reciente, más frecuente, mayor gasto) | Segmentación RFM clásica e interpretable; útil para modelos simples y para explicar resultados al negocio |

## Resultado

- 4.297 clientes, una fila por cliente y ninguna columna con nulos.
- Recency promedio: 91,5 días; frequency promedio: 4,1 pedidos; monetary promedio: £1.953.
- 2.886 clientes tienen `trend_delta_gasto` negativo: gastaron en noviembre menos que su promedio histórico, en la mayoría de los casos porque no compraron.
- Recency, Frequency, Monetary y Trend se verificaron contra un cálculo independiente en Python/pandas, con coincidencia exacta salvo redondeo.

## Próximo paso: la etiqueta de churn

Este dataset contiene solo las variables predictoras (X). Para entrenar el modelo falta definir la etiqueta (y), por ejemplo: *el cliente se considera churn si no compra en los N días posteriores a la fecha de corte*. Como el dataset termina el 09/12/2011, una opción realista es mover la fecha de corte hacia atrás (por ejemplo, al 01/09/2011) en la CTE `parametros` y usar los meses siguientes como período de observación de la etiqueta.
