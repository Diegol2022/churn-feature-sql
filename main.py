"""
main.py - Pipeline de ingeniería de features para churn con SQL.

Ejecuta todo el proceso con un solo comando:
    1. Crea la base de datos SQLite y la tabla de transacciones.
    2. Carga el dataset Online Retail (data.csv o el .zip descargado).
    3. Ejecuta la consulta de features (sql/02_features_churn.sql).
    4. Exporta el resultado a output/customer_features.csv.
    5. Muestra un resumen por pantalla.

Uso:
    python main.py
    python main.py --input data/archive.zip
    python main.py --input ruta/a/data.csv --output resultados.csv

Solo usa la biblioteca estándar de Python (no requiere instalar paquetes).
"""

import argparse
import csv
import io
import sqlite3
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
SQL_CREAR_TABLAS = RAIZ / "sql" / "01_crear_tablas.sql"
SQL_FEATURES = RAIZ / "sql" / "02_features_churn.sql"

ENTRADA_POR_DEFECTO = RAIZ / "data" / "data.csv"
BASE_POR_DEFECTO = RAIZ / "output" / "ecommerce.db"
SALIDA_POR_DEFECTO = RAIZ / "output" / "customer_features.csv"

COLUMNAS_ESPERADAS = [
    "InvoiceNo", "StockCode", "Description", "Quantity",
    "InvoiceDate", "UnitPrice", "CustomerID", "Country",
]


def ruta_corta(ruta):
    """Muestra la ruta relativa a la carpeta actual cuando es posible."""
    try:
        return ruta.resolve().relative_to(Path.cwd())
    except ValueError:
        return ruta


def leer_argumentos():
    parser = argparse.ArgumentParser(
        description="Genera features de churn por cliente a partir del dataset Online Retail."
    )
    parser.add_argument(
        "--input", type=Path, default=ENTRADA_POR_DEFECTO,
        help="Archivo de datos: data.csv o el .zip que lo contiene (por defecto: data/data.csv)",
    )
    parser.add_argument(
        "--db", type=Path, default=BASE_POR_DEFECTO,
        help="Archivo de base de datos SQLite a crear (por defecto: output/ecommerce.db)",
    )
    parser.add_argument(
        "--output", type=Path, default=SALIDA_POR_DEFECTO,
        help="CSV de salida con las features (por defecto: output/customer_features.csv)",
    )
    return parser.parse_args()


def abrir_csv(ruta):
    """Devuelve un archivo de texto con el CSV, sea un .csv o un .zip que lo contiene."""
    if not ruta.exists():
        sys.exit(
            f"ERROR: no se encontró el archivo de datos '{ruta}'.\n"
            "Descargá el dataset y guardalo como data/data.csv "
            "(o indicá la ruta con --input). Ver README.md."
        )
    if ruta.suffix.lower() == ".zip":
        archivo_zip = zipfile.ZipFile(ruta)
        csvs = [n for n in archivo_zip.namelist() if n.lower().endswith(".csv")]
        if not csvs:
            sys.exit(f"ERROR: el zip '{ruta}' no contiene ningún archivo .csv.")
        return io.TextIOWrapper(archivo_zip.open(csvs[0]), encoding="latin-1", newline="")
    # El dataset original está codificado en LATIN-1 (ISO-8859-1).
    return open(ruta, encoding="latin-1", newline="")


def convertir_fila(fila):
    """Convierte una fila del CSV a los tipos de la tabla online_retail."""
    fecha = datetime.strptime(fila["InvoiceDate"], "%m/%d/%Y %H:%M")
    cliente = fila["CustomerID"].strip()
    return (
        fila["InvoiceNo"].strip(),
        fila["StockCode"].strip(),
        fila["Description"].strip() or None,
        int(fila["Quantity"]),
        fecha.strftime("%Y-%m-%d %H:%M:%S"),
        float(fila["UnitPrice"]),
        int(float(cliente)) if cliente else None,
        fila["Country"].strip(),
    )


