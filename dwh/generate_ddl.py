import yaml
import os


def generate_ddl(config_path, output_path):
    print(f"Read configuration from {config_path}...")
    with open(config_path, 'r', encoding='utf-8') as f:
        schema = yaml.safe_load(f)

    sql_lines = [
        "-- =========================================",
        "-- Auto-generated Data Vault 2.0 DDL Script",
        "-- =========================================",
        "CREATE SCHEMA IF NOT EXISTS dwh_detailed;\n"
    ]

    for table in schema.get('tables', []):
        name = table['name']
        source = table.get('source_system', 'system')
        bk = table.get('business_key')
        bk_type = table.get('business_key_type')
        refs = table.get('references', [])
        attrs = table.get('attributes', [])

        if bk:
            sql_lines.append(f"-- ================= HUB & SAT: {name.upper()} =================")
            sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.hub_{name} (")
            sql_lines.append(f"    hk_{name} VARCHAR(32) PRIMARY KEY,")
            sql_lines.append(f"    {bk} {bk_type} NOT NULL,")
            sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
            sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}'")
            sql_lines.append(f");\n")

            if attrs:
                sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.sat_{name} (")
                sql_lines.append(f"    hk_{name} VARCHAR(32) REFERENCES dwh_detailed.hub_{name}(hk_{name}),")
                sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
                sql_lines.append(f"    hash_diff VARCHAR(128) NOT NULL,")
                for attr in attrs:
                    sql_lines.append(f"    {attr['name']} {attr['type']},")
                sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}',")
                sql_lines.append(f"    PRIMARY KEY (hk_{name}, load_dt)")
                sql_lines.append(f");\n")
                
            for ref in refs:
                target = ref['target']
                link_name = f"lnk_{name}_{target}"
                sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.{link_name} (")
                sql_lines.append(f"    hk_{link_name} VARCHAR(32) PRIMARY KEY,")
                sql_lines.append(f"    hk_{name} VARCHAR(32) REFERENCES dwh_detailed.hub_{name}(hk_{name}),")
                sql_lines.append(f"    hk_{target} VARCHAR(32) REFERENCES dwh_detailed.hub_{target}(hk_{target}),")
                sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
                sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}'")
                sql_lines.append(f");\n")
            
        elif not bk and len(refs) == 1:
            target = refs[0]['target']
            sql_lines.append(f"-- ================= SAT (History): {name.upper()} =================")
            sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.sat_{name} (")
            sql_lines.append(f"    hk_{target} VARCHAR(32) REFERENCES dwh_detailed.hub_{target}(hk_{target}),")
            sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
            sql_lines.append(f"    hash_diff VARCHAR(128) NOT NULL,")
            for attr in attrs:
                sql_lines.append(f"    {attr['name']} {attr['type']},")
            sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}',")
            sql_lines.append(f"    PRIMARY KEY (hk_{target}, load_dt)")
            sql_lines.append(f");\n")
            
        # Generate LINK
        elif not bk and len(refs) > 1:
            link_name = f"lnk_{name}"
            sql_lines.append(f"-- ================= LINK & SAT: {name.upper()} =================")
            sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.{link_name} (")
            sql_lines.append(f"    hk_{link_name} VARCHAR(32) PRIMARY KEY,")
            for ref in refs:
                t = ref['target']
                sql_lines.append(f"    hk_{t} VARCHAR(32) REFERENCES dwh_detailed.hub_{t}(hk_{t}),")
            sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
            sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}'")
            sql_lines.append(f");\n")

            if attrs:
                sql_lines.append(f"CREATE TABLE IF NOT EXISTS dwh_detailed.sat_{name} (")
                sql_lines.append(f"    hk_{link_name} VARCHAR(32) REFERENCES dwh_detailed.{link_name}(hk_{link_name}),")
                sql_lines.append(f"    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,")
                sql_lines.append(f"    hash_diff VARCHAR(128) NOT NULL,")
                for attr in attrs:
                    sql_lines.append(f"    {attr['name']} {attr['type']},")
                sql_lines.append(f"    record_source VARCHAR(100) NOT NULL DEFAULT '{source}',")
                sql_lines.append(f"    PRIMARY KEY (hk_{link_name}, load_dt)")
                sql_lines.append(f");\n")
    
    # Write to file
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("\n".join(sql_lines))
    
    print(f"DDL successfully generated and saved to {output_path}")

if __name__ == "__main__":
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    config_file = os.path.join(BASE_DIR, 'source_schema.yaml')
    output_file = os.path.join(BASE_DIR, './ddl/001_dwh_detailed_ddl_generated.sql')
    
    generate_ddl(config_file, output_file)
