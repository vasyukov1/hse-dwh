import json
import yaml
import hashlib
import pymysql
import os
import time
from datetime import datetime, timedelta
from kafka import KafkaConsumer


class DMPService:
    def __init__(self, config_path):
        with open(config_path, 'r') as f:
            self.config = yaml.safe_load(f)

        db_host = os.getenv("DWH_HOST", 'starrocks')
        db_port = int(os.getenv("DWH_PORT", '9030'))
        db_name = os.getenv("DWH_DB", 'dwh_detailed')
        db_user = os.getenv("DWH_USER", 'root')
        db_pass = os.getenv("DWH_PASSWORD", '')

        print(f"Connecting to StarRocks DWH at {db_host}:{db_port}/{db_name}...")
        while True:
            try:
                self.db_conn = pymysql.connect(
                    host=db_host, port=db_port,
                    database=db_name, user=db_user, password=db_pass,
                    autocommit=True, connect_timeout=10, charset='utf8mb4'
                )
                print("Connected to StarRocks DWH!")
                break
            except pymysql.err.OperationalError as e:
                print(f"StarRocks DWH not ready yet ({e}). Waiting 2 seconds...")
                time.sleep(2)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _md5(self, data):
        if isinstance(data, dict):
            data = json.dumps(data, sort_keys=True)
        return hashlib.md5(str(data).encode()).hexdigest()
    
    def _coerce(self, val, attr_name):
        if isinstance(val, int):
            if val > 10 ** 12:
                return datetime.fromtimestamp(val / 1_000_000.0)
            if any(k in attr_name for k in ('date', 'birth')):
                return (datetime(1970, 1, 1) + timedelta(days=val)).date()
        return val
    
    def _insert(self, table: str, columns: list, values: tuple):
        cols = ', '.join(columns)
        placeholders = ', '.join(['%s'] * len(values))
        cur = self.db_conn.cursor()
        cur.execute(f"INSERT INTO {table} ({cols}) VALUES ({placeholders})", values)
    
    # ------------------------------------------------------------------
    # Hub
    # ------------------------------------------------------------------

    def _process_hub(self, cfg: dict, data: dict, record_source: str) -> str:
        bk_val = data[cfg['business_key']]
        hk = self._md5(bk_val)
        self._insert(
            cfg['table'],
            [cfg['target_key'], cfg['business_key'], 'record_source'],
            (hk, bk_val, record_source)
        )
        return hk

    # ------------------------------------------------------------------
    # Link
    # ------------------------------------------------------------------

    def _process_link(self, cfg: dict, source_hk: str, data: dict, record_source: str):
        target_bk = data.get(cfg['target_business_key_field'])
        if not target_bk:
            return
        target_hk = self._md5(target_bk)
        link_hk = self._md5(source_hk + target_hk)
        try:
            self._insert(
                cfg['table'],
                [cfg['link_key'], cfg['source_hub_key'], cfg['target_hub_key'], 'record_source'],
                (link_hk, source_hk, target_hk, record_source)
            )
        except Exception as e:
            print(f"Link [{cfg['table']}] warning: {e}")

    # ------------------------------------------------------------------
    # Satellite
    # ------------------------------------------------------------------

    def _process_satellite(self, cfg: dict, hub_hk: str, data: dict, record_source: str):
        values = [self._coerce(data.get(a), a) for a in cfg['attributes']]
        hash_diff = self._md5({k: data.get(k) for k in cfg['attributes']})
        cols = [cfg['hub_key'], 'hash_diff', 'record_source'] + cfg['attributes']
        self._insert(cfg['table'], cols, (hub_hk, hash_diff, record_source, *values))

    # ------------------------------------------------------------------
    # History satellite
    # ------------------------------------------------------------------

    def _process_history_satellite(self, cfg: dict, data: dict, record_source: str):
        parent_bk = data.get(cfg['parent_business_key_field'])
        if not parent_bk:
            print(f"[{cfg['table']}] No parent BK, skipping")
            return
        parent_hk = self._md5(parent_bk)

        hub_key_val = parent_hk
        if 'link_table' in cfg:
            sec_bk = data.get(cfg['secondary_business_key_field'])
            if not sec_bk:
                return
            sec_hk = self._md5(sec_bk)
            link_hk = self._md5(parent_hk + sec_hk)
            try:
                self._insert(
                    cfg['link_table'],
                    [cfg['link_key'], cfg['parent_hub_key'], cfg['secondary_hub_key'], 'record_source'],
                    (link_hk, parent_hk, sec_hk, record_source)
                )
            except Exception as e:
                print(f"Link [{cfg['link_table']}] warning: {e}")
            hub_key_val = link_hk

        values = [self._coerce(data.get(a), a) for a in cfg['attributes']]
        hash_diff = self._md5({k: data.get(k) for k in cfg['attributes']})
        cols = [cfg['hub_key'], 'hash_diff', 'record_source'] + cfg['attributes']
        self._insert(cfg['table'], cols, (hub_key_val, hash_diff, record_source, *values))

    # ------------------------------------------------------------------
    # Router
    # ------------------------------------------------------------------
    
    def process_message(self, topic_config: dict, message: dict):
        payload = message.get('payload', message)
        data = payload.get('after')
        if not data:
            return

        source = topic_config['name']

        if 'history_satellite' in topic_config:
            self._process_history_satellite(topic_config['history_satellite'], data, source)
            return

        hub_hk = None
        if 'hub' in topic_config:
            hub_hk = self._process_hub(topic_config['hub'], data, source)

        if 'links' in topic_config and hub_hk:
            for lnk in topic_config['links']:
                self._process_link(lnk, hub_hk, data, source)

        if 'satellite' in topic_config and hub_hk:
            self._process_satellite(topic_config['satellite'], hub_hk, data, source)

    # ------------------------------------------------------------------
    # Main loop
    # ------------------------------------------------------------------
    
    def run(self):
        topics = []
        topic_map = {}
        for service in self.config['services'].values():
            for topic in service['topics']:
                topics.append(topic['name'])
                topic_map[topic['name']] = topic
        
        consumer = KafkaConsumer(
            *topics,
            bootstrap_servers=os.getenv("KAFKA_BOOTSTRAP", 'kafka:9092'),
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            group_id='dmp-dwh-loader-v1',
            auto_offset_reset='earliest'
        )

        print(f"DMP Service started. Listening to: {topics}")
        for msg in consumer:
            try:
                self.process_message(topic_map[msg.topic], msg.value)
            except Exception as e:
                print(f"Error processing message from {msg.topic}: {e}")


if __name__ == "__main__":
    service = DMPService('config.yaml')
    service.run()
