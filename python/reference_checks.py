"""Published Olist snapshot checks. Run scripts with OLIST_VERIFY_REFERENCE=1.

These expected values are historical regression baselines, not input validity rules.
"""
from analysis_checks import require


def verify_review(df):
    groups = df.groupby('is_late').is_bad_review.agg(['size', 'sum'])
    actual = (len(df), int(groups.loc[1, 'size']), int(groups.loc[1, 'sum']),
              int(groups.loc[0, 'size']), int(groups.loc[0, 'sum']))
    require(actual == (95299, 6353, 3962, 88946, 8227), 'Published review baseline mismatch')


def verify_sellers(df):
    actual = (len(df), *[int(df[c].sum()) for c in
              ['order_count', 'late_orders', 'reviewed_orders', 'bad_review_orders']])
    require(actual == (2948, 95195, 6521, 94051, 11597), 'Published seller baseline mismatch')


def verify_selection(focus, priority, shortlist):
    require((len(focus), len(priority), len(shortlist)) == (201, 55, 9), 'Published selection baseline mismatch')


def verify_sensitivity(results):
    baseline = results[100]['ids']
    require(len(baseline) == 9 and len(results[50]['ids'] & baseline) == 7
            and len(results[150]['ids'] & baseline) == 8, 'Published threshold sensitivity mismatch')


def verify_handoff(df):
    actual = tuple(int(df[c].sum()) for c in ['order_count', 'late_handoff_orders',
                   'late_delivery_orders', 'ontime_handoff_late_delivery'])
    require(actual == (95029, 8655, 6518, 4706), 'Published handoff baseline mismatch')


def verify_amount(df, final):
    require((int(df.order_count.sum()), int(df.issue_orders.sum()), round(df.issue_amount.sum(), 2), len(final))
            == (95195, 14165, 2564540.84, 9), 'Published amount baseline mismatch')


def verify_statistics(rd, rd_ci, rr, rr_ci, adjusted_or, or_low, or_high):
    actual = tuple(round(float(v), 2) for v in
                   [rd*100, rd_ci[0]*100, rd_ci[1]*100, rr, *rr_ci, adjusted_or, or_low, or_high])
    require(actual == (53.11, 51.90, 54.31, 6.74, 6.56, 6.93, 14.78, 13.94, 15.66), 'Published statistics baseline mismatch')
