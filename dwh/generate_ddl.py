import yaml
import os

TYPE_MAP = {
    'uuid':      'VARCHAR(36)',
    'varchar':   'VARCHAR(500)',
    'text':      'VARCHAR(65533)',
    'integer':   'INT',
    'serial':    'INT',
    'decimal':   'DECIMAL(18,2)',
    'boolean':   'BOOLEAN',
    'date':      'DATE',
    'timestamp': 'DATETIME',
    'inet':      'VARCHAR(50)',
}


def pg_to_sr(pg_type: str) -> str:
    return TYPE_MAP.get(pg_type.lower(), 'VARCHAR(500)')


def generate_ddl(config_path: str, output_path: str):
    print(f"Reading config: {config_path}")
    with open(config_path, 'r', encoding='utf-8') as f:
        schema = yaml.safe_load(f)

    lines = [
        "-- =====================================================",
        "-- Auto-generated Data Vault 2.0 DDL for StarRocks MPP",
        "-- Source: source_schema.yaml",
        "-- =====================================================",
        "",
        "CREATE DATABASE IF NOT EXISTS dwh_detailed;",
        "USE dwh_detailed;",
        "",
    ]

    PROPS = '("replication_num" = "1")'
    BUCKETS = 4

    for table in schema.get('tables', []):
        name   = table['name']
        source = table.get('source_system', 'unknown')
        bk     = table.get('business_key')
        bk_type = pg_to_sr(table.get('business_key_type', 'varchar'))
        refs   = table.get('references', [])
        attrs  = table.get('attributes', [])

        # ── HUB ──────────────────────────────────────────────
        if bk:
            lines += [
                f"-- ===== HUB: {name.upper()} =====",
                f"CREATE TABLE IF NOT EXISTS hub_{name} (",
                f"    hk_{name}     VARCHAR(32)   NOT NULL COMMENT 'MD5({bk})',",
                f"    {bk}          {bk_type}     NOT NULL,",
                f"    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                f"    record_source VARCHAR(100)  NOT NULL DEFAULT '{source}'",
                f") UNIQUE KEY(hk_{name})",
                f"COMMENT 'Hub: {name}'",
                f"DISTRIBUTED BY HASH(hk_{name}) BUCKETS {BUCKETS}",
                f"PROPERTIES {PROPS};",
                "",
            ]

            # ── SATELLITE ─────────────────────
            if attrs:
                filtered_attrs = [
                    a for a in attrs
                    if a['name'] not in (
                        'effective_from', 'effective_to', 'is_current',
                        'created_at', 'updated_at', 'created_by', 'updated_by'
                    )
                ]

                attr_lines = [
                    f"    {a['name']:<30} {pg_to_sr(a['type'])}"
                    for a in filtered_attrs
                ]
                attr_cols = ",\n".join(attr_lines) if attr_lines else ""
                
                lines += [
                    f"CREATE TABLE IF NOT EXISTS sat_{name} (",
                    f"    hk_{name}     VARCHAR(32)   NOT NULL,",
                    f"    hash_diff     VARCHAR(128)  NOT NULL,",
                    f"    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                    f"    record_source VARCHAR(100)  NOT NULL DEFAULT '{source}',",
                    attr_cols,
                    f") UNIQUE KEY(hk_{name}, hash_diff)",
                    f"COMMENT 'Satellite: {name} attributes'",
                    f"DISTRIBUTED BY HASH(hk_{name}) BUCKETS {BUCKETS}",
                    f"PROPERTIES {PROPS};",
                    "",
                ]

            # ── LINKS ─────────────────
            for ref in refs:
                target = ref['target']
                lnk = f"lnk_{name}_{target}"
                lines += [
                    f"CREATE TABLE IF NOT EXISTS {lnk} (",
                    f"    hk_{lnk}      VARCHAR(32)  NOT NULL,",
                    f"    hk_{name}     VARCHAR(32)  NOT NULL,",
                    f"    hk_{target}   VARCHAR(32)  NOT NULL,",
                    f"    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                    f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}'",
                    f") UNIQUE KEY(hk_{lnk})",
                    f"COMMENT 'Link: {name} → {target}'",
                    f"DISTRIBUTED BY HASH(hk_{lnk}) BUCKETS {BUCKETS}",
                    f"PROPERTIES {PROPS};",
                    "",
                ]

        # ── SAT ────────
        elif not bk and len(refs) == 1:
            target = refs[0]['target']
            attr_lines = [
                f"    {a['name']:<30} {pg_to_sr(a['type'])}"
                for a in attrs
            ]
            attr_cols = ",\n".join(attr_lines) if attr_lines else ""

            lines += [
                f"-- ===== SAT: {name.upper()} =====",
                f"CREATE TABLE IF NOT EXISTS sat_{name} (",
                f"    hk_{target}   VARCHAR(32)   NOT NULL,",
                f"    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                f"    hash_diff     VARCHAR(128)  NOT NULL,",
                f"    record_source VARCHAR(100)  NOT NULL DEFAULT '{source}',",
                attr_cols,
                f") DUPLICATE KEY(hk_{target}, load_dt)",
                f"COMMENT 'Satellite: {name}'",
                f"DISTRIBUTED BY HASH(hk_{target}) BUCKETS {BUCKETS}",
                f"PROPERTIES {PROPS};",
                "",
            ]

        # ── LINK + SAT ──────────
        elif not bk and len(refs) > 1:
            lnk = f"lnk_{name}"
            ref_cols = '\n'.join(
                f"    hk_{r['target']:<24} VARCHAR(32)  NOT NULL,"
                for r in refs
            )
            lines += [
                f"-- ===== LINK+SAT: {name.upper()} =====",
                f"CREATE TABLE IF NOT EXISTS {lnk} (",
                f"    hk_{lnk}      VARCHAR(32)  NOT NULL,",
                ref_cols,
                f"    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}'",
                f") UNIQUE KEY(hk_{lnk})",
                f"COMMENT 'Link: {name}'",
                f"DISTRIBUTED BY HASH(hk_{lnk}) BUCKETS {BUCKETS}",
                f"PROPERTIES {PROPS};",
                "",
            ]

            if attrs:
                attr_lines = [
                    f"    {a['name']:<30} {pg_to_sr(a['type'])}"
                    for a in attrs
                ]
                attr_cols = ",\n".join(attr_lines) if attr_lines else ""

                lines += [
                    f"CREATE TABLE IF NOT EXISTS sat_{name} (",
                    f"    hk_{lnk}      VARCHAR(32)   NOT NULL,",
                    f"    hash_diff     VARCHAR(128)  NOT NULL,",
                    f"    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,",
                    f"    record_source VARCHAR(100)  NOT NULL DEFAULT '{source}',",
                    attr_cols,
                    f") UNIQUE KEY(hk_{lnk}, hash_diff)",
                    f"COMMENT 'Satellite: {name} attributes (on Link)'",
                    f"DISTRIBUTED BY HASH(hk_{lnk}) BUCKETS {BUCKETS}",
                    f"PROPERTIES {PROPS};",
                    "",
                ]

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f"StarRocks DDL saved to {output_path}")


if __name__ == "__main__":
    BASE = os.path.dirname(os.path.abspath(__file__))
    generate_ddl(
        config_path=os.path.join(BASE, 'source_schema.yaml'),
        output_path=os.path.join(BASE, 'ddl/001_starrocks_dwh_detailed.sql')
    )
