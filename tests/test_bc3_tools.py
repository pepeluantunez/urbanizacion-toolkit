"""
Smoke tests para bc3_tools.py
==============================
Detectan regresiones en la firma de funciones internas y en la ejecución
de los comandos principales contra un fixture mínimo real.

Bug de referencia corregido:
    cmd_export hacía `total, ok = _precio_calculado(...)` pero la función
    devuelve 3 valores → ValueError al desempaquetar.
"""

import sys
import shutil
from pathlib import Path

import pytest

# ── Rutas ────────────────────────────────────────────────────────────────────

TOOLKIT_ROOT = Path(__file__).parent.parent
BC3_MODULE   = TOOLKIT_ROOT / "tools" / "python"
FIXTURE      = Path(__file__).parent / "fixtures" / "minimal.bc3"

# Añadir tools/python al path para poder importar bc3_tools directamente
if str(BC3_MODULE) not in sys.path:
    sys.path.insert(0, str(BC3_MODULE))

import bc3_tools  # noqa: E402  (import después de sys.path)


# ── Fixture mínimo ───────────────────────────────────────────────────────────
#
# CAP01 (EA) — capítulo
#   PAR01 (m2, 15.0000 €) — partida con ~D
#     └─ REC01 (h, 15.0000 €) × factor=1 × rendimiento=1.0000
#
# Precio PAR01 declarado == calculado (15.0000), diff=0 → recalc no toca nada.

def _bc3():
    """Helper: parsea el fixture y lo devuelve."""
    return bc3_tools.parse_bc3(str(FIXTURE))


# ─────────────────────────────────────────────────────────────────────────────
# 1. _precio_calculado — firma de retorno
# ─────────────────────────────────────────────────────────────────────────────

class TestPrecioCalculado:

    def test_devuelve_exactamente_tres_valores(self):
        """Regresión directa del bug: desempaquetar debe funcionar con 3 variables."""
        bc3 = _bc3()
        result = bc3_tools._precio_calculado(bc3, "PAR01")
        # Si devolviera 2 valores, la línea anterior habría fallado en versiones
        # con el bug. Verificamos explícitamente la cardinalidad.
        assert len(result) == 3, (
            f"_precio_calculado devuelve {len(result)} valores; se esperan 3. "
            "El bug original era desempaquetar solo 2."
        )

    def test_tipos_del_retorno(self):
        """total=float|None, ok=bool, missing=list."""
        bc3 = _bc3()
        total, ok, missing = bc3_tools._precio_calculado(bc3, "PAR01")
        assert isinstance(total, float)
        assert isinstance(ok, bool)
        assert isinstance(missing, list)

    def test_valor_calculado_correcto(self):
        """REC01(15€) × factor=1 × rend=1 → total=15.0 para PAR01."""
        bc3 = _bc3()
        total, ok, missing = bc3_tools._precio_calculado(bc3, "PAR01")
        assert ok is True
        assert missing == []
        assert abs(total - 15.0) < 0.001, f"total esperado ≈15.0, obtenido {total}"

    def test_sin_descomp_devuelve_none_false(self):
        """Código sin ~D → (None, False, [])."""
        bc3 = _bc3()
        total, ok, missing = bc3_tools._precio_calculado(bc3, "REC01")
        assert ok is False
        assert total is None
        assert missing == []

    def test_codigo_inexistente(self):
        """Código que no existe en el bc3 → (None, False, [])."""
        bc3 = _bc3()
        total, ok, missing = bc3_tools._precio_calculado(bc3, "INEXISTENTE")
        assert ok is False
        assert total is None


# ─────────────────────────────────────────────────────────────────────────────
# 2. parse_bc3 — estructura del fixture
# ─────────────────────────────────────────────────────────────────────────────

class TestParseBc3:

    def test_conceptos_presentes(self):
        bc3 = _bc3()
        assert "CAP01" in bc3["conceptos"]
        assert "PAR01" in bc3["conceptos"]
        assert "REC01" in bc3["conceptos"]

    def test_tipo_capitulo(self):
        bc3 = _bc3()
        assert bc3["conceptos"]["CAP01"]["tipo"] == "EA"

    def test_descomp_par01(self):
        bc3 = _bc3()
        assert "PAR01" in bc3["descomps"]
        comps = bc3["descomps"]["PAR01"]
        assert len(comps) == 1
        assert comps[0]["code"] == "REC01"
        assert comps[0]["factor"] == "1"
        assert comps[0]["rendimiento"] == "1.0000"

    def test_relacion_capitulo(self):
        bc3 = _bc3()
        assert "CAP01" in bc3["rel_caps"]
        raw = bc3["rel_caps"]["CAP01"]
        assert "PAR01" in raw


# ─────────────────────────────────────────────────────────────────────────────
# 3. cmd_info — no lanza excepción
# ─────────────────────────────────────────────────────────────────────────────

class TestCmdInfo:

    def test_no_lanza(self, capsys):
        bc3_tools.cmd_info(str(FIXTURE))

    def test_muestra_archivo(self, capsys):
        bc3_tools.cmd_info(str(FIXTURE))
        out = capsys.readouterr().out
        assert "ARCHIVO" in out

    def test_muestra_conceptos(self, capsys):
        bc3_tools.cmd_info(str(FIXTURE))
        out = capsys.readouterr().out
        assert "Conceptos totales" in out


