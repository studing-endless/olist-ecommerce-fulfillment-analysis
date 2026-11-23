import sys
from pathlib import Path
import unittest
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from analysis_checks import check_review_orders, shortlist_union
from reference_checks import verify_review


class InputChecksTests(unittest.TestCase):
    def frame(self):
        return pd.DataFrame({
            'order_id': ['synthetic_a', 'synthetic_b'],
            'customer_unique_id': ['synthetic_customer'] * 2,
            'customer_state': ['SP'] * 2, 'order_month': ['2018-01'] * 2,
            'delivery_days': [1.5, 2.25], 'delay_days': [0, 1],
            'is_late': [0, 1], 'review_score': [5, 1], 'is_bad_review': [0, 1]})

    def test_valid_small_data_does_not_require_fixed_snapshot(self):
        check_review_orders(self.frame())
        with self.assertRaisesRegex(ValueError, 'baseline'):
            verify_review(self.frame())

    def test_duplicate_order_rejected(self):
        data = self.frame()
        data.loc[1, 'order_id'] = data.loc[0, 'order_id']
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            check_review_orders(data)

    def test_inconsistent_late_or_review_flag_rejected(self):
        for field in ['is_late', 'is_bad_review']:
            with self.subTest(field=field):
                data = self.frame()
                data.loc[0, field] = 1
                with self.assertRaises(ValueError):
                    check_review_orders(data)

    def test_shortlist_preserves_volume_and_rate_union(self):
        data = pd.DataFrame({'seller_id': ['synthetic_a', 'synthetic_b', 'synthetic_c'],
                             'issue_orders': [20, 10, 2], 'issue_rate_pct': [20, 50, 80]})
        result = shortlist_union(data, size=2)
        self.assertEqual(result.seller_id.tolist(), data.seller_id.tolist())
        self.assertTrue(result.seller_id.is_unique)
