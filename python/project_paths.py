"""Repository paths and local-only generated data."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLES = Path(os.environ.get("OLIST_TABLES_DIR", str(ROOT / "outputs" / "tables"))).resolve()
FIGURES = Path(os.environ.get("OLIST_FIGURES_DIR", str(ROOT / "figures"))).resolve()
TABLES.mkdir(parents=True, exist_ok=True)
FIGURES.mkdir(parents=True, exist_ok=True)
