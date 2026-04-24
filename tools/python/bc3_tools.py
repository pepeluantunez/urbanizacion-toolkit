#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bc3_tools.py — Herramientas FIEBDC-3 para obra civil
======================================================
Operaciones deterministas sobre archivos .bc3.

REGLA FUNDAMENTAL:
  Las mediciones (~M) son intocables por defecto.
  Ninguna operación modifica ~M a menos que se use --allow-mediciones.
  Toda operación de escritura hace backup automático del original.

Comandos:
  info            archivo.bc3
  show            archivo.bc3  CODIGO
  compare         archivo_a.bc3  archivo_b.bc3
  export          archivo.bc3  [--output=salida.csv]
  modify          archivo.bc3  CODIGO  campo=valor  [--output=salida.bc3]
  modify-descomp  archivo.bc3  CODIGO  OPERACION  [args]
  merge           base.bc3  adicional.bc3  salida.bc3  [opciones]
  recalc          archivo.bc3  [--output=salida.bc3]  [--tolerance=0.02]
  validate        archivo.bc3

Campos modificables en 'modify':
  unidad, resumen, precio, tipo

Comando modify-descomp — modificar descomposición ~D de una partida:
  set-rendimiento CODIGO comp_code=nuevo_rendimiento [comp_code=...]
  set-factor      CODIGO comp_code=nuevo_factor [comp_code=...]
  add             CODIGO comp_code factor rendimiento
  remove          CODIGO comp_code
  Tras modificar ~D, recalcula automáticamente el precio ~C para que Presto no dé diferencias.

Comando compare — diferencias entre dos versiones de un bc3:
  Muestra: conceptos añadidos, eliminados, con precio cambiado, con descomposición cambiada.
  Las ~M se reportan separadas (cambios en medición son críticos).

Comando export — vuelca el bc3 a CSV para revisión en Excel:
  Genera: [archivo]_export.csv con CODIGO, TIPO, UNIDAD, RESUMEN, PRECIO, COMPONENTES.
  Genera: [archivo]_descomps.csv con el detalle de cada ~D.

Opciones de merge:
  --on-conflict=keep-base   (defecto) mantiene datos de la base en conflictos
  --on-conflict=keep-new    sobreescribe con el adicional en conflictos
  --allow-mediciones        permite copiar ~M del adicional

Comando recalc:
  Ajusta precio ~C para que coincida con sum(precio_comp * factor * rendimiento) de ~D.
  Resuelve "Presto da valor distinto con/sin recalcular".
  --tolerance=0.02  solo actualiza diferencias > tolerance

Comando extract — extraer partidas específicas con sus dependencias:
  extract  src.bc3  CODIGO1 CODIGO2 ...  [--output=salida.bc3]
  Extrae las partidas indicadas y todos los recursos de los que dependen
  (mano de obra, materiales, maquinaria). Ideal para tomar partidas de
  un bc3 de compañero sin importar todo el archivo.

Comando rename — renombrar un código en todo el bc3:
  rename  archivo.bc3  CODIGO_VIEJO  CODIGO_NUEVO  [--output=salida.bc3]
  Actualiza: ~C (clave), ~T, ~D (referencias como componente), ~B.
  No toca el contenido de ~M. Recalcula precios afectados automáticamente.

Ejemplos:
  python3 bc3_tools.py info presupuesto.bc3
  python3 bc3_tools.py show presupuesto.bc3 E01.01
  python3 bc3_tools.py extract compañero.bc3 E02.03 E02.07 --output=partidas.bc3
  python3 bc3_tools.py rename presupuesto.bc3 MOOF1ALB MOOF1A
  python3 bc3_tools.py modify presupuesto.bc3 E01.01 precio=125.50
  python3 bc3_tools.py merge base.bc3 extra.bc3 fusionado.bc3
  python3 bc3_tools.py recalc presupuesto.bc3
  python3 bc3_tools.py validate fusionado.bc3
