-- Задача розрахунок RFM-метрик (Recency, Frequency, Monetary)
CREATE OR REPLACE view rfm_segmentation as -- створюємо View для легшного імпорту в Power BI
with rfm as 
(

	select 
		customer_unique_id
		,current_date - max(order_purchase_timestamp)::date as recency -- розрахунок скільки днів пройшло з останньої покупки
		,count(distinct order_id) as frequency -- кількість покупок
		,sum(payment_value) as monetary -- витрачено
	from orders
	  join order_payments using(order_id) -- під'єднуємось до таблиць задля отримання додаткових потрібних колонок (customer_unique_id, payment_value)
	  join customers using(customer_id)
	group by customer_unique_id
	
), rfm_ranked as 
(

	select
		*
		,row_number() over (order by recency) 			as r_rank                -- ранжуємо кожні з метрик
		,dense_rank() over (order by frequency DESC) 	as f_rank
		,row_number() over (order by monetary DESC) 	as m_rank
	from rfm

), rfm_scores as 
(

	select
		*
		,ntile(10) over (order by r_rank desc) as r_score         -- за допомогою віконної функції ділимо дані на 10 частим, цим самим надаємо оцінку метрикам
		,ntile(10) over (order by f_rank desc) as f_score
		,ntile(10) over (order by m_rank desc) as m_score
	from rfm_ranked
	
), rfm_total as
(

	select
		customer_unique_id
		,recency
		,frequency
		,monetary
		,r_score
		,f_score
		,m_score
		,r_score + m_score + f_score as rfm_total_score
	from rfm_scores
	order by rfm_total_score desc
	
)
select
	customer_unique_id
	,recency
	,frequency
	,monetary
	,r_score
	,f_score
	,m_score
	,rfm_total_score
	,case                -- надаємо статус сгідно загальної оцінки "rfm_total_score"
		when rfm_total_score >= 24 then 'Champions' -- 24-30
		when rfm_total_score >= 20 then 'Loyal VIPs' -- 20-24
		when rfm_total_score >= 16 then 'Potential Loyalists' -- 16-20
		when rfm_total_score >= 12 then 'Promising' -- 12-16
		when rfm_total_score >= 8 then 'Requires Attention' -- 8-12
		when rfm_total_score >= 4 then 'At Risk' -- 4-8
		else 'Lost_Inactive' -- інші
	end as rfm_segment
from rfm_total

