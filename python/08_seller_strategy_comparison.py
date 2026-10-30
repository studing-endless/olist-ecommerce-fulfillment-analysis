"""Compare four seller investigation policies with an event-time holdout.

Only aggregate outputs are saved. Seller/order identifiers remain in memory.
Snapshot fields have no change log: this is a conditional historical replay,
not a claim of a fully reconstructed production feature store or causal gains.
"""
import argparse
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
import os

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DECISION = pd.Timestamp("2018-04-01")
TEST_END = pd.Timestamp("2018-07-01")
OBSERVATION_END = pd.Timestamp("2018-09-01")
MIN_ORDERS = 100
LABELS = {"A": "A Combination", "B": "B Issue volume", "C": "C Issue rate", "D": "D Order volume"}


def pct(numerator, denominator):
    if not denominator:
        return np.nan
    return float((Decimal(int(numerator)) * 100 / Decimal(int(denominator))).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def read_inputs(raw_dir):
    order_cols = ["order_id", "order_status", "order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date", "order_delivered_carrier_date"]
    o = pd.read_csv(raw_dir / "olist_orders_dataset.csv", usecols=order_cols)
    for name in order_cols[2:]:
        o[name] = pd.to_datetime(o[name], errors="coerce")
    i = pd.read_csv(raw_dir / "olist_order_items_dataset.csv", usecols=["order_id", "seller_id", "shipping_limit_date", "price", "freight_value"])
    i["shipping_limit_date"] = pd.to_datetime(i.shipping_limit_date, errors="coerce")
    r = pd.read_csv(raw_dir / "olist_order_reviews_dataset.csv", usecols=["order_id", "review_score", "review_creation_date", "review_answer_timestamp"])
    for name in ["review_creation_date", "review_answer_timestamp"]:
        r[name] = pd.to_datetime(r[name], errors="coerce")
    assert o.order_id.is_unique and o.order_id.notna().all()
    assert r.review_score.dropna().between(1, 5).all()
    assert i[["price", "freight_value"]].notna().all().all()
    return o, i, r


def item_orders(items, order_ids):
    # Filter order membership before aggregation, never use future order counts.
    data = items[items.order_id.isin(order_ids)].copy()
    data["amount_cents"] = (data.price * 100).round().astype("int64") + (data.freight_value * 100).round().astype("int64")
    result = data.groupby("order_id").agg(seller_count=("seller_id", "nunique"), seller_id=("seller_id", "min"), amount_cents=("amount_cents", "sum"), deadline=("shipping_limit_date", "min"), deadline_count=("shipping_limit_date", "nunique"), missing_deadline=("shipping_limit_date", lambda x: x.isna().sum()))
    return result[result.seller_count == 1].reset_index()


def available_reviews(reviews, orders, end):
    """One scored review among records observable by end; no future dedup rule."""
    rr = reviews.merge(orders[["order_id", "order_purchase_timestamp"]], on="order_id", validate="many_to_one")
    valid_clock = (rr.review_creation_date.notna() & rr.review_answer_timestamp.notna()
                   & (rr.review_answer_timestamp >= rr.review_creation_date)
                   & (rr.review_answer_timestamp >= rr.order_purchase_timestamp)
                   & (rr.review_creation_date >= rr.order_purchase_timestamp.dt.normalize()))
    available = rr[valid_clock & (rr.review_creation_date < end) & (rr.review_answer_timestamp < end)]
    summary = available.groupby("order_id").agg(review_count=("review_score", "size"), valid_scores=("review_score", "count"), review_score=("review_score", "max"))
    single = summary[(summary.review_count == 1) & (summary.valid_scores == 1)][["review_score"]]
    audit = {
        "review_rows_for_purchased_cohort": len(rr),
        "review_invalid_or_missing_clock_rows": int((~valid_clock).sum()),
        "review_rows_not_yet_available": int((valid_clock & ((rr.review_creation_date >= end) | (rr.review_answer_timestamp >= end))).sum()),
        "available_review_rows": len(available),
        "available_multi_review_orders": int((summary.review_count > 1).sum()),
    }
    return single, audit


def build_cohort(orders, items, reviews, start, purchase_end, outcome_end):
    purchased = orders[(orders.order_purchase_timestamp < purchase_end) & orders.order_purchase_timestamp.notna()].copy()
    if start is not None:
        purchased = purchased[purchased.order_purchase_timestamp >= start]
    single = item_orders(items, purchased.order_id)
    purchase_single = purchased.merge(single, on="order_id", validate="one_to_one")
    review, review_audit = available_reviews(reviews, purchased, outcome_end)
    valid_time = (purchase_single.order_delivered_customer_date.notna()
                  & purchase_single.order_estimated_delivery_date.notna()
                  & (purchase_single.order_delivered_customer_date >= purchase_single.order_purchase_timestamp))
    ready = purchase_single[valid_time & (purchase_single.order_status == "delivered") & (purchase_single.order_delivered_customer_date < outcome_end)].copy()
    ready = ready.merge(review, on="order_id", how="left", validate="one_to_one")
    ready["is_late"] = (ready.order_delivered_customer_date.dt.normalize() > ready.order_estimated_delivery_date.dt.normalize()).astype(int)
    ready["is_reviewed"] = ready.review_score.notna().astype(int)
    ready["is_bad"] = (ready.review_score <= 2).astype(int)
    ready["is_issue"] = ((ready.is_late == 1) | (ready.is_bad == 1)).astype(int)
    ready["issue_amount_cents"] = ready.is_issue * ready.amount_cents
    ready["valid_handoff"] = (ready.order_delivered_carrier_date.notna()
        & (ready.order_delivered_carrier_date >= ready.order_purchase_timestamp)
        & (ready.order_delivered_carrier_date <= ready.order_delivered_customer_date)
        & (ready.deadline_count == 1) & (ready.missing_deadline == 0)).astype(int)
    ready["late_handoff"] = ((ready.valid_handoff == 1) & (ready.order_delivered_carrier_date > ready.deadline)).astype(int)
    ready["handoff_valid_late_delivery"] = ready.valid_handoff * ready.is_late
    ready["ontime_handoff_late_delivery"] = ((ready.valid_handoff == 1) & (ready.late_handoff == 0) & (ready.is_late == 1)).astype(int)
    ready["ontime_bad"] = (1-ready.is_late) * ready.is_bad
    audit = {
        "purchased_orders_all_statuses": len(purchased),
        "single_seller_purchased_orders_all_statuses": len(purchase_single),
        "single_seller_valid_delivered_observed": len(ready),
        "single_seller_not_in_observed_delivered_denominator": len(purchase_single)-len(ready),
        "single_seller_delivered_after_observation_end": int((valid_time & (purchase_single.order_status == "delivered") & (purchase_single.order_delivered_customer_date >= outcome_end)).sum()),
        "single_seller_final_status_not_delivered": int((purchase_single.order_status != "delivered").sum()),
        "delivered_event_before_end_but_final_status_not_delivered": int((valid_time & (purchase_single.order_delivered_customer_date < outcome_end) & (purchase_single.order_status != "delivered")).sum()),
        "ready_single_review_orders": int(ready.is_reviewed.sum()),
        "ready_without_single_available_review": int((ready.is_reviewed == 0).sum()),
        "ready_late_orders": int(ready.is_late.sum()),
        "ready_observed_issue_orders": int(ready.is_issue.sum()),
        "ready_sellers": int(ready.seller_id.nunique()),
        **review_audit,
    }
    return ready, purchase_single, audit


def profile_orders(orders):
    p = orders.groupby("seller_id").agg(order_count=("order_id", "size"), late_orders=("is_late", "sum"), reviewed_orders=("is_reviewed", "sum"), bad_orders=("is_bad", "sum"), issue_orders=("is_issue", "sum"))
    p["late_rate_pct"] = [pct(n,d) for n,d in zip(p.late_orders,p.order_count)]
    p["bad_rate_pct"] = [pct(n,d) for n,d in zip(p.bad_orders,p.reviewed_orders)]
    # Preserve the original main shortlist's two-decimal pandas issue-rate rank.
    p["issue_rate_pct"] = (100*p.issue_orders/p.order_count).round(2)
    return p


def rank(profile, key):
    keys = [key] + (["issue_orders"] if key == "issue_rate_pct" else [])
    return profile.reset_index().sort_values(keys + ["seller_id"], ascending=[False]*len(keys)+[True], kind="mergesort").seller_id.tolist()


def choose_strategies(history):
    """No follow-up argument: every eligibility, threshold and tie uses history."""
    p = profile_orders(history)
    thresholds = {"late_rate_pct": pct(p.late_orders.sum(), p.order_count.sum()),
                  "bad_rate_pct": pct(p.bad_orders.sum(), p.reviewed_orders.sum())}
    eligible = p[(p.order_count >= MIN_ORDERS) & (p.reviewed_orders > 0)].copy()
    dual = eligible[(eligible.late_rate_pct > thresholds["late_rate_pct"]) & (eligible.bad_rate_pct > thresholds["bad_rate_pct"])]
    a = set(rank(dual, "issue_orders")[:5]) | set(rank(dual, "issue_rate_pct")[:5])
    k = len(a)
    if k == 0 or len(eligible) < k:
        raise ValueError("Insufficient historical candidates at the fixed 100-order threshold; do not tune using future results.")
    selected = {"A": a, "B": set(rank(eligible, "issue_orders")[:k]), "C": set(rank(eligible, "issue_rate_pct")[:k]), "D": set(rank(eligible, "order_count")[:k])}
    assert all(len(ids) == k and ids <= set(eligible.index) for ids in selected.values())
    audit = {"minimum_historical_orders": MIN_ORDERS, "historical_profile_sellers": len(p), "historical_eligible_sellers": len(eligible), "historical_dual_high_sellers": len(dual), "investigation_budget_k": k, "historical_late_baseline_pct": thresholds["late_rate_pct"], "historical_bad_review_baseline_pct": thresholds["bad_rate_pct"], "historical_eligible_orders": int(eligible.order_count.sum()), "historical_eligible_order_share_pct": pct(eligible.order_count.sum(), len(history)), "historical_eligible_reviewed_orders": int(eligible.reviewed_orders.sum())}
    return selected, eligible, audit


def compare(orders, items, reviews):
    history, _, hist_audit = build_cohort(orders, items, reviews, None, DECISION, DECISION)
    selections, eligible, policy_audit = choose_strategies(history)
    # Lists are frozen before any follow-up cohort is constructed.
    frozen = {k: frozenset(v) for k,v in selections.items()}
    future, future_purchased, test_audit = build_cohort(orders, items, reviews, DECISION, TEST_END, OBSERVATION_END)
    assert not set(history.order_id) & set(future.order_id)
    assert (history.order_purchase_timestamp < DECISION).all()
    assert (history.order_delivered_customer_date < DECISION).all()
    evaluation = future[future.seller_id.isin(eligible.index)]
    evaluation_purchased = future_purchased[future_purchased.seller_id.isin(eligible.index)]
    assert len(evaluation) and evaluation.is_issue.sum() > 0
    rows=[]
    for strategy, ids in frozen.items():
        f = evaluation[evaluation.seller_id.isin(ids)]
        h = history[history.seller_id.isin(ids)]
        purchase = evaluation_purchased[evaluation_purchased.seller_id.isin(ids)]
        rows.append({
            "strategy": strategy, "strategy_name": LABELS[strategy], "budget_k": len(ids),
            "eligible_sellers": len(eligible), "historical_selected_orders": len(h),
            "historical_selected_order_share_of_eligible_pct": pct(len(h),eligible.order_count.sum()),
            "historical_selected_order_share_of_all_history_pct": pct(len(h),len(history)),
            "historical_selected_issue_orders": int(h.is_issue.sum()), "historical_selected_issue_rate_pct": pct(h.is_issue.sum(),len(h)),
            "followup_active_sellers_any_order": int(purchase.seller_id.nunique()),
            "followup_active_sellers_valid_delivered": int(f.seller_id.nunique()),
            "followup_selected_purchased_orders": len(purchase), "followup_covered_orders": len(f),
            "followup_covered_late_orders": int(f.is_late.sum()), "followup_covered_issue_orders": int(f.is_issue.sum()),
            "followup_covered_issue_amount_brl": int(f.issue_amount_cents.sum())/100,
            "followup_order_coverage_pct": pct(len(f),len(evaluation)),
            "followup_late_coverage_pct": pct(f.is_late.sum(),evaluation.is_late.sum()),
            "followup_issue_coverage_pct": pct(f.is_issue.sum(),evaluation.is_issue.sum()),
            "followup_issue_amount_coverage_pct": pct(f.issue_amount_cents.sum(),evaluation.issue_amount_cents.sum()),
            "followup_late_rate_pct": pct(f.is_late.sum(),len(f)),
            "followup_issue_rate_pct": pct(f.is_issue.sum(),len(f)),
            "followup_reviewed_orders": int(f.is_reviewed.sum()), "followup_bad_review_orders": int(f.is_bad.sum()),
            "followup_bad_review_rate_pct": pct(f.is_bad.sum(),f.is_reviewed.sum()),
            "followup_ontime_bad_orders": int(f.ontime_bad.sum()),
            "followup_valid_handoff_orders": int(f.valid_handoff.sum()),
            "followup_late_handoff_orders": int(f.late_handoff.sum()),
            "followup_late_handoff_rate_pct": pct(f.late_handoff.sum(),f.valid_handoff.sum()),
            "followup_handoff_valid_late_delivery_orders": int(f.handoff_valid_late_delivery.sum()),
            "followup_ontime_handoff_late_delivery_orders": int(f.ontime_handoff_late_delivery.sum()),
            "followup_ontime_handoff_share_of_late_pct": pct(f.ontime_handoff_late_delivery.sum(),f.handoff_valid_late_delivery.sum()),
            "comparable_followup_orders": len(evaluation), "comparable_followup_late_orders": int(evaluation.is_late.sum()),
            "comparable_followup_issue_orders": int(evaluation.is_issue.sum()),
            "comparable_followup_issue_amount_brl": int(evaluation.issue_amount_cents.sum())/100,
            "followup_issue_coverage_all_sellers_pct": pct(f.is_issue.sum(),future.is_issue.sum()),
        })
    overlaps=[]
    for left in frozen:
        for right in frozen:
            intersection=len(frozen[left] & frozen[right]); union=len(frozen[left] | frozen[right])
            overlaps.append({"strategy_left":left,"strategy_right":right,"intersection_sellers":intersection,"union_sellers":union,"jaccard_pct":pct(intersection,union)})
    audit = {"decision_time_exclusive":"2018-04-01", "followup_purchase_end_exclusive":"2018-07-01", "followup_outcome_end_exclusive":"2018-09-01", **{"history_"+k:v for k,v in hist_audit.items()}, **{"followup_"+k:v for k,v in test_audit.items()}, **policy_audit,
             "comparable_followup_sellers": int(evaluation.seller_id.nunique()),
             "eligible_sellers_without_valid_followup_orders": int(len(eligible)-evaluation.seller_id.nunique()),
             "comparable_followup_purchased_orders_all_statuses": len(evaluation_purchased),
             "comparable_followup_valid_orders":len(evaluation),
             "comparable_followup_excluded_unobserved_or_invalid_orders":len(evaluation_purchased)-len(evaluation),
             "comparable_followup_review_coverage_pct":pct(evaluation.is_reviewed.sum(),len(evaluation)),
             "comparable_followup_valid_order_share_pct":pct(len(evaluation),len(future)),
             "future_outcome_timestamps_used_in_selection":False,
             "validation_classification":"event_time_constrained_retrospective_holdout",
             "fully_point_in_time_snapshot_guaranteed":False,
             "snapshot_revision_history_available":False}
    return pd.DataFrame(rows), pd.DataFrame(overlaps), audit


def plot_comparison(results, destination):
    fig, axes = plt.subplots(1,2,figsize=(12,5.5))
    x=np.arange(len(results)); width=.24
    for offset,col,label,color in [(-width,"followup_order_coverage_pct","Order coverage","#8599ab"),(0,"followup_late_coverage_pct","Late-order coverage","#d28a44"),(width,"followup_issue_coverage_pct","Issue-order coverage","#2878a5")]:
        bars=axes[0].bar(x+offset,results[col],width,label=label,color=color)
        for b,n in zip(bars,results[col]): axes[0].text(b.get_x()+b.get_width()/2,b.get_height()+.5,f"{n:.1f}",ha="center",fontsize=8)
    axes[0].set_xticks(x); axes[0].set_xticklabels(results.strategy)
    axes[0].set_ylabel("Coverage within each comparable outcome (%)")
    axes[0].set_ylim(0,max(results[["followup_order_coverage_pct","followup_late_coverage_pct","followup_issue_coverage_pct"]].max())*1.3)
    axes[0].legend(fontsize=8,loc="upper left")
    bars=axes[1].bar(x,results.followup_issue_rate_pct,color="#2878a5")
    for b,row in zip(bars,results.itertuples()): axes[1].text(b.get_x()+b.get_width()/2,b.get_height()+.5,f"{row.followup_issue_rate_pct:.2f}%\n{row.followup_covered_issue_orders:,}/{row.followup_covered_orders:,}",ha="center",fontsize=8)
    axes[1].set_xticks(x); axes[1].set_xticklabels(results.strategy)
    axes[1].set_ylabel("Observed issue rate within covered orders (%)")
    axes[1].set_ylim(0,max(results.followup_issue_rate_pct)*1.35)
    r=results.iloc[0]
    fig.suptitle(f"Historical Seller Strategy Replay | Equal Investigation Budget K={int(r.budget_k)}")
    fig.text(.5,.065,f"Decision: 2018-04-01; purchases: Apr-Jun 2018; outcomes observed before 2018-09-01\nComparable: {int(r.comparable_followup_orders):,} valid orders; {int(r.comparable_followup_late_orders):,} late; {int(r.comparable_followup_issue_orders):,} observed issues. Single-seller orders only.",ha="center",fontsize=9)
    fig.text(.5,.012,"A combination | B historical issue count | C historical issue rate | D historical order count. Coverage is not treatment benefit.",ha="center",fontsize=8)
    fig.tight_layout(rect=[0,.15,1,.94]); destination.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(destination,dpi=200,bbox_inches="tight"); plt.close(fig)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir",type=Path,default=Path(os.environ.get("OLIST_RAW_DIR",str(ROOT/"data/raw"))))
    parser.add_argument("--output-dir",type=Path,default=ROOT/"outputs")
    parser.add_argument("--figure",type=Path,default=ROOT/"figures/seller_strategy_comparison.png")
    args=parser.parse_args()
    results,overlap,audit=compare(*read_inputs(args.raw_dir))
    args.output_dir.mkdir(parents=True,exist_ok=True)
    results.to_csv(args.output_dir/"seller_strategy_comparison.csv",index=False)
    overlap.to_csv(args.output_dir/"seller_strategy_overlap.csv",index=False)
    pd.DataFrame([{"metric":k,"value":v} for k,v in audit.items()]).to_csv(args.output_dir/"seller_strategy_audit.csv",index=False)
    plot_comparison(results,args.figure)
    print(results[["strategy","budget_k","followup_covered_orders","followup_covered_late_orders","followup_covered_issue_orders","followup_issue_coverage_pct","followup_issue_rate_pct","followup_covered_issue_amount_brl"]].to_string(index=False))
    print("\nSample and availability audit:")
    for key,value in audit.items(): print(f"{key}: {value}")


if __name__ == "__main__":
    main()