# ─────────────────────────────────────────────────────────────────────────────
# 4. cmd_validate — no lanza excepción, fixture limpio
# ─────────────────────────────────────────────────────────────────────────────

class TestCmdValidate:

    def test_no_lanza(self, capsys):
        bc3_tools.cmd_validate(str(FIXTURE))

    def test_sin_errores_criticos(self, capsys):
        """El fixture minimal.bc3 debe pasar validate sin errores."""
        bc3_tools.cmd_validate(str(FIXTURE))
        out = capsys.readouterr().out
        assert "Sin errores" in out, (
            f"Se esperaba 'Sin errores' en la salida de validate. Salida:\n{out}"
        )


# ─────────────────────────────────────────────────────────────────────────────
# 5. cmd_export — no lanza ValueError (bug de referencia)
# ─────────────────────────────────────────────────────────────────────────────

class TestCmdExport:

    def test_no_lanza_value_error(self, tmp_path):
        """Regresión directa: antes lanzaba ValueError al desempaquetar 3→2."""
        output_base = str(tmp_path / "out")
        bc3_tools.cmd_export(str(FIXTURE), output_base)

    def test_crea_csv_conceptos(self, tmp_path):
        output_base = str(tmp_path / "out")
        bc3_tools.cmd_export(str(FIXTURE), output_base)
        assert (tmp_path / "out_export.csv").exists()

    def test_crea_csv_descomposiciones(self, tmp_path):
        output_base = str(tmp_path / "out")
        bc3_tools.cmd_export(str(FIXTURE), output_base)
        assert (tmp_path / "out_descomps.csv").exists()

    def test_csv_tiene_cabecera_correcta(self, tmp_path):
        output_base = str(tmp_path / "out")
        bc3_tools.cmd_export(str(FIXTURE), output_base)
        content = (tmp_path / "out_export.csv").read_text(encoding="utf-8-sig")
        primera_linea = content.splitlines()[0]
        assert "CODIGO" in primera_linea
        assert "PRECIO" in primera_linea

    def test_csv_contiene_partida(self, tmp_path):
        output_base = str(tmp_path / "out")
        bc3_tools.cmd_export(str(FIXTURE), output_base)
        content = (tmp_path / "out_export.csv").read_text(encoding="utf-8-sig")
        assert "PAR01" in content


# ─────────────────────────────────────────────────────────────────────────────
# 6. cmd_recalc — no modifica cuando precios ya están alineados
# ─────────────────────────────────────────────────────────────────────────────

class TestCmdRecalc:

    def test_no_lanza(self, tmp_path, capsys):
        src = tmp_path / "minimal.bc3"
        shutil.copy(str(FIXTURE), str(src))
        bc3_tools.cmd_recalc(str(src))

    def test_no_genera_output_cuando_precios_cuadran(self, tmp_path, capsys):
        """
        El fixture tiene PAR01 con precio declarado == calculado (15.0).
        cmd_recalc debe detectar que no hay desajuste y retornar sin escribir archivo.
        """
        src = tmp_path / "minimal.bc3"
        shutil.copy(str(FIXTURE), str(src))
        out_path = tmp_path / "recalc_out.bc3"

        bc3_tools.cmd_recalc(str(src), output_path=str(out_path), tolerance=0.02)
        out = capsys.readouterr().out

        assert "ya cuadraban" in out, (
            f"Se esperaba el mensaje 'ya cuadraban' en stdout. Salida:\n{out}"
        )
        assert not out_path.exists(), (
            "cmd_recalc no debería haber escrito archivo de salida cuando precios cuadran"
        )

    def test_actualizados_cero(self, tmp_path, capsys):
        """Actualizados debe ser 0 con el fixture alineado."""
        src = tmp_path / "minimal.bc3"
        shutil.copy(str(FIXTURE), str(src))
        bc3_tools.cmd_recalc(str(src), tolerance=0.02)
        out = capsys.readouterr().out
        # La línea "Actualizados          : 0" debe estar presente
        assert "Actualizados" in out and ": 0" in out, (
            f"Se esperaba 'Actualizados : 0'. Salida:\n{out}"
        )

    def test_desajuste_real_genera_output(self, tmp_path, capsys):
        """Si el precio declarado no coincide, sí debe generar archivo y actualizarlo."""
        bc3 = _bc3()
        # Forzar desajuste: PAR01 precio=99.9999 (calculado=15.0)
        bc3["conceptos"]["PAR01"]["precio"] = "99.9999"
        src = tmp_path / "desajustado.bc3"
        bc3_tools.write_bc3(bc3, str(src))

        out_path = tmp_path / "recalc_desajustado.bc3"
        bc3_tools.cmd_recalc(str(src), output_path=str(out_path), tolerance=0.02)

        assert out_path.exists(), "Debe generar archivo cuando hay desajuste"
        bc3_v = bc3_tools.parse_bc3(str(out_path))
        precio_recalc = float(bc3_v["conceptos"]["PAR01"]["precio"])
        assert abs(precio_recalc - 15.0) < 0.001, (
            f"Precio recalculado debe ser ≈15.0, obtenido {precio_recalc}"
        )
