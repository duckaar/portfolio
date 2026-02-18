/*
 7) “Крос-категорійні” продукти у кошику (топ 20)
	Cross-category selling products (Top 20)

 	Key techniques:
		- CTE
		- DISTINCT
		- Self-join
		- Pair deduplication (category_a < category_b)
		- GROUP BY
		- Aggregations (COUNT DISTINCT)
*/
with cte as(
	select distinct p.product_category_name
		, o.order_id
	from order_items oi 
	  join orders o on o.order_id = oi.order_id
	  join products p on oi.product_id = p.product_id
	where o.order_status = 'delivered'
)
select c1.product_category_name		as category_a
	, c2.product_category_name 		as category_b
	, count(distinct c1.order_id) 	as cross_cnt
from cte c1
  join cte c2 on c1.order_id = c2.order_id 
	and c1.product_category_name < c2.product_category_name
group by 1,2
order by cross_cnt desc
limit 20;

/*
 8) Нові vs повторні клієнти по місяцях
	New vs returning customers by month

 	Key techniques:
		- CTE
		- DATE_TRUNC
		- GROUP BY
		- CASE
		- Derived metric (returning_rate)
		- NULLIF
		- Numeric casting
		- ROUND
 */
with first_order as (
	select c.customer_unique_id
		, date_trunc('month', min(o.order_purchase_timestamp))::date as first_order_month
	from orders o
	  join customers c on o.customer_id = c.customer_id
	where o.order_status = 'delivered'
	group by 1
), 
customer_orders as (
	select c.customer_unique_id
		, date_trunc('month', o.order_purchase_timestamp)::date as order_month
	from orders o
	  join customers c on o.customer_id = c.customer_id
	where o.order_status = 'delivered'
	group by 1, 2
)
select co.order_month 
	, count(*) as total_customers_cnt
	, sum(case when co.order_month = fo.first_order_month then 1 else 0 end)					as new_customers_cnt
	, sum(case when co.order_month > fo.first_order_month then 1 else 0 end)					as returning_customers_cnt
	, round(
			sum(case when co.order_month > fo.first_order_month then 1 else 0 end)::numeric 
			/ nullif(count(*), 0), 
			4
		)																						as returning_rate
from customer_orders co
  join first_order fo on co.customer_unique_id = fo.customer_unique_id 
group by co.order_month
order by co.order_month;

/*
 9) Категорії з високою концентрацією (top-3 products share > 0.6)
	High concentration categories (top-3 share > 0.6)

 	Key techniques:
		- CTE
		- Window function (RANK)
		- PARTITION BY
		- Aggregations (SUM)
		- Conditional aggregation (FILTER)
		- HAVING
		- Derived metric (top_3_share)
		- NULLIF
		- Numeric casting
		- ROUND
 */
with ranked as(
	select p.product_category_name 
		, p.product_id
		, sum(oi.price) as revenue
		, rank() over (partition by p.product_category_name order by sum(oi.price) desc) as product_rank
	from order_items oi 
	  join orders o on o.order_id = oi.order_id
	  join products p on oi.product_id = p.product_id
	where o.order_status = 'delivered'
	group by p.product_category_name, p.product_id
)
select product_category_name
	, sum(revenue) as revenue
	, round(
			sum(revenue) filter (where product_rank <=3)::numeric 
			/ nullif(sum(revenue), 0), 
			2
		) as top_3_share
from ranked
group by product_category_name
having sum(revenue) filter (where product_rank <=3)::numeric / nullif(sum(revenue), 0) > 0.6
order by top_3_share desc;