"""

import sys
import os
from collections import OrderedDict
from copy import deepcopy

ENCODING_CANDIDATES = ['latin-1', 'cp1252', 'iso-8859-1', 'utf-8']

for stream_name in ('stdout', 'stderr'):
    stream = getattr(sys, stream_name, None)
    if hasattr(stream, 'reconfigure'):
        try:
            stream.reconfigure(encoding='utf-8', errors='replace')
        except Exception:
            pass


# ─────────────────────────────────────────────────────────────────────────────
# LECTURA
# ─────────────────────────────────────────────────────────────────────────────

def _read_bc3_lines(path):
    for enc in ENCODING_CANDIDATES:
        try:
            with open(path, 'r', encoding=enc) as f:
                lines = f.readlines()
            return lines, enc
        except (UnicodeDecodeError, LookupError):
            continue
    raise ValueError(f"No se pudo leer '{path}' con ningún encoding estándar.")


def _split_fields(line):
    body = line.strip()
    if body.startswith('~') and len(body) >= 3:
        body = body[3:]
    if body.endswith('|'):
        body = body[:-1]
    return body.split('|')


def parse_bc3(path):
    """
    Parsea el bc3 completo.
    Preserva TODOS los registros: ~V ~C ~T ~D ~M ~B ~K y desconocidos.
    Las ~M se almacenan exactamente como vienen — nunca se modifican salvo orden explícita.
    """
    lines, enc = _read_bc3_lines(path)

    bc3 = {
        'version': {},
        'conceptos': OrderedDict(),
        'textos': {},
        'descomps': {},
        'mediciones': {},   # ~M: solo lectura por defecto
        'rel_caps': {},     # ~B
        'extras': [],       # ~K y registros no clasificados
        'orden': [],
        'encoding': enc,
    }

    for line in lines:
        s = line.rstrip('\r\n')
        if not s.startswith('~') or len(s) < 2:
            continue

        tipo = s[1].upper()

        if tipo == 'V':
            f = _split_fields(s)
            bc3['version'] = {
                'tipo_bd': f[0] if len(f) > 0 else '',
                'version': f[1] if len(f) > 1 else '',
                'programa': f[2] if len(f) > 2 else '',
                'fichero': f[3] if len(f) > 3 else '',
                'encoding': f[4] if len(f) > 4 else 'ANSI',  # ANSI=CP1252, necesario para Presto
            }
            bc3['orden'].append(('V', ''))

        elif tipo == 'C':
            f = _split_fields(s)
            if not f or not f[0]:
                continue
            code = f[0]
            bc3['conceptos'][code] = {
                'code': code,
                'unidad':  f[1] if len(f) > 1 else '',
                'resumen': f[2] if len(f) > 2 else '',
                'precio':  f[3] if len(f) > 3 else '',
                '_f4':     f[4] if len(f) > 4 else '',
                'tipo':    f[5] if len(f) > 5 else '0',
            }
            bc3['orden'].append(('C', code))

        elif tipo == 'T':
            f = _split_fields(s)
            if not f or not f[0]:
                continue
            code = f[0]
            bc3['textos'][code] = f[1] if len(f) > 1 else ''
            bc3['orden'].append(('T', code))

        elif tipo == 'D':
            f = _split_fields(s)
            if not f or not f[0]:
                continue
            code = f[0]
            raw = f[1] if len(f) > 1 else ''
            bc3['descomps'][code] = _parse_descomp(raw)
            bc3['orden'].append(('D', code))

        elif tipo == 'M':
            f = _split_fields(s)
            if not f or not f[0]:
                continue
            code = f[0]
            # Preservar el contenido exacto — nunca reformatear
            bc3['mediciones'][code] = f[1] if len(f) > 1 else ''
            bc3['orden'].append(('M', code))

        elif tipo == 'B':
            f = _split_fields(s)
            if not f or not f[0]:
                continue
            code = f[0]
            bc3['rel_caps'][code] = f[1] if len(f) > 1 else ''
            bc3['orden'].append(('B', code))

        elif tipo == 'K':
            bc3['extras'].append(s)
            bc3['orden'].append(('K', ''))

        else:
            bc3['extras'].append(s)
            bc3['orden'].append(('?', ''))

    return bc3


def _parse_descomp(raw):
    if not raw:
        return []
    parts = raw.split('\\')
    components = []
    i = 0
    while i + 2 < len(parts):
        code = parts[i].strip()
        if code:
            components.append({
                'code': code,
                'factor': parts[i+1].strip(),
                'rendimiento': parts[i+2].strip(),
            })
        i += 3
    return components


def _format_descomp(components):
    if not components:
        return ''
    return '\\'.join(
        f"{c['code']}\\{c['factor']}\\{c['rendimiento']}"
        for c in components
    ) + '\\'


# ─────────────────────────────────────────────────────────────────────────────
# ESCRITURA
# ─────────────────────────────────────────────────────────────────────────────

def write_bc3(bc3, output_path, encoding='latin-1'):
    """
    Escribe el bc3 preservando el orden original.
    Las ~M se escriben exactamente como se leyeron.
    """
    out = []
    seen_C = set(); seen_T = set(); seen_D = set()
    seen_M = set(); seen_B = set()
    extras_idx = 0

    for tipo, code in bc3['orden']:
        if tipo == 'V':
            v = bc3['version']
            enc = v.get('encoding', 'ANSI')  # Siempre declarar ANSI para Presto/CP1252
            out.append(
                f"~V|{v.get('tipo_bd','')}|{v.get('version','')}|"
                f"{v.get('programa','')}|{v.get('fichero','')}|{enc}|\n"
            )
        elif tipo == 'C' and code in bc3['conceptos'] and code not in seen_C:
            c = bc3['conceptos'][code]
            out.append(
                f"~C|{c['code']}|{c['unidad']}|{c['resumen']}|"
                f"{c['precio']}|{c.get('_f4','')}|{c['tipo']}|\n"
            )
            seen_C.add(code)
        elif tipo == 'T' and code in bc3['textos'] and code not in seen_T:
            out.append(f"~T|{code}|{bc3['textos'][code]}|\n")
            seen_T.add(code)
        elif tipo == 'D' and code in bc3['descomps'] and code not in seen_D:
            out.append(f"~D|{code}|{_format_descomp(bc3['descomps'][code])}|\n")
            seen_D.add(code)
        elif tipo == 'M' and code in bc3['mediciones'] and code not in seen_M:
            # ~M se escribe exactamente como se leyó
            out.append(f"~M|{code}|{bc3['mediciones'][code]}|\n")
            seen_M.add(code)
        elif tipo == 'B' and code in bc3['rel_caps'] and code not in seen_B:
            out.append(f"~B|{code}|{bc3['rel_caps'][code]}|\n")
            seen_B.add(code)
        elif tipo in ('K', '?'):
            if extras_idx < len(bc3['extras']):
                out.append(bc3['extras'][extras_idx] + '\n')
                extras_idx += 1

    # CRLF obligatorio: Presto en Windows rechaza archivos con LF solo
    with open(output_path, 'w', encoding=encoding, errors='replace', newline='\r\n') as f:
        f.writelines(out)
    return len(out)


# ─────────────────────────────────────────────────────────────────────────────
# PRECIO CALCULADO
# ─────────────────────────────────────────────────────────────────────────────

def _precio_calculado(bc3, code):
    """
    Suma precio_componente * factor * rendimiento para todos los ~D de 'code'.
    Devuelve (total_calculado, ok_bool, missing_codes).
    - ok_bool=False solo si no hay ~D para 'code'.
    - missing_codes: lista de componentes referenciados en ~D que no tienen ~C
      en este bc3. Si no está vacía, el total calculado es incorrecto.
    """
    if code not in bc3['descomps']:
        return None, False, []
    total = 0.0
    missing = []
    for comp in bc3['descomps'][code]:
        comp_data = bc3['conceptos'].get(comp['code'])
        if comp_data is None:
            if comp['code']:
                missing.append(comp['code'])
            continue
        try:
            cp = float(comp_data['precio'] or '0')
            f  = float(comp['factor'] or '1')
            r  = float(comp['rendimiento'] or '0')
            total += cp * f * r
        except (ValueError, TypeError):
            pass
    return total, True, missing


def _collect_deps(bc3, code, visited=None):
    """
    Recorre recursivamente todas las dependencias de una partida
    (recursos referenciados en ~D, y los ~D de esos recursos, etc.).
    Devuelve el set de todos los códigos necesarios (incluido 'code').
    """
    if visited is None:
        visited = set()
    if code in visited:
        return visited
    visited.add(code)
    for comp in bc3.get('descomps', {}).get(code, []):
        if comp['code']:
            _collect_deps(bc3, comp['code'], visited)
    return visited


# ─────────────────────────────────────────────────────────────────────────────
# COMANDOS
# ─────────────────────────────────────────────────────────────────────────────

def cmd_info(path):
    print(f"\n{'='*60}")
    print(f"ARCHIVO: {path}")
    bc3 = parse_bc3(path)
    print(f"Encoding  : {bc3['encoding']}")
    print(f"Versión   : {bc3['version'].get('version', '?')}")
    print(f"Programa  : {bc3['version'].get('programa', '?')}")
    print()

    c = bc3['conceptos']
    caps     = {k: v for k, v in c.items() if v['tipo'] in ('EA', 'EU')}
    partidas = {k: v for k, v in c.items() if v['tipo'] not in ('EA', 'EU')}

    print(f"Conceptos totales : {len(c)}")
    print(f"Capítulos (EA/EU) : {len(caps)}")
    print(f"Partidas/recursos : {len(partidas)}")
    print(f"Con descomposición: {len(bc3['descomps'])}")
    print(f"Con texto largo   : {len(bc3['textos'])}")
    print(f"Con medición (~M) : {len(bc3['mediciones'])}")
    print(f"Con relación (~B) : {len(bc3['rel_caps'])}")
    print()

    if caps:
        print(f"CAPÍTULOS:")
        print(f"  {'CÓDIGO':<22} {'TIPO':<5} RESUMEN")
        print(f"  {'-'*70}")
        for code, cv in caps.items():
            print(f"  {code:<22} {cv['tipo']:<5} {cv['resumen'][:50]}")

    # Aviso: partidas tipo 0 sin ~D (potencial pérdida de datos)
    sin_descomp = [k for k, v in partidas.items()
                   if v['tipo'] == '0' and k not in bc3['descomps']]
    if sin_descomp:
        print(f"\n⚠  Partidas tipo 0 sin descomposición ~D: {len(sin_descomp)}")
        for code in sin_descomp[:8]:
            print(f"   {code}: {c[code]['resumen'][:55]}")
        if len(sin_descomp) > 8:
            print(f"   ... y {len(sin_descomp)-8} más")

    # Aviso: precios que no cuadran con ~D (problema Presto recalcular)
    desajustes = []
    comp_faltantes = []
    for code in bc3['descomps']:
        cv = bc3['conceptos'].get(code)
        if not cv or not cv['precio']:
            continue
        total, ok, missing = _precio_calculado(bc3, code)
        if missing:
            comp_faltantes.append((code, missing))
        if ok and total > 0:
            try:
                diff = abs(float(cv['precio']) - total)
                if diff > 0.02:
                    desajustes.append((code, float(cv['precio']), total, diff))
            except (ValueError, TypeError):
                pass
    if comp_faltantes:
        print(f"\n⚠  Partidas con componentes ~D sin ~C (precio calculado incompleto):")
        for code, missing in comp_faltantes[:10]:
            print(f"   {code}: faltan {missing}")
        if len(comp_faltantes) > 10:
            print(f"   ... y {len(comp_faltantes)-10} más")
        print(f"   → Si viene de un merge, ejecutar de nuevo con dependencias completas")
    if desajustes:
        print(f"\n⚠  Precios ~C que NO cuadran con ~D (causa del problema Presto recalcular):")
        print(f"   {'CÓDIGO':<22} {'DECLARADO':>12} {'CALCULADO':>12} {'DIFF':>8}")
        for code, decl, calc, diff in desajustes[:10]:
            print(f"   {code:<22} {decl:>12.4f} {calc:>12.4f} {diff:>8.4f}")
        if len(desajustes) > 10:
            print(f"   ... y {len(desajustes)-10} más")
        print(f"\n   → Ejecutar: python3 bc3_tools.py recalc {path}")


def cmd_show(path, code):
    bc3 = parse_bc3(path)
    if code not in bc3['conceptos']:
        print(f"ERROR: '{code}' no existe en {path}")
        sys.exit(1)

    c = bc3['conceptos'][code]
    print(f"\n{'='*65}")
    print(f"PARTIDA: {code}")
    print(f"{'='*65}")
    print(f"Resumen : {c['resumen']}")
    print(f"Unidad  : {c['unidad']}")
    print(f"Tipo    : {c['tipo']}")

    try:
        pf = float(c['precio']) if c['precio'] else 0.0
        print(f"Precio  : {pf:,.4f} €  (en bc3: {c['precio']})")
    except ValueError:
        print(f"Precio  : {c['precio']}")

    if code in bc3['textos']:
        txt = bc3['textos'][code]
        print(f"\nDESCRIPCIÓN (~T):")
        print(f"  {txt[:600]}")
        if len(txt) > 600:
            print("  [... truncado ...]")

    if code in bc3['descomps']:
        comps = bc3['descomps'][code]
        print(f"\nDESCOMPOSICIÓN ~D ({len(comps)} componentes):")
        print(f"  {'CÓDIGO':<22} {'FACTOR':>7} {'REND':>10}  RESUMEN")
        print(f"  {'-'*70}")
        total_calc = 0.0
        for comp in comps:
            cd = bc3['conceptos'].get(comp['code'], {})
            res = cd.get('resumen', '¡NO EN BC3!')[:28]
            try:
                cp = float(cd.get('precio', '0') or '0')
                f  = float(comp['factor'] or '1')
                r  = float(comp['rendimiento'] or '0')
                total_calc += cp * f * r
            except (ValueError, TypeError):
                pass
            print(f"  {comp['code']:<22} {comp['factor']:>7} {comp['rendimiento']:>10}  {res}")

        try:
            pd = float(c['precio']) if c['precio'] else 0.0
            diff = abs(pd - total_calc)
            print(f"\n  Precio declarado (~C): {pd:.4f} €")
            print(f"  Total calculado (~D) : {total_calc:.4f} €")
            if diff <= 0.02:
                print(f"  ✓ Cuadran (diferencia {diff:.4f} € ≤ 0.02)")
            else:
                print(f"  ✗ DESAJUSTE: {diff:.4f} € — Presto dará valores distintos con/sin recalcular")
                print(f"  → Ejecutar: python3 bc3_tools.py recalc {path}")
        except (ValueError, TypeError):
            pass

    if code in bc3['mediciones']:
        print(f"\nMEDICIÓN ~M (read-only — no se modifica nunca por código):")
        print(f"  {bc3['mediciones'][code][:400]}")

    print()


def cmd_modify(path, code, changes_raw, output_path=None):
    """
    Modifica SOLO campos de ~C: unidad, resumen, precio, tipo.
    ~T, ~D, ~M nunca se tocan. Si necesitas cambiar descomposición o medición,
    edita el bc3 directamente en un editor de texto.
    """
    bc3 = parse_bc3(path)

    if code not in bc3['conceptos']:
        print(f"ERROR: '{code}' no existe en {path}")
        sys.exit(1)

    changes = {}
    for ch in changes_raw:
        if '=' not in ch:
            print(f"ERROR: formato incorrecto '{ch}'. Usar campo=valor")
            sys.exit(1)
        k, v = ch.split('=', 1)
        changes[k.strip()] = v.strip()

    permitidos = {'unidad', 'resumen', 'precio', 'tipo'}
    for k in changes:
        if k not in permitidos:
            print(f"ERROR: '{k}' no es modificable. Solo: {permitidos}")
            print("Para cambiar ~T, ~D o ~M: editar el bc3 manualmente.")
            sys.exit(1)

    c = bc3['conceptos'][code]
    print(f"\nModificando {code}:")
    for k, v in changes.items():
        print(f"  {k}: '{c[k]}' → '{v}'")
        c[k] = v

    if output_path is None:
        base, ext = os.path.splitext(path)
        output_path = f"{base}_mod{ext}"

    _backup(path)
    n = write_bc3(bc3, output_path, encoding=bc3['encoding'])
    print(f"Guardado: {output_path} ({n} líneas)")

    # Verificar round-trip
    bc3_v = parse_bc3(output_path)
    cv = bc3_v['conceptos'].get(code, {})
    ok = all(cv.get(k) == v for k, v in changes.items())
    m_orig = bc3['mediciones'].get(code)
    m_out  = bc3_v['mediciones'].get(code)
    m_ok = (m_orig == m_out)

    print(f"✓ Cambios verificados: {'SÍ' if ok else 'NO'}")
    print(f"✓ ~M preservada intacta: {'SÍ' if m_ok else '⚠ REVISAR'}")

    _log_change(output_path, 'modify', f"Código: {code}\n" + '\n'.join(f"{k}={v}" for k, v in changes.items()))
    _run_propagacion(output_path)


def cmd_recalc(path, output_path=None, tolerance=0.02, max_iter=10):
    """
    Recalcula los precios ~C a partir de las descomposiciones ~D.

    Resuelve el problema: "si doy a recalcular en Presto me sale un valor distinto".
    Eso pasa porque el precio declarado en ~C no coincide con
    sum(precio_componente × factor × rendimiento).

    Este comando los iguala: actualiza el ~C con el valor calculado.
    Itera internamente hasta que no queden desajustes (hasta max_iter pasadas).
    Solo actualiza partidas cuya diferencia supere 'tolerance' (defecto 0.02 €).

    IMPORTANTE: Este comando NO toca ~M, ~T, ~D. Solo ajusta el campo precio en ~C.
    """
    print(f"\nRecalculando precios: {path}")
    print(f"Tolerancia: {tolerance} €")

    bc3 = parse_bc3(path)
    actualizados_total = []
    sin_descomp = []

    for iteracion in range(1, max_iter + 1):
        actualizados = []
        sin_cambio   = []

        for code, c in bc3['conceptos'].items():
            if c['tipo'] in ('EA', 'EU'):
                continue  # capítulos: precio 0, normal

            total, ok, missing = _precio_calculado(bc3, code)
            if not ok:
                if iteracion == 1:
                    sin_descomp.append(code)
                continue

            if missing:
                if iteracion == 1:
                    sin_descomp.append(f"{code} [faltan: {', '.join(missing)}]")
                continue

            if total <= 0:
                continue

            try:
                precio_decl = float(c['precio']) if c['precio'] else 0.0
            except (ValueError, TypeError):
                continue

            diff = abs(precio_decl - total)
            if diff > tolerance:
                actualizados.append((code, precio_decl, total, diff))
                bc3['conceptos'][code]['precio'] = f"{total:.4f}"
            else:
                sin_cambio.append(code)

        actualizados_total.extend(actualizados)
        if not actualizados:
            if iteracion > 1:
                print(f"  Convergencia en {iteracion} pasadas.")
            break
        if iteracion > 1:
            print(f"  Pasada {iteracion}: {len(actualizados)} partidas actualizadas")
    else:
        print(f"  ⚠ No convergió en {max_iter} pasadas — puede haber referencias circulares.")

    # Para el informe, eliminar duplicados (mostrar último estado)
    seen = {}
    for code, antes, despues, diff in actualizados_total:
        if code not in seen:
            seen[code] = (antes, despues, diff)
        else:
            seen[code] = (seen[code][0], despues, abs(seen[code][0] - despues))
    actualizados_dedup = [(c, v[0], v[1], v[2]) for c, v in seen.items()]

    actualizados = actualizados_dedup
    sin_cambio_count = len([c for c in bc3['conceptos'] if c not in seen])

    print(f"\nResultados:")
    print(f"  Sin descomposición ~D : {len(sin_descomp)}")
    print(f"  Ya cuadran (diff ≤ {tolerance}) : {sin_cambio_count}")
    print(f"  Actualizados          : {len(actualizados)}")

    if actualizados:
        print(f"\n  Partidas actualizadas:")
        print(f"  {'CÓDIGO':<22} {'ANTES':>10} {'DESPUÉS':>10} {'DIFF':>8}")
        print(f"  {'-'*55}")
        for code, antes, despues, diff in actualizados[:30]:
            print(f"  {code:<22} {antes:>10.4f} {despues:>10.4f} {diff:>8.4f}")
        if len(actualizados) > 30:
            print(f"  ... y {len(actualizados)-30} más")

    if not actualizados:
        print("\n  ✓ Todos los precios ya cuadraban. No se ha generado archivo de salida.")
        return

    if output_path is None:
        base, ext = os.path.splitext(path)
        output_path = f"{base}_recalc{ext}"

    _backup(path)
    n = write_bc3(bc3, output_path, encoding=bc3['encoding'])
    print(f"\nGuardado: {output_path} ({n} líneas)")
    print("IMPORTANTE: ~M, ~T y ~D no han sido modificadas.")

    # Verificar que ~M no cambió en ninguna partida
    bc3_v = parse_bc3(output_path)
    m_corrupted = [
        code for code in bc3['mediciones']
        if bc3['mediciones'][code] != bc3_v['mediciones'].get(code)
    ]
    if m_corrupted:
        print(f"⚠  ~M ALTERADAS (no debería ocurrir): {m_corrupted}")
    else:
        print(f"✓ Todas las ~M preservadas intactas.")

    _log_change(output_path, 'recalc', f"Partidas recalculadas: {len(recalculated)}")
    _run_propagacion(output_path)


def cmd_merge(path_base, path_add, output_path,
              on_conflict='keep-base', allow_mediciones=False):
    """
    Fusiona dos bc3.

    Por defecto (~M protegidas):
    - Los ~M de la base se preservan SIEMPRE, incluso en conflictos.
    - Para conceptos nuevos del adicional: se copia su ~M solo si allow_mediciones=True.
    - Razón: las ~M contienen el desglose de medición real del proyecto;
      mezclarlos sin revisión introduce errores silenciosos.

    Con --allow-mediciones:
    - Conceptos nuevos: se copia su ~M del adicional.
    - Conflictos keep-new: se copia ~M del adicional solo si la base no tenía ~M.
    """
    print(f"\nFusionando:")
    print(f"  Base         : {path_base}")
    print(f"  Adicional    : {path_add}")
    print(f"  En conflicto : {on_conflict}")
    print(f"  Copiar ~M    : {'SÍ (--allow-mediciones)' if allow_mediciones else 'NO (protegidas)'}")
    print()

    bc3_base = parse_bc3(path_base)
    bc3_add  = parse_bc3(path_add)

    # Detectar mismatch de encoding
    if bc3_base['encoding'] != bc3_add['encoding']:
        print(f"⚠  Encoding diferente: base={bc3_base['encoding']}, "
              f"adicional={bc3_add['encoding']}")
        print(f"   El output se escribirá en {bc3_base['encoding']}. "
              f"Caracteres especiales del adicional pueden corromperse.")
        print()

    n_base = len(bc3_base['conceptos'])
    n_add  = len(bc3_add['conceptos'])

    conflicts = set(bc3_base['conceptos'].keys()) & set(bc3_add['conceptos'].keys())
    nuevos    = set(bc3_add['conceptos'].keys()) - set(bc3_base['conceptos'].keys())

    # ── Cascade de dependencias ──────────────────────────────────────────────
    # Las partidas nuevas (~D) referencian recursos (mano de obra, materiales,
    # maquinaria). Si esos recursos no existen en la base, recalc y validate
    # fallarán. Se copian automáticamente desde el adicional si no están en base.
    all_deps = set()
    for code in nuevos:
        all_deps.update(_collect_deps(bc3_add, code))

    # Recursos necesarios que no están en base ni son las propias partidas nuevas
    recursos_a_copiar = (all_deps - set(bc3_base['conceptos'].keys())) - nuevos
    # Excluir también los que sí están en el adicional (pueden ser refs externas)
    recursos_a_copiar = recursos_a_copiar & set(bc3_add['conceptos'].keys())
    # Referencias a códigos que no existen en ninguno de los dos archivos
    refs_externas = (all_deps - set(bc3_base['conceptos'].keys())) - nuevos \
                    - set(bc3_add['conceptos'].keys())

    print(f"Conceptos en base          : {n_base}")
    print(f"Conceptos en adicional     : {n_add}")
    print(f"Conflictos (mismo cód)     : {len(conflicts)}")
    print(f"Partidas nuevas            : {len(nuevos)}")
    print(f"Recursos dependientes      : {len(recursos_a_copiar)}  "
          f"(copiados para que ~D esté completa)")
    if refs_externas:
        print(f"⚠ Referencias externas     : {len(refs_externas)}  "
              f"(no están en ninguno de los dos bc3)")
        for ref in sorted(refs_externas)[:8]:
            print(f"   {ref}")

    if conflicts and len(conflicts) <= 25:
        print(f"\nConflictos resueltos con '{on_conflict}':")
        for code in sorted(conflicts):
            b = bc3_base['conceptos'][code]['resumen'][:35]
            a = bc3_add['conceptos'][code]['resumen'][:35]
            ganador = "base" if on_conflict == 'keep-base' else "adicional"
            print(f"  {code:<20} base='{b}' | adic='{a}' → {ganador}")
    elif conflicts:
        print(f"\n  (más de 25 conflictos — ver archivo de salida)")

    bc3_merged = deepcopy(bc3_base)

    # ── Copiar recursos dependientes primero (base para que ~D funcione) ─────
    for code in sorted(recursos_a_copiar):
        bc3_merged['conceptos'][code] = deepcopy(bc3_add['conceptos'][code])
        bc3_merged['orden'].append(('C', code))
        if code in bc3_add['textos']:
            bc3_merged['textos'][code] = bc3_add['textos'][code]
            bc3_merged['orden'].append(('T', code))
        if code in bc3_add['descomps']:
            bc3_merged['descomps'][code] = deepcopy(bc3_add['descomps'][code])
            bc3_merged['orden'].append(('D', code))
        # Los recursos no tienen ~M normalmente, pero si allow_mediciones y existe, copiar
        if allow_mediciones and code in bc3_add['mediciones']:
            bc3_merged['mediciones'][code] = bc3_add['mediciones'][code]
            bc3_merged['orden'].append(('M', code))

    # ── Añadir partidas completamente nuevas ─────────────────────────────────
    for code in nuevos:
        bc3_merged['conceptos'][code] = deepcopy(bc3_add['conceptos'][code])
        bc3_merged['orden'].append(('C', code))

        if code in bc3_add['textos']:
            bc3_merged['textos'][code] = bc3_add['textos'][code]
            bc3_merged['orden'].append(('T', code))

        if code in bc3_add['descomps']:
            bc3_merged['descomps'][code] = deepcopy(bc3_add['descomps'][code])
            bc3_merged['orden'].append(('D', code))

        # ~M: solo si se permite explícitamente
        if allow_mediciones and code in bc3_add['mediciones']:
            bc3_merged['mediciones'][code] = bc3_add['mediciones'][code]
            bc3_merged['orden'].append(('M', code))

    # Resolver conflictos (keep-new)
    if on_conflict == 'keep-new':
        for code in conflicts:
            bc3_merged['conceptos'][code] = deepcopy(bc3_add['conceptos'][code])
            if code in bc3_add['textos']:
                bc3_merged['textos'][code] = bc3_add['textos'][code]
            if code in bc3_add['descomps']:
                bc3_merged['descomps'][code] = deepcopy(bc3_add['descomps'][code])
            # ~M: NUNCA sobreescribir la de la base, incluso con keep-new
            # Si la base no tenía ~M y allow_mediciones, copiar la del adicional
            if allow_mediciones and code not in bc3_base['mediciones'] \
                    and code in bc3_add['mediciones']:
                bc3_merged['mediciones'][code] = bc3_add['mediciones'][code]
                bc3_merged['orden'].append(('M', code))

    # Fusionar ~B sin duplicar entradas
    for code, raw in bc3_add['rel_caps'].items():
        if code not in bc3_merged['rel_caps']:
            bc3_merged['rel_caps'][code] = raw
            bc3_merged['orden'].append(('B', code))
        else:
            existing = bc3_merged['rel_caps'][code]
            existing_codes = set()
            parts = existing.split('\\')
            for i in range(0, len(parts) - 1, 2):
                if parts[i]:
                    existing_codes.add(parts[i])
            add_parts = raw.split('\\')
            new_entries = ''
            for i in range(0, len(add_parts) - 1, 2):
                if add_parts[i] and add_parts[i] not in existing_codes:
                    med = add_parts[i+1] if i+1 < len(add_parts) else '0'
                    new_entries += f"{add_parts[i]}\\{med}\\"
            if new_entries:
                bc3_merged['rel_caps'][code] = existing + new_entries

    _backup(path_base)
    n = write_bc3(bc3_merged, output_path, encoding=bc3_base['encoding'])
    print(f"\nGuardado: {output_path} ({n} líneas)")

    _log_change(output_path, 'merge', f"Base: {Path(path_base).name}\nAdicional: {Path(path_add).name}\nNuevos: {len(nuevos)}")
    _run_propagacion(output_path)

    # Validación
    bc3_v = parse_bc3(output_path)
    lost_base = set(bc3_base['conceptos'].keys()) - set(bc3_v['conceptos'].keys())
    lost_new  = nuevos - set(bc3_v['conceptos'].keys())

    # Verificar que ~M de la base no se han tocado
    m_corrupted = [
        code for code in bc3_base['mediciones']
        if bc3_base['mediciones'][code] != bc3_v['mediciones'].get(code)
    ]

    lost_recursos = recursos_a_copiar - set(bc3_v['conceptos'].keys())

    print(f"\nValidación post-merge:")
    print(f"  Conceptos en salida: {len(bc3_v['conceptos'])}")
    if lost_base:
        print(f"  ✗ PERDIDOS DE LA BASE: {lost_base}")
    else:
        print(f"  ✓ Todos los conceptos de la base presentes")
    if lost_new:
        print(f"  ✗ NUEVOS PERDIDOS: {lost_new}")
    else:
        print(f"  ✓ Todas las partidas nuevas presentes ({len(nuevos)})")
    if lost_recursos:
        print(f"  ✗ RECURSOS DEPENDIENTES PERDIDOS: {lost_recursos}")
    else:
        print(f"  ✓ Todos los recursos dependientes presentes ({len(recursos_a_copiar)})")
    if m_corrupted:
        print(f"  ✗ ~M ALTERADAS (ERROR): {m_corrupted[:10]}")
    else:
        print(f"  ✓ Todas las ~M de la base preservadas intactas")
    if refs_externas:
        print(f"  ⚠ Referencias externas no resueltas: {sorted(refs_externas)[:5]}")
        print(f"    Ejecutar validate para ver impacto en precios")


def cmd_validate(path):
    print(f"\nValidando: {path}")
    bc3 = parse_bc3(path)
    errores = []
    avisos  = []

    conceptos = bc3['conceptos']

    for code, c in conceptos.items():
        if not c['resumen']:
            avisos.append(f"  {code}: resumen vacío")

        total, ok, missing = _precio_calculado(bc3, code)
        if missing:
            for m in missing:
                errores.append(
                    f"  COMPONENTE SIN ~C: '{m}' en ~D de {code} "
                    f"— precio calculado incorrecto, Presto fallará al recalcular"
                )
        if ok and total is not None and total > 0:
            try:
                pd = float(c['precio']) if c['precio'] else 0.0
                diff = abs(pd - total)
                if diff > 0.10:
                    errores.append(
                        f"  PRECIO DESAJUSTADO {code}: "
                        f"declarado={pd:.4f} calculado={total:.4f} diff={diff:.4f}"
                    )
                elif diff > 0.02:
                    avisos.append(
                        f"  Precio leve desajuste {code}: diff={diff:.4f} "
                        f"(puede causar diferencia en Presto al recalcular)"
                    )
            except (ValueError, TypeError):
                pass

        # Nota: los componentes sin ~C ya se reportan como ERROR arriba (via _precio_calculado).
        # No se duplica como aviso.

    for cap_code, raw in bc3['rel_caps'].items():
        parts = raw.split('\\')
        for i in range(0, len(parts) - 1, 2):
            ref = parts[i].strip()
            if ref and ref not in conceptos:
                avisos.append(
                    f"  ~B de {cap_code} referencia '{ref}' sin ~C"
                )

    print(f"\nResumen:")
    print(f"  Conceptos       : {len(conceptos)}")
    print(f"  Descomposiciones: {len(bc3['descomps'])}")
    print(f"  Textos largos   : {len(bc3['textos'])}")
    print(f"  Mediciones ~M   : {len(bc3['mediciones'])}")

    if errores:
        print(f"\n  ERRORES ({len(errores)}):")
        for e in errores[:20]:
            print(e)
    else:
        print(f"\n  ✓ Sin errores críticos")

    if avisos:
        print(f"\n  AVISOS ({len(avisos)}):")
        for a in avisos[:20]:
            print(a)
        if len(avisos) > 20:
            print(f"  ... y {len(avisos)-20} más")
    else:
        print(f"  ✓ Sin avisos")

    if not errores and not avisos:
        print(f"\n  ✓ Archivo íntegro")


# ─────────────────────────────────────────────────────────────────────────────
# BACKUP
# ─────────────────────────────────────────────────────────────────────────────

def _backup(path):
    """
    Crea copia de seguridad en <archivo>.bak antes de cualquier escritura.
    Si ya existe .bak, la sobreescribe (solo se guarda la última copia limpia).
    """
    bak = path + '.bak'
    try:
        import shutil
        shutil.copy2(path, bak)
        print(f"Backup: {bak}")
    except Exception as e:
        print(f"⚠ No se pudo crear backup: {e}")


def _log_change(bc3_path, cmd, details=''):
    """
    Registra cada escritura en BC3_CHANGELOG.md junto al bc3.
    Esto permite recuperar el historial de cambios sin depender de memoria de sesión.
    """
    from datetime import datetime
    bc3_path = Path(bc3_path).resolve()
    log_path = bc3_path.parent / 'BC3_CHANGELOG.md'
    ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    bak = str(bc3_path) + '.bak'
    entry = (
        f"\n## {ts} — `{cmd}` → `{bc3_path.name}`\n"
        f"- Backup: `{Path(bak).name}`\n"
    )
    if details:
        for line in details.strip().split('\n'):
            entry += f"- {line}\n"
    try:
        header = ''
        if not log_path.exists():
            header = (
                f"# BC3 CHANGELOG — {bc3_path.name}\n\n"
                f"Registro automático de todas las modificaciones al bc3.\n"
                f"Generado por bc3_tools.py. No editar manualmente.\n"
            )
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(header + entry)
    except Exception:
        pass  # No interrumpir el flujo principal


def _run_propagacion(bc3_path):
    """
    Ejecuta propagacion_cambios.py si existe en el proyecto del bc3.
    Se llama automáticamente tras cualquier escritura de bc3.
    Busca tools/propagacion_cambios.py en el directorio padre del bc3.
    """
    import subprocess
    bc3_path = Path(bc3_path).resolve()
    # Buscar en: parent/tools/ y parent.parent/tools/
    for candidate_root in [bc3_path.parent.parent, bc3_path.parent]:
        prop_script = candidate_root / 'tools' / 'propagacion_cambios.py'
        if prop_script.exists():
            try:
                result = subprocess.run(
                    [sys.executable, str(prop_script), '--bc3', str(bc3_path)],
                    capture_output=True, text=True, timeout=30
                )
                output = result.stdout.strip()
                if output:
                    print(f"\n[Propagación] {output}")
                if result.returncode != 0 and result.stderr.strip():
                    # Solo mostrar error si no es "no hay snapshot"
                    err = result.stderr.strip()
                    if 'No hay snapshot' not in err and 'Snapshot creado' not in err:
                        print(f"[Propagación] ⚠ {err}")
            except Exception:
                pass  # No interrumpir el flujo principal
            break


# ─────────────────────────────────────────────────────────────────────────────
# COMPARE
# ─────────────────────────────────────────────────────────────────────────────

def cmd_extract(path_src, codes_to_extract, output_path=None):
    """
    Extrae partidas específicas con toda su cadena de dependencias.
    Genera un bc3 mínimo que contiene exactamente las partidas pedidas
    y los recursos (~C) que necesitan para que ~D esté completa.
    Las ~M de las partidas pedidas se preservan; las de los recursos, no
    (los recursos no tienen ~M normalmente).
    """
    bc3_src = parse_bc3(path_src)

    # Validar existencia
    missing_codes = [c for c in codes_to_extract if c not in bc3_src['conceptos']]
    if missing_codes:
        print(f"ERROR: códigos no encontrados en {path_src}: {missing_codes}")
        avail = list(bc3_src['conceptos'].keys())[:15]
        print(f"  Primeros códigos disponibles: {avail}")
        sys.exit(1)

    # Recoger todas las dependencias (cascade recursivo)
    all_needed = set()
    for code in codes_to_extract:
        all_needed.update(_collect_deps(bc3_src, code))

    n_deps = len(all_needed - set(codes_to_extract))

    # Referencias externas (en ~D pero sin ~C en este bc3)
    refs_ext = all_needed - set(bc3_src['conceptos'].keys())

    print(f"\nExtrayendo de: {path_src}")
    print(f"  Partidas pedidas      : {len(codes_to_extract)}  "
          f"({', '.join(codes_to_extract[:5])}{'...' if len(codes_to_extract)>5 else ''})")
    print(f"  Recursos dependientes : {n_deps}")
    print(f"  Total a incluir       : {len(all_needed - refs_ext)}")
    if refs_ext:
        print(f"  ⚠ Referencias externas: {sorted(refs_ext)}")
        print(f"    (no tienen ~C en este bc3 — el validate del destino las reportará)")

    # Construir bc3 de salida preservando el orden del original
    bc3_out = {
        'version': bc3_src['version'].copy(),
        'conceptos': OrderedDict(),
        'textos': {},
        'descomps': {},
        'mediciones': {},
        'rel_caps': {},
        'extras': [],
        'orden': [('V', '')],
        'encoding': bc3_src['encoding'],
    }

    for code, c in bc3_src['conceptos'].items():
        if code not in all_needed:
            continue
        bc3_out['conceptos'][code] = deepcopy(c)
        bc3_out['orden'].append(('C', code))
        if code in bc3_src['textos']:
            bc3_out['textos'][code] = bc3_src['textos'][code]
            bc3_out['orden'].append(('T', code))
        if code in bc3_src['descomps']:
            bc3_out['descomps'][code] = deepcopy(bc3_src['descomps'][code])
            bc3_out['orden'].append(('D', code))
        # ~M: solo para partidas pedidas explícitamente, no sus recursos
        if code in codes_to_extract and code in bc3_src['mediciones']:
            bc3_out['mediciones'][code] = bc3_src['mediciones'][code]
            bc3_out['orden'].append(('M', code))

    # ~B: copiar entradas que referencian las partidas pedidas
    for cap_code, raw in bc3_src['rel_caps'].items():
        parts = raw.split('\\')
        new_entries = ''
        for i in range(0, len(parts) - 1, 2):
            if parts[i] in set(codes_to_extract):
                med = parts[i+1] if i+1 < len(parts) else '0'
                new_entries += f"{parts[i]}\\{med}\\"
        if new_entries:
            if cap_code in bc3_src['conceptos'] and cap_code not in bc3_out['conceptos']:
                bc3_out['conceptos'][cap_code] = deepcopy(bc3_src['conceptos'][cap_code])
                bc3_out['orden'].append(('C', cap_code))
            bc3_out['rel_caps'][cap_code] = new_entries
            bc3_out['orden'].append(('B', cap_code))

    if output_path is None:
        base, ext = os.path.splitext(path_src)
        sfx = '_'.join(codes_to_extract[:2])
        output_path = f"{base}_{sfx}_extract{ext}"

    n = write_bc3(bc3_out, output_path, encoding=bc3_src['encoding'])
    print(f"\nGuardado: {output_path} ({n} líneas)")

    # Verificación
    bc3_v = parse_bc3(output_path)
    lost_req  = set(codes_to_extract) - set(bc3_v['conceptos'].keys())
    present_deps = (all_needed & set(bc3_src['conceptos'].keys())) - set(bc3_v['conceptos'].keys())
    if lost_req:
        print(f"  ✗ PARTIDAS PERDIDAS: {lost_req}")
    else:
        print(f"  ✓ Todas las partidas pedidas presentes")
    if present_deps:
        print(f"  ✗ DEPENDENCIAS PERDIDAS: {present_deps}")
    else:
        print(f"  ✓ Todas las dependencias presentes")


def cmd_rename(path, old_code, new_code, output_path=None):
    """
    Renombra un código en todo el bc3.

    Actualiza:
      - ~C: la clave del concepto (y el campo 'code' interno)
      - ~T: la clave del texto largo
      - ~D: donde aparece como componente de otras partidas
      - ~B: donde aparece en relaciones de capítulo
      - Orden interno del bc3

    NO modifica el contenido de ~M (son texto libre de medición, no referencias
    estructurales). Si el contenido de una ~M menciona el código por nombre,
    hay que editarlo manualmente.

    Recalcula automáticamente los precios ~C de las partidas que tenían
    old_code como componente en su ~D.
    """
    bc3 = parse_bc3(path)

    if old_code not in bc3['conceptos']:
        print(f"ERROR: '{old_code}' no existe en {path}")
        sys.exit(1)
    if new_code in bc3['conceptos']:
        print(f"ERROR: '{new_code}' ya existe en {path} — elige un código libre")
        sys.exit(1)

    print(f"\nRenombrando '{old_code}' → '{new_code}'")

    # 1. Renombrar en conceptos (preservar orden con OrderedDict)
    new_conceptos = OrderedDict()
    for k, v in bc3['conceptos'].items():
        if k == old_code:
            v = dict(v)
            v['code'] = new_code
            new_conceptos[new_code] = v
        else:
            new_conceptos[k] = v
    bc3['conceptos'] = new_conceptos

    # 2. Textos
    if old_code in bc3['textos']:
        bc3['textos'][new_code] = bc3['textos'].pop(old_code)

    # 3. Descomps (clave)
    if old_code in bc3['descomps']:
        bc3['descomps'][new_code] = bc3['descomps'].pop(old_code)

    # 4. Descomps (referencias como componente de otras partidas)
    n_refs_D = 0
    afectadas_por_D = []
    for code, comps in bc3['descomps'].items():
        for comp in comps:
            if comp['code'] == old_code:
                comp['code'] = new_code
                n_refs_D += 1
                afectadas_por_D.append(code)

    # 5. Mediciones (solo la clave — nunca el contenido)
    if old_code in bc3['mediciones']:
        bc3['mediciones'][new_code] = bc3['mediciones'].pop(old_code)

    # 6. Relaciones de capítulo (clave y referencias en el raw string)
    n_refs_B = 0
    new_rel_caps = {}
    for cap_code, raw in bc3['rel_caps'].items():
        new_cap = new_code if cap_code == old_code else cap_code
        parts = raw.split('\\')
        new_raw = ''
        for i in range(0, len(parts) - 1, 2):
            c = new_code if parts[i] == old_code else parts[i]
            m = parts[i+1] if i+1 < len(parts) else '0'
            new_raw += f"{c}\\{m}\\"
            if parts[i] == old_code:
                n_refs_B += 1
        new_rel_caps[new_cap] = new_raw
    bc3['rel_caps'] = new_rel_caps

    # 7. Orden
    bc3['orden'] = [
        (t, new_code if c == old_code else c)
        for t, c in bc3['orden']
    ]

    # 8. Recalcular precios de partidas afectadas
    recalculated = []
    for code in set(afectadas_por_D):
        total, ok, missing = _precio_calculado(bc3, code)
        if ok and not missing and total > 0:
            try:
                old_p = float(bc3['conceptos'][code]['precio'] or '0')
                if abs(old_p - total) > 0.0001:
                    bc3['conceptos'][code]['precio'] = f"{total:.4f}"
                    recalculated.append((code, old_p, total))
            except (ValueError, TypeError):
                pass

    print(f"  Referencias en ~D     : {n_refs_D}")
    print(f"  Referencias en ~B     : {n_refs_B}")
    if recalculated:
        print(f"  Precios recalculados  : {len(recalculated)}")
        for code, old_p, new_p in recalculated:
            print(f"    {code}: {old_p:.4f} → {new_p:.4f}")

    if output_path is None:
        base, ext = os.path.splitext(path)
        output_path = f"{base}_renamed{ext}"

    _backup(path)
    n = write_bc3(bc3, output_path, encoding=bc3['encoding'])
    print(f"\nGuardado: {output_path} ({n} líneas)")

    _log_change(output_path, 'rename', f"{old_code} → {new_code}")
    _run_propagacion(output_path)

    # Verificación
    bc3_v = parse_bc3(output_path)
    new_ok  = new_code in bc3_v['conceptos']
    old_gone = old_code not in bc3_v['conceptos']
    m_ok = (old_code not in bc3_v['mediciones'] or new_code in bc3_v['mediciones'])

    print(f"  ✓ '{new_code}' presente: {'SÍ' if new_ok else 'NO — REVISAR'}")
    print(f"  ✓ '{old_code}' eliminado: {'SÍ' if old_gone else 'NO — REVISAR'}")

    # Verificar que no quede ninguna ref al código viejo en ~D
    dangling = [
        code for code, comps in bc3_v['descomps'].items()
        if any(c['code'] == old_code for c in comps)
    ]
    if dangling:
        print(f"  ✗ Referencias residuales en ~D: {dangling}")
    else:
        print(f"  ✓ Sin referencias residuales en ~D")


def cmd_compare(path_a, path_b):
    """
    Compara dos versiones de un bc3.
    Muestra: conceptos añadidos, eliminados, con datos ~C cambiados,
    con descomposición ~D cambiada.
    Los cambios en ~M se reportan por separado — son críticos.
    """
    print(f"\nComparando:")
    print(f"  A (base)   : {path_a}")
    print(f"  B (nuevo)  : {path_b}\n")

    bc3_a = parse_bc3(path_a)
    bc3_b = parse_bc3(path_b)

    codes_a = set(bc3_a['conceptos'].keys())
    codes_b = set(bc3_b['conceptos'].keys())

    eliminados = sorted(codes_a - codes_b)
    añadidos   = sorted(codes_b - codes_a)
    comunes    = sorted(codes_a & codes_b)

    print(f"RESUMEN")
    print(f"  Conceptos en A  : {len(codes_a)}")
    print(f"  Conceptos en B  : {len(codes_b)}")
    print(f"  Solo en A (eliminados): {len(eliminados)}")
    print(f"  Solo en B (nuevos)    : {len(añadidos)}")
    print(f"  En ambos              : {len(comunes)}")

    # Cambios en conceptos comunes
    c_changed  = []  # campo ~C distinto
    d_changed  = []  # descomposición ~D distinta
    m_changed  = []  # medición ~M distinta — crítico

    CAMPOS_C = ['unidad', 'resumen', 'precio', 'tipo']
    for code in comunes:
        ca = bc3_a['conceptos'][code]
        cb = bc3_b['conceptos'][code]
        diffs_c = {k: (ca.get(k, ''), cb.get(k, ''))
                   for k in CAMPOS_C
                   if ca.get(k, '') != cb.get(k, '')}
        if diffs_c:
            c_changed.append((code, diffs_c))

        # Comparar ~D como raw string (más fiable que comparar listas)
        d_a = _format_descomp(bc3_a['descomps'].get(code, []))
        d_b = _format_descomp(bc3_b['descomps'].get(code, []))
        if d_a != d_b:
            d_changed.append((code, d_a, d_b))

        m_a = bc3_a['mediciones'].get(code, '')
        m_b = bc3_b['mediciones'].get(code, '')
        if m_a != m_b:
            m_changed.append((code, m_a[:80], m_b[:80]))

    print(f"  Con ~C cambiado       : {len(c_changed)}")
    print(f"  Con ~D cambiada       : {len(d_changed)}")
    print(f"  Con ~M cambiada       : {len(m_changed)}  {'⚠ REVISAR — mediciones críticas' if m_changed else ''}")

    if eliminados:
        print(f"\nELIMINADOS (en A, no en B) — {len(eliminados)}:")
        for code in eliminados[:30]:
            res = bc3_a['conceptos'][code]['resumen'][:55]
            print(f"  - {code:<22} {res}")
        if len(eliminados) > 30:
            print(f"  ... y {len(eliminados)-30} más")

    if añadidos:
        print(f"\nNUEVOS (en B, no en A) — {len(añadidos)}:")
        for code in añadidos[:30]:
            res = bc3_b['conceptos'][code]['resumen'][:55]
            print(f"  + {code:<22} {res}")
        if len(añadidos) > 30:
            print(f"  ... y {len(añadidos)-30} más")

    if c_changed:
        print(f"\nCAMBIOS EN ~C — {len(c_changed)}:")
        for code, diffs in c_changed[:30]:
            print(f"  {code}:")
            for campo, (va, vb) in diffs.items():
                print(f"    {campo}: '{va}' → '{vb}'")
        if len(c_changed) > 30:
            print(f"  ... y {len(c_changed)-30} más")

    if d_changed:
        print(f"\nCAMBIOS EN ~D — {len(d_changed)}:")
        for code, d_a_str, d_b_str in d_changed[:20]:
            res = bc3_a['conceptos'].get(code, {}).get('resumen', '')[:40]
            print(f"  {code}  {res}")
            comps_a = bc3_a['descomps'].get(code, [])
            comps_b = bc3_b['descomps'].get(code, [])
            codes_a_d = {c['code'] for c in comps_a}
            codes_b_d = {c['code'] for c in comps_b}
            for c in comps_a:
                if c['code'] not in codes_b_d:
                    print(f"    - QUITADO: {c['code']}  f={c['factor']} r={c['rendimiento']}")
            for c in comps_b:
                if c['code'] not in codes_a_d:
                    print(f"    + AÑADIDO: {c['code']}  f={c['factor']} r={c['rendimiento']}")
            for ca_comp in comps_a:
                for cb_comp in comps_b:
                    if ca_comp['code'] == cb_comp['code']:
                        changes = []
                        if ca_comp['factor'] != cb_comp['factor']:
                            changes.append(f"factor {ca_comp['factor']}→{cb_comp['factor']}")
                        if ca_comp['rendimiento'] != cb_comp['rendimiento']:
                            changes.append(f"rend {ca_comp['rendimiento']}→{cb_comp['rendimiento']}")
                        if changes:
                            print(f"    ~ {ca_comp['code']}: {', '.join(changes)}")
        if len(d_changed) > 20:
            print(f"  ... y {len(d_changed)-20} más")

    if m_changed:
        print(f"\n⚠ CAMBIOS EN ~M (MEDICIONES) — {len(m_changed)} — REVISAR MANUALMENTE:")
        for code, ma, mb in m_changed[:15]:
            print(f"  {code}:")
            print(f"    A: {ma}")
            print(f"    B: {mb}")
        if len(m_changed) > 15:
            print(f"  ... y {len(m_changed)-15} más")

    if not eliminados and not añadidos and not c_changed and not d_changed and not m_changed:
        print("\n  ✓ Los dos archivos son idénticos en contenido bc3")


# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

def cmd_export(path, output_path=None):
    """
    Vuelca el bc3 a dos CSV para revisión en Excel:
      - [archivo]_export.csv      : CODIGO, TIPO, UNIDAD, RESUMEN, PRECIO, NUM_COMPS
      - [archivo]_descomps.csv    : CODIGO_PADRE, CODIGO_COMP, FACTOR, RENDIMIENTO,
                                    PRECIO_COMP, RESUMEN_COMP, IMPORTE
    Útil para verificar precios y descomposiciones sin abrir Presto.
    """
    import csv

    bc3 = parse_bc3(path)

    base = os.path.splitext(output_path or path)[0]
    path_exp   = base + '_export.csv'
    path_descp = base + '_descomps.csv'

    # CSV 1: conceptos
    with open(path_exp, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['CODIGO', 'TIPO', 'UNIDAD', 'RESUMEN', 'PRECIO', 'NUM_COMPS',
                    'PRECIO_CALCULADO', 'DIFF_PRESTO'])
        for code, c in bc3['conceptos'].items():
            n_comps = len(bc3['descomps'].get(code, []))
            try:
                precio_decl = float(c['precio']) if c['precio'] else 0.0
            except (ValueError, TypeError):
                precio_decl = 0.0
            total_calc, ok, missing_comps = _precio_calculado(bc3, code)
            if missing_comps:
                print(f"  [EXPORT] {code}: componentes no encontrados → {missing_comps}")
            if ok and total_calc is not None and not missing_comps:
                diff = abs(precio_decl - total_calc)
                diff_str  = f"{diff:.4f}".replace('.', ',')
                calc_str  = f"{total_calc:.4f}".replace('.', ',')
            else:
                diff_str = ''
                calc_str = ''
            precio_str = f"{precio_decl:.4f}".replace('.', ',')
            w.writerow([code, c['tipo'], c['unidad'], c['resumen'],
                        precio_str, n_comps, calc_str, diff_str])

    # CSV 2: descomposiciones
    with open(path_descp, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow(['CODIGO_PADRE', 'RESUMEN_PADRE',
                    'CODIGO_COMP', 'RESUMEN_COMP',
                    'FACTOR', 'RENDIMIENTO',
                    'PRECIO_COMP', 'IMPORTE'])
        for code, comps in bc3['descomps'].items():
            res_padre = bc3['conceptos'].get(code, {}).get('resumen', '')
            for comp in comps:
                cd_raw = bc3['conceptos'].get(comp['code'])
                cd = cd_raw or {}
                falta_c = '' if cd_raw else ' ¡FALTA ~C!'
                res_comp = cd.get('resumen', '') + falta_c
                try:
                    cp = float(cd.get('precio', '0') or '0')
                    fv = float(comp['factor'] or '1')
                    r  = float(comp['rendimiento'] or '0')
                    importe = cp * fv * r
                    cp_str  = f"{cp:.4f}".replace('.', ',')
                    imp_str = f"{importe:.4f}".replace('.', ',')
                except (ValueError, TypeError):
                    cp_str  = ''
                    imp_str = ''
                w.writerow([code, res_padre,
                            comp['code'], res_comp,
                            comp['factor'], comp['rendimiento'],
                            cp_str, imp_str])

    n_c = len(bc3['conceptos'])
    n_d = sum(len(v) for v in bc3['descomps'].values())
    print(f"\nExportado: {path_exp}")
    print(f"  {n_c} conceptos")
    print(f"Exportado: {path_descp}")
    print(f"  {n_d} líneas de descomposición")
    print(f"Nota: separador de columnas = ';' (compatible con Excel español)")


# ─────────────────────────────────────────────────────────────────────────────
# MODIFY-DESCOMP
# ─────────────────────────────────────────────────────────────────────────────

def cmd_modify_descomp(path, code, operation, op_args, output_path=None):
    """
    Modifica la descomposición ~D de una partida.

    Operaciones:
      set-rendimiento  comp_code=nuevo_rendimiento [...]
      set-factor       comp_code=nuevo_factor [...]
      add              comp_code factor rendimiento
      remove           comp_code

    Tras cualquier modificación:
      1. Actualiza el precio ~C con el valor calculado de ~D (previene problema Presto).
      2. Hace backup del original.
      3. Verifica ~M intacta en el output.

    NUNCA modifica ~M, ~T, ni ningún otro campo de ~C excepto precio.
    """
    bc3 = parse_bc3(path)

    if code not in bc3['conceptos']:
        print(f"ERROR: '{code}' no existe en {path}")
        sys.exit(1)

    # Asegurar que existe la entrada en descomps
    if code not in bc3['descomps']:
        bc3['descomps'][code] = []
        bc3['orden'].append(('D', code))

    comps = bc3['descomps'][code]

    if operation == 'set-rendimiento':
        if not op_args:
            print("ERROR: set-rendimiento requiere comp_code=valor")
            sys.exit(1)
        changes = {}
        for arg in op_args:
            if '=' not in arg:
                print(f"ERROR: formato incorrecto '{arg}'. Usar comp_code=rendimiento")
                sys.exit(1)
            k, v = arg.split('=', 1)
            changes[k.strip()] = v.strip()
        found = {c['code'] for c in comps}
        for comp_code, new_r in changes.items():
            if comp_code not in found:
                print(f"ERROR: componente '{comp_code}' no está en ~D de {code}")
                print(f"  Componentes actuales: {', '.join(c['code'] for c in comps)}")
                sys.exit(1)
            for comp in comps:
                if comp['code'] == comp_code:
                    print(f"  {comp_code}: rendimiento {comp['rendimiento']} → {new_r}")
                    comp['rendimiento'] = new_r

    elif operation == 'set-factor':
        if not op_args:
            print("ERROR: set-factor requiere comp_code=valor")
            sys.exit(1)
        changes = {}
        for arg in op_args:
            if '=' not in arg:
                print(f"ERROR: formato incorrecto '{arg}'. Usar comp_code=factor")
                sys.exit(1)
            k, v = arg.split('=', 1)
            changes[k.strip()] = v.strip()
        found = {c['code'] for c in comps}
        for comp_code, new_f in changes.items():
            if comp_code not in found:
                print(f"ERROR: componente '{comp_code}' no está en ~D de {code}")
                sys.exit(1)
            for comp in comps:
                if comp['code'] == comp_code:
                    print(f"  {comp_code}: factor {comp['factor']} → {new_f}")
                    comp['factor'] = new_f

    elif operation == 'add':
        if len(op_args) < 3:
            print("ERROR: add requiere comp_code factor rendimiento")
            print("  Ejemplo: add MOOF1ALB 1 0.250")
            sys.exit(1)
        comp_code   = op_args[0]
        new_factor  = op_args[1]
        new_rend    = op_args[2]
        # Validar que el componente existe en el bc3
        if comp_code not in bc3['conceptos']:
            print(f"⚠  Aviso: '{comp_code}' no tiene ~C en este bc3. "
                  f"Se añade igualmente, pero validate dará aviso.")
        # Comprobar duplicado
        existing = [c for c in comps if c['code'] == comp_code]
        if existing:
            print(f"⚠  '{comp_code}' ya existe en ~D. Usa set-rendimiento o set-factor para cambiar valores.")
            print(f"  Actual: factor={existing[0]['factor']} rendimiento={existing[0]['rendimiento']}")
            sys.exit(1)
        comps.append({'code': comp_code, 'factor': new_factor, 'rendimiento': new_rend})
        print(f"  Añadido: {comp_code}  factor={new_factor}  rendimiento={new_rend}")

    elif operation == 'remove':
        if not op_args:
            print("ERROR: remove requiere comp_code")
            sys.exit(1)
        comp_code = op_args[0]
        antes = len(comps)
        bc3['descomps'][code] = [c for c in comps if c['code'] != comp_code]
        comps = bc3['descomps'][code]
        if len(comps) == antes:
            print(f"ERROR: '{comp_code}' no está en ~D de {code}")
            print(f"  Componentes actuales: {', '.join(c['code'] for c in comps)}")
            sys.exit(1)
        print(f"  Eliminado: {comp_code}")

    else:
        print(f"ERROR: operación desconocida '{operation}'")
        print("  Operaciones válidas: set-rendimiento, set-factor, add, remove")
        sys.exit(1)

    # Recalcular precio ~C automáticamente tras modificar ~D
    total_calc, ok, missing_calc = _precio_calculado(bc3, code)
    precio_anterior = bc3['conceptos'][code].get('precio', '0')
    if ok and total_calc is not None and total_calc > 0 and not missing_calc:
        precio_nuevo = f"{total_calc:.4f}"
        bc3['conceptos'][code]['precio'] = precio_nuevo
        print(f"\n  Precio ~C actualizado automáticamente:")
        print(f"    Antes  : {precio_anterior}")
        print(f"    Después: {precio_nuevo}")
        print(f"    (Presto no dará diferencia al recalcular)")
    elif missing_calc:
        print(f"\n  ⚠ Precio NO recalculado — componentes sin ~C: {missing_calc}")
        print(f"    El precio ~C queda como estaba: {precio_anterior}")
        print(f"    Añade los ~C que faltan o usa merge para traerlos del bc3 origen.")
    else:
        print(f"\n  ⚠ No se pudo recalcular el precio.")
        print(f"    Revisar con: python3 bc3_tools.py show {path} {code}")

    if output_path is None:
        base, ext = os.path.splitext(path)
        output_path = f"{base}_mod{ext}"

    _backup(path)
    n = write_bc3(bc3, output_path, encoding=bc3['encoding'])
    print(f"\nGuardado: {output_path} ({n} líneas)")

    # Verificación round-trip
    bc3_v  = parse_bc3(output_path)
    comps_v = bc3_v['descomps'].get(code, [])
    m_orig  = bc3['mediciones'].get(code, '')
    m_out   = bc3_v['mediciones'].get(code, '')
    m_ok    = (m_orig == m_out)

    print(f"✓ ~D guardada con {len(comps_v)} componentes")
    print(f"✓ ~M preservada intacta: {'SÍ' if m_ok else '⚠ REVISAR'}")

    _log_change(output_path, f'modify-descomp/{operation}', f"Código: {code}\nArgs: {op_args}")
    _run_propagacion(output_path)


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def _parse_args():
    args = sys.argv[1:]
    flags = {}
    positional = []
    for a in args:
        if a.startswith('--'):
            if '=' in a:
                k, v = a[2:].split('=', 1)
                flags[k] = v
            else:
                flags[a[2:]] = True
        else:
            positional.append(a)
    return positional, flags


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    positional, flags = _parse_args()
    cmd = positional[0].lower() if positional else ''

    if cmd == 'info':
        if len(positional) < 2:
            print("Uso: bc3_tools.py info archivo.bc3"); sys.exit(1)
        cmd_info(positional[1])

    elif cmd == 'show':
        if len(positional) < 3:
            print("Uso: bc3_tools.py show archivo.bc3 CODIGO"); sys.exit(1)
        cmd_show(positional[1], positional[2])

    elif cmd == 'modify':
        if len(positional) < 4:
            print("Uso: bc3_tools.py modify archivo.bc3 CODIGO campo=valor ..."); sys.exit(1)
        output = flags.get('output')
        changes = [p for p in positional[3:]]
        cmd_modify(positional[1], positional[2], changes, output)

    elif cmd == 'recalc':
        if len(positional) < 2:
            print("Uso: bc3_tools.py recalc archivo.bc3 [--output=salida.bc3] [--tolerance=0.02]"); sys.exit(1)
        output    = flags.get('output')
        tolerance = float(flags.get('tolerance', '0.02'))
        cmd_recalc(positional[1], output, tolerance)

    elif cmd == 'merge':
        if len(positional) < 4:
            print("Uso: bc3_tools.py merge base.bc3 adicional.bc3 salida.bc3 [--on-conflict=keep-base|keep-new] [--allow-mediciones]"); sys.exit(1)
        on_conflict      = flags.get('on-conflict', 'keep-base')
        allow_mediciones = 'allow-mediciones' in flags
        cmd_merge(positional[1], positional[2], positional[3],
                  on_conflict, allow_mediciones)

    elif cmd == 'validate':
        if len(positional) < 2:
            print("Uso: bc3_tools.py validate archivo.bc3"); sys.exit(1)
        cmd_validate(positional[1])

    elif cmd == 'extract':
        if len(positional) < 3:
            print("Uso: bc3_tools.py extract src.bc3 CODIGO1 [CODIGO2 ...] [--output=salida.bc3]")
            sys.exit(1)
        output = flags.get('output')
        codes  = positional[2:]
        cmd_extract(positional[1], codes, output)

    elif cmd == 'rename':
        if len(positional) < 4:
            print("Uso: bc3_tools.py rename archivo.bc3 CODIGO_VIEJO CODIGO_NUEVO [--output=salida.bc3]")
            sys.exit(1)
        output = flags.get('output')
        cmd_rename(positional[1], positional[2], positional[3], output)

    elif cmd == 'compare':
        if len(positional) < 3:
            print("Uso: bc3_tools.py compare archivo_a.bc3 archivo_b.bc3"); sys.exit(1)
        cmd_compare(positional[1], positional[2])

    elif cmd == 'export':
        if len(positional) < 2:
            print("Uso: bc3_tools.py export archivo.bc3 [--output=base_salida]"); sys.exit(1)
        output = flags.get('output')
        cmd_export(positional[1], output)

    elif cmd == 'modify-descomp':
        # Uso: modify-descomp archivo.bc3 CODIGO OPERACION [args...] [--output=salida.bc3]
        if len(positional) < 4:
            print("Uso: bc3_tools.py modify-descomp archivo.bc3 CODIGO OPERACION [args]")
            print("  Operaciones: set-rendimiento, set-factor, add, remove")
            print("  Ejemplos:")
            print("    modify-descomp presupuesto.bc3 E02.03 set-rendimiento MOOF1ALB=0.250")
            print("    modify-descomp presupuesto.bc3 E02.03 add MOOF1ALB 1 0.250")
            print("    modify-descomp presupuesto.bc3 E02.03 remove MOOF1ALB")
            sys.exit(1)
        output    = flags.get('output')
        operation = positional[3]
        op_args   = positional[4:]
        cmd_modify_descomp(positional[1], positional[2], operation, op_args, output)

    else:
        print(f"Comando desconocido: '{cmd}'")
        print("Comandos: info, show, extract, rename, compare, export, modify, modify-descomp, merge, recalc, validate")
        sys.exit(1)


if __name__ == '__main__':
    main()
