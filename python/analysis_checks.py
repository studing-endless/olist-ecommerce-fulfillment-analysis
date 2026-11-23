"""General input checks, separate from opt-in checks for the published dataset."""
import os
import numpy as np
import pandas as pd


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_review_orders(df):
    columns = ['order_id', 'customer_unique_id', 'customer_state', 'order_month',
               'delivery_days', 'delay_days', 'is_late', 'review_score', 'is_bad_review']
    require(set(columns) <= set(df), 'Missing review analysis columns')
    require(len(df) > 0 and df[columns].notna().all().all(), 'Empty or incomplete review data')
    require(df.order_id.is_unique, 'Duplicate order IDs')
    numeric = ['delivery_days', 'delay_days', 'is_late', 'review_score', 'is_bad_review']
    values = df[numeric].apply(pd.to_numeric, errors='raise')
    require(np.isfinite(values).all().all(), 'Non-finite review values')
    require((values.delivery_days >= 0).all(), 'Negative delivery duration')
    require((values.delay_days % 1 == 0).all(), 'Delay must use whole calendar days')
    require(values.review_score.isin([1, 2, 3, 4, 5]).all(), 'Invalid review score')
    require(values.is_late.isin([0, 1]).all() and values.is_bad_review.isin([0, 1]).all(), 'Invalid binary flags')
    require((values.is_late == (values.delay_days > 0)).all(), 'Late flag disagrees with calendar-day delay')
    require((values.is_bad_review == (values.review_score <= 2)).all(), 'Bad-review flag disagrees with score')


def check_seller_profile(df):
    counts = ['order_count', 'late_orders', 'reviewed_orders', 'reviewed_late_orders',
              'bad_review_orders', 'late_bad_orders', 'ontime_bad_orders']
    require(set(['seller_id', 'late_rate_pct', 'bad_review_rate_pct'] + counts) <= set(df), 'Missing seller columns')
    require(len(df) > 0 and df.seller_id.notna().all() and df.seller_id.is_unique, 'Empty or duplicate seller IDs')
    require(df[counts].notna().all().all(), 'Missing seller counts')
    require(((df[counts] >= 0) & (df[counts] % 1 == 0)).all().all(), 'Invalid seller counts')
    require((df.order_count > 0).all(), 'Seller has no orders')
    for numerator, denominator in [('late_orders', 'order_count'), ('reviewed_orders', 'order_count'),
                                   ('bad_review_orders', 'reviewed_orders'), ('reviewed_late_orders', 'late_orders'),
                                   ('reviewed_late_orders', 'reviewed_orders'), ('late_bad_orders', 'reviewed_late_orders')]:
        require((df[numerator] <= df[denominator]).all(), numerator + ' exceeds denominator')
    require((df.ontime_bad_orders <= df.reviewed_orders - df.reviewed_late_orders).all(), 'Invalid on-time bad count')
    require((df.late_bad_orders + df.ontime_bad_orders == df.bad_review_orders).all(), 'Bad-review partition mismatch')
    require((df.late_orders + df.ontime_bad_orders <= df.order_count).all(), 'Issue union exceeds orders')
    for rate, numerator, denominator in [('late_rate_pct', 'late_orders', 'order_count'),
                                        ('bad_review_rate_pct', 'bad_review_orders', 'reviewed_orders')]:
        expected = 100 * df[numerator] / df[denominator].replace(0, np.nan)
        require((df[rate].isna() == expected.isna()).all(), 'Rate missingness mismatch')
        require(np.isclose(df[rate], expected, atol=.005001, rtol=0, equal_nan=True).all(), 'Rounded rate mismatch')


def shortlist_union(priority, size=5):
    """Preserve the original input order, pandas ranking and tie handling."""
    return pd.concat([priority.nlargest(size, 'issue_orders'),
                      priority.nlargest(size, 'issue_rate_pct')]).drop_duplicates('seller_id')


def reference_enabled():
    return os.environ.get('OLIST_VERIFY_REFERENCE') == '1'
