import json
import yaml
import hashlib
import psycopg2
from kafka import KafkaConsumer
import os
import time
from datetime import datetime, timedelta


class DMPService:
    def __init__(self, config_path):
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)

        # env
        db_host = os.getenv("DWH_HOST", 'postgres-dwh')
        db_name = os.getenv("DWH_DB", 'dwh')
        db_user = os.getenv("DWH_USER", 'postgres')
        db_pass = os.getenv("DWH_PASSWORD", 'postgres')

        print(f"Connecting to DWH at {db_host}...")

        while True:
            try:
                self.db_conn = psycopg2.connect(
                    host=db_host,
                    database=db_name,
                    user=db_user,
                    password=db_pass
                )
                self.db_conn.autocommit = True
                print("Successfully connected to DWH!")
                break
            except psycopg2.OperationalError:
                print("DWH is not ready yet. Waiting 2 seconds...")
                time.sleep(2)

    def generate_dv_hash(self, data):
        """Create MD5 hash for business key or satellites"""
        if isinstance(data, dict):
            data = json.dumps(data, sort_keys=True)
        return hashlib.md5(str(data).encode()).hexdigest()
    
    def process_message(self, topic_config, message_value):
        if 'payload' in message_value:
            data = message_value['payload'].get('after')
        else:
            data = message_value.get('after')        

        if not data:
            print(f"Skipping message: no 'after' data found in {message_value.get('op', 'unknown op')}")
            return
        
        print(f"Processing data for {topic_config['name']}: {data.get('email')}")
        cursor = self.db_conn.cursor()
        hub_hash_id = None

        # HUB
        if 'hub' in topic_config:
            hub_cfg = topic_config['hub']
            business_key_value = data[hub_cfg['business_key']]
            hub_hash_id = self.generate_dv_hash(business_key_value)

            cursor.execute(f"""
                INSERT INTO dwh_detailed.{hub_cfg['table']} ({hub_cfg['target_key']}, {hub_cfg['business_key']}, record_source)
                VALUES (%s, %s, %s) ON CONFLICT DO NOTHING
            """, (hub_hash_id, business_key_value, topic_config['name']))

        # LINK
        if 'links' in topic_config and hub_hash_id:
            for link_cfg in topic_config['links']:
                target_bk_val = data.get(link_cfg['target_business_key_field'])

                if target_bk_val:
                    target_hash = self.generate_dv_hash(target_bk_val)
                    link_hash = self.generate_dv_hash(hub_hash_id + target_hash)

                    cursor.execute(f"""
                        INSERT INTO dwh_detailed.{link_cfg['table']}
                        ({link_cfg['link_key']}, {link_cfg['source_hub_key']}, {link_cfg['target_hub_key']}, record_source)
                        VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING
                    """, (link_hash, hub_hash_id, target_hash, topic_config['name']))

        # SATELLITE
        if 'satellite' in topic_config:
            sat_cfg = topic_config['satellite']

            if not hub_hash_id:
                return

            processed_values = []
            for attr in sat_cfg['attributes']:
                val = data.get(attr)

                if isinstance(val, int):
                    if val > 10**12:
                        val = datetime.fromtimestamp(val / 1000000.0)
                    elif 'date' in attr or 'birth' in attr:
                        val = (datetime(1970, 1, 1) + timedelta(days=val)).date() 
                
                processed_values.append(val)
            
            hash_diff = self.generate_dv_hash({k: data[k] for k in sat_cfg['attributes'] if k in data})

            cursor.execute(f"""
                INSERT INTO dwh_detailed.{sat_cfg['table']}
                ({sat_cfg['hub_key']}, hash_diff, record_source, {', '.join(sat_cfg['attributes'])})
                SELECT %s, %s, %s, {', '.join(['%s']*len(sat_cfg['attributes']))}
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dwh_detailed.{sat_cfg['table']}
                    WHERE {sat_cfg['hub_key']} = %s AND hash_diff = %s
                )
            """, (hub_hash_id, hash_diff, topic_config['name'], *processed_values, hub_hash_id, hash_diff))

    def run(self):
        topics = []
        topic_map = {}
        for service in self.config['services'].values():
            for t in service['topics']:
                topics.append(t['name'])
                topic_map[t['name']] = t
        
        consumer = KafkaConsumer(
            *topics,
            bootstrap_servers=os.getenv("KAFKA_BOOTSTRAP", 'kafka:9092'),
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            group_id='dmp-dwh-loader-v2',
            auto_offset_reset='earliest'
        )

        print(f"DMP Service started. Listening to: {topics}")
        for msg in consumer:
            self.process_message(topic_map[msg.topic], msg.value)


if __name__ == "__main__":
    service = DMPService('config.yaml')
    service.run()
