"""Regenerate three charts from reviewed public aggregates; no database needed."""
from project_paths import ROOT, FIGURES
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
R = ROOT
state=pd.read_csv(R/'outputs/02_state_delivery_summary.csv').nlargest(10,'total_orders').sort_values('late_rate_pct')
fig,ax=plt.subplots(figsize=(9,5))
ax.barh(state.state,state.late_rate_pct,color='#2878a5')
for idx,row in enumerate(state.itertuples()): ax.text(row.late_rate_pct+.15,idx,f'{row.late_rate_pct:.2f}% (n={row.total_orders:,})',va='center',fontsize=8)
ax.set_xlim(0,max(state.late_rate_pct)*1.5)
ax.set_title('Late Delivery by State (10 largest states; base n=96,470)')
ax.set_xlabel('Late delivery rate (%)'); ax.set_ylabel('Customer state')
fig.tight_layout(); fig.savefig(FIGURES/'state_delivery.png',dpi=180); plt.close(fig)
fig,ax=plt.subplots(figsize=(9,5))
h=pd.read_csv(ROOT/'outputs/handoff_summary.csv').iloc[0]
values=[int(h.late_handoff_late_delivery),int(h.ontime_handoff_late_delivery)]
late_total=int(h.late_delivery_orders)
bars=ax.bar(['Late handoff','On-time handoff'],values,color=['#d2804b','#2878a5'])
for bar,n in zip(bars,values): ax.text(bar.get_x()+bar.get_width()/2,n+60,f'{n:,} ({n/late_total:.2%})',ha='center')
ax.set_title(f'Handoff Timing Among Late Deliveries (n={late_total:,})')
ax.set_ylabel('Late delivery orders'); ax.set_ylim(0,5400)
fig.text(.5,.01,'Single-seller valid handoff sample: 95,029 orders; timing alone does not establish responsibility.',ha='center',fontsize=8)
fig.tight_layout(rect=[0,.04,1,1]); fig.savefig(FIGURES/'handoff_diagnosis.png',dpi=180); plt.close(fig)

st=pd.read_csv(ROOT/'outputs/regional_stage_summary.csv').set_index(['period','customer_state'])
fig,axes=plt.subplots(1,2,figsize=(11,5),sharey=True)
labels=['Sep-Oct 2017','Nov 2017-Mar 2018','Apr-Jun 2018']
for ax,state in zip(axes,['RJ','SP']):
    data=st.xs(state,level='customer_state')
    x=np.arange(3)
    ax.bar(x,data.avg_pre_carrier_days,label='Purchase to carrier',color='#d2804b')
    ax.bar(x,data.avg_transit_days,bottom=data.avg_pre_carrier_days,label='Carrier to customer',color='#2878a5')
    ax.set_title(f'{state}: valid stage timestamps')
    ax.set_xticks(x); ax.set_xticklabels(labels,rotation=15,ha='right',fontsize=8)
    for idx,row in enumerate(data.itertuples()): ax.text(idx,row.avg_pre_carrier_days+row.avg_transit_days+.3,f'n={row.order_count:,}',ha='center',fontsize=8)
axes[0].set_ylabel('Mean duration (days)'); axes[0].legend(fontsize=8)
fig.suptitle('Regional Delivery Stages by Purchase Period')
fig.tight_layout(); fig.savefig(FIGURES/'regional_stages.png',dpi=180); plt.close(fig)
