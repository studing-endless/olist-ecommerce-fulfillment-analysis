"""Boundary and leakage tests; synthetic data only, no credentials or raw IDs."""
import importlib.util
from pathlib import Path
import unittest
import pandas as pd

MODULE = Path(__file__).resolve().parents[1]/"python/08_seller_strategy_comparison.py"
if not MODULE.exists():
    MODULE = Path(__file__).with_name("08_seller_strategy_comparison.py")
spec=importlib.util.spec_from_file_location("seller_comparison",MODULE)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


class TemporalPolicyTests(unittest.TestCase):
    def inputs(self):
        orders=pd.DataFrame([
            ["old","delivered","2018-03-01","2018-03-10","2018-03-15","2018-03-03"],
            ["boundary","delivered","2018-03-20","2018-04-01","2018-03-30","2018-03-22"],
            ["future","delivered","2018-04-02","2018-04-04","2018-04-05","2018-04-03"],
        ],columns=["order_id","order_status","order_purchase_timestamp","order_delivered_customer_date","order_estimated_delivery_date","order_delivered_carrier_date"])
        for col in orders.columns[2:]: orders[col]=pd.to_datetime(orders[col])
        items=pd.DataFrame({"order_id":orders.order_id,"seller_id":["synthetic_seller"]*3,"shipping_limit_date":pd.to_datetime(["2018-03-05","2018-03-25","2018-04-04"]),"price":[10.,10.,10.],"freight_value":[1.,1.,1.]})
        reviews=pd.DataFrame([
            ["old",5,"2018-03-11","2018-03-12"],
            ["old",1,"2018-04-10","2018-04-11"],
            ["boundary",1,"2018-03-25","2018-04-01"],
        ],columns=["order_id","review_score","review_creation_date","review_answer_timestamp"])
        for col in reviews.columns[2:]: reviews[col]=pd.to_datetime(reviews[col])
        return orders,items,reviews

    def test_delivery_at_decision_is_not_history(self):
        history,_,_=m.build_cohort(*self.inputs(),None,m.DECISION,m.DECISION)
        self.assertEqual(history.order_id.tolist(),["old"])

    def test_future_second_review_does_not_exclude_known_single_review(self):
        o,i,r=self.inputs()
        single,audit=m.available_reviews(r,o,m.DECISION)
        self.assertEqual(single.loc["old","review_score"],5)
        self.assertNotIn("boundary",single.index)
        self.assertEqual(audit["available_multi_review_orders"],0)

    def test_future_outcomes_and_future_reviews_do_not_change_history(self):
        o,i,r=self.inputs()
        h1,_,_=m.build_cohort(o,i,r,None,m.DECISION,m.DECISION)
        o.loc[o.order_id=="future","order_estimated_delivery_date"]=pd.Timestamp("2018-04-02")
        r.loc[r.review_answer_timestamp>=m.DECISION,"review_score"]=5
        i.loc[i.order_id=="future","price"]=999999.
        h2,_,_=m.build_cohort(o,i,r,None,m.DECISION,m.DECISION)
        pd.testing.assert_frame_equal(h1,h2)

    def test_issue_is_union_not_sum_and_missing_review_is_unknown(self):
        o,i,r=self.inputs()
        o.loc[o.order_id=="old","order_estimated_delivery_date"]=pd.Timestamp("2018-03-09")
        r.loc[0,"review_score"]=1
        h,_,_=m.build_cohort(o,i,r,None,m.DECISION,m.DECISION)
        self.assertEqual(int(h.is_late.iloc[0]),1)
        self.assertEqual(int(h.is_bad.iloc[0]),1)
        self.assertEqual(int(h.is_issue.iloc[0]),1)
        h,_,_=m.build_cohort(o,i,r.iloc[0:0],None,m.DECISION,m.DECISION)
        self.assertEqual(int(h.is_reviewed.iloc[0]),0)
        self.assertEqual(int(h.is_issue.iloc[0]),1)

    def test_same_budget_and_eligibility_with_history_only(self):
        rows=[]
        for seller in range(12):
            for n in range(100):
                high=seller<6
                late=int(n<(30 if high else 5)); bad=int((10<=n<30) if high else (3<=n<8))
                rows.append({"seller_id":f"synthetic_{seller:02d}","order_id":f"synthetic_order_{seller}_{n}","is_late":late,"is_reviewed":1,"is_bad":bad,"is_issue":int(late or bad)})
        history=pd.DataFrame(rows)
        selected,eligible,audit=m.choose_strategies(history)
        k=audit["investigation_budget_k"]
        self.assertTrue(k>0)
        self.assertEqual({len(v) for v in selected.values()},{k})
        self.assertTrue(all(v<=set(eligible.index) for v in selected.values()))
        history=history.sample(frac=1,random_state=15)
        shuffled,_,_=m.choose_strategies(history)
        self.assertEqual(selected,shuffled)


if __name__=="__main__": unittest.main()
