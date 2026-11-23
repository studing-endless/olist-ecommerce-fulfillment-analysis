"""Execute production SQL on synthetic TEMPORARY tables in an opt-in test instance."""
import os
from pathlib import Path
import unittest
import pymysql

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('OLIST_TEST_DB_NAME'), 'Requires dedicated test MySQL; see data_setup.md')
class SqlSemanticsTests(unittest.TestCase):
    def setUp(self):
        name = os.environ['OLIST_TEST_DB_NAME']
        if not name.startswith('olist_quality_') or os.environ.get('OLIST_DB_PORT') != '34067':
            raise RuntimeError('Synthetic SQL tests require the isolated quality database and port')
        self.conn = pymysql.connect(host='127.0.0.1', port=34067, database=name,
            user=os.environ['OLIST_DB_USER'], password=os.environ['OLIST_DB_PASSWORD'], charset='utf8mb4')
        self.addCleanup(self.conn.close)
        self.cursor = self.conn.cursor(pymysql.cursors.DictCursor)
        self.addCleanup(self.cursor.close)
        for ddl in [
            'olist_orders (order_id VARCHAR(32), customer_id VARCHAR(32), order_status VARCHAR(32), order_purchase_timestamp DATETIME, order_delivered_customer_date DATETIME, order_estimated_delivery_date DATETIME, order_delivered_carrier_date DATETIME)',
            'olist_customers (customer_id VARCHAR(32), customer_unique_id VARCHAR(32), customer_state VARCHAR(10))',
            'olist_order_items (order_id VARCHAR(32), seller_id VARCHAR(32), price DECIMAL(12,2), freight_value DECIMAL(12,2), shipping_limit_date DATETIME)',
            'olist_order_reviews (order_id VARCHAR(32), review_score INT)']:
            self.cursor.execute('CREATE TEMPORARY TABLE ' + ddl)
        self.cursor.execute("INSERT INTO olist_customers VALUES ('synthetic_c','synthetic_unique','SP')")

    def order(self, key, delivery='2018-01-02 23:00:00', promise='2018-01-02 00:00:00', carrier='2018-01-01 12:00:00'):
        self.cursor.execute("INSERT INTO olist_orders VALUES (%s,'synthetic_c','delivered','2018-01-01 12:00:00',%s,%s,%s)", (key, delivery, promise, carrier))
        self.cursor.execute("INSERT INTO olist_order_items VALUES (%s,'synthetic_seller',10,1,'2018-01-01 13:00:00')", (key,))

    def score(self, key, *scores):
        self.cursor.executemany('INSERT INTO olist_order_reviews VALUES (%s,%s)', [(key, score) for score in scores])

    def query(self, filename):
        sql = (ROOT/'sql'/filename).read_text(encoding='utf8').split(';', 1)[1].strip()
        self.cursor.execute(sql)
        return self.cursor.fetchall()

    def review_query(self):
        text = (ROOT/'sql/03_review_analysis.sql').read_text(encoding='utf8')
        sql = text.split('CREATE OR REPLACE VIEW v_order_review_analysis AS', 1)[1].split(';', 1)[0]
        self.cursor.execute(sql)
        return self.cursor.fetchall()

    def test_calendar_day_delay_and_second_precision_duration(self):
        self.order('synthetic_day')
        self.score('synthetic_day', 5)
        row = self.review_query()[0]
        self.assertEqual(row['is_late'], 0)
        self.assertEqual(row['delay_days'], 0)
        self.assertAlmostEqual(float(row['delivery_days']), 35/24, places=4)

    def test_missing_multi_conflicting_and_null_reviews_excluded(self):
        for key, scores in [('synthetic_single', [1]), ('synthetic_none', []),
                            ('synthetic_multi', [5, 5]), ('synthetic_conflict', [1, 5]), ('synthetic_null', [None])]:
            self.order(key)
            if scores:
                self.score(key, *scores)
        self.assertEqual([row['order_id'] for row in self.review_query()], ['synthetic_single'])

    def test_multiple_items_do_not_duplicate_seller_orders_or_issue_amount(self):
        self.order('synthetic_issue', delivery='2018-01-03')
        self.score('synthetic_issue', 1)
        self.cursor.execute("INSERT INTO olist_order_items VALUES ('synthetic_issue','synthetic_seller',20,2,'2018-01-01 13:00:00')")
        row = self.query('export_seller_profile.sql')[0]
        self.assertEqual((row['order_count'], row['late_orders'], row['bad_review_orders'], row['late_bad_orders']), (1, 1, 1, 1))
        row = self.query('export_seller_issue_amount.sql')[0]
        self.assertEqual(row['issue_orders'], 1)
        self.assertEqual(float(row['issue_amount']), 33.0)

    def test_handoff_uses_timestamp_final_delay_uses_date(self):
        self.order('synthetic_on_time', carrier='2018-01-01 14:00:00')
        self.order('synthetic_late', delivery='2018-01-03', carrier='2018-01-01 12:00:00')
        row = self.query('export_seller_handoff_profile.sql')[0]
        self.assertEqual((row['order_count'], row['late_handoff_orders'], row['late_delivery_orders'], row['ontime_handoff_late_delivery']), (2, 1, 1, 1))