def cargar_datos(conexion, ruta_entrada):
    conexion.executescript(SQL_CREAR_TABLAS.read_text(encoding="utf-8"))

    with abrir_csv(ruta_entrada) as archivo:
        lector = csv.DictReader(archivo)
        faltantes = set(COLUMNAS_ESPERADAS) - set(lector.fieldnames or [])
        if faltantes:
            sys.exit(f"ERROR: al CSV le faltan las columnas: {', '.join(sorted(faltantes))}")

        conexion.executemany(
            "INSERT INTO online_retail VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (convertir_fila(fila) for fila in lector),
        )

    conexion.execute("CREATE INDEX idx_retail_customer ON online_retail (customer_id)")
    conexion.commit()
    return conexion.execute("SELECT COUNT(*) FROM online_retail").fetchone()[0]


def generar_features(conexion):
    conexion.executescript(SQL_FEATURES.read_text(encoding="utf-8"))
    conexion.commit()
    return conexion.execute("SELECT COUNT(*) FROM customer_features").fetchone()[0]


def exportar_csv(conexion, ruta_salida):
    cursor = conexion.execute("SELECT * FROM customer_features ORDER BY customer_id")
    columnas = [descripcion[0] for descripcion in cursor.description]
    with open(ruta_salida, "w", encoding="utf-8", newline="") as archivo:
        escritor = csv.writer(archivo)
        escritor.writerow(columnas)
        escritor.writerows(cursor)


def mostrar_resumen(conexion):
    resumen = conexion.execute(
        """
        SELECT
            COUNT(*)                                         AS clientes,
            ROUND(AVG(recency_dias), 1)                      AS recency_prom,
            ROUND(AVG(frequency), 1)                         AS frequency_prom,
            ROUND(AVG(monetary), 2)                          AS monetary_prom,
            SUM(CASE WHEN trend_delta_gasto < 0 THEN 1 END)  AS trend_negativo
        FROM customer_features
        """
    ).fetchone()
    print("\nResumen de features")
    print(f"  Clientes                        : {resumen[0]:,}")
    print(f"  Recency promedio (días)         : {resumen[1]}")
    print(f"  Frequency promedio (pedidos)    : {resumen[2]}")
    print(f"  Monetary promedio (GBP)         : {resumen[3]:,}")
    print(f"  Clientes con tendencia negativa : {resumen[4]:,}")

    print("\nTop 5 clientes por gasto total:")
    cursor = conexion.execute(
        """
        SELECT customer_id, recency_dias, frequency, monetary, trend_delta_gasto
        FROM customer_features
        ORDER BY ranking_monetary
        LIMIT 5
        """
    )
    print(f"  {'cliente':>8} {'recency':>8} {'frequency':>10} {'monetary':>12} {'trend':>11}")
    for cliente, recency, frequency, monetary, trend in cursor:
        print(f"  {cliente:>8} {recency:>8} {frequency:>10} {monetary:>12,.2f} {trend:>11,.2f}")


def main():
    args = leer_argumentos()
    args.db.parent.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.db.exists():
        args.db.unlink()                      # cada corrida parte de una base limpia

    print(f"SQLite {sqlite3.sqlite_version}")
    if sqlite3.sqlite_version_info < (3, 25, 0):
        sys.exit("ERROR: se necesita SQLite 3.25 o superior (funciones de ventana).")

    inicio = time.time()
    conexion = sqlite3.connect(args.db)
    try:
        print(f"[1/3] Cargando datos desde {ruta_corta(args.input)} ...")
        filas = cargar_datos(conexion, args.input)
        print(f"      {filas:,} filas cargadas en la tabla online_retail")

        print(f"[2/3] Ejecutando {SQL_FEATURES.relative_to(RAIZ)} ...")
        clientes = generar_features(conexion)
        print(f"      {clientes:,} clientes en la tabla customer_features")

        print(f"[3/3] Exportando resultado a {ruta_corta(args.output)} ...")
        exportar_csv(conexion, args.output)

        mostrar_resumen(conexion)
    finally:
        conexion.close()

    print(f"\nListo en {time.time() - inicio:.1f} s. Base de datos: {ruta_corta(args.db)}")


if __name__ == "__main__":
    main()
