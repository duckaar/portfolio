/*
 1) Основні бізнес метрики по доставленим замовленням
	Main business KPIs based on delivered orders

 	Key techniques:
		- JOIN
		- Aggregations (SUM, COUNT DISTINCT)
		- Derived metrics (ratios)
		- NULLIF for safe division
		- Numeric casting
		- ROUND
 */
select sum(oi.price) as total_revenue
	, count(distinct o.order_id)						as orders_cnt
	, sum(oi.freight_value)								as total_freight
	, round(
			sum(oi.freight_value)::numeric 
			/ NULLIF(sum(oi.price), 0), 
			2
		)												as freight_share
	, round(
			sum(oi.price)::numeric 
			/ NULLIF(count(distinct o.order_id), 0),
			2
		)												as AOV
	, round(
			count(*)::numeric 
			/ NULLIF(count(distinct o.order_id), 0), 
			2
		)												as avg_items_per_order
from order_items oi
  join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered';

/*
 2) Розподіл замовлень за статусами
	Orders status distribution

 	Key techniques:
		- GROUP BY
		- Aggregations (COUNT)
		- Window aggregation (SUM(...) OVER())
		- Share calculation
		- Numeric casting
 */
select order_status
	, count(*)									as orders_cnt
	, count(*)::numeric 
	/ sum(count(*)) over()						as orders_share
from orders 
group by order_status
order by orders_cnt desc;

/*
 3) Виручка, кількість замовлень та AOV по місяцях
	Revenue, orders count, AOV by month

 	Key techniques:
		- DATE_TRUNC
		- GROUP BY
		- COUNT DISTINCT
		- Derived metric (AOV)
		- NULLIF
		- Numeric casting
 */
select date_trunc('month' ,o.order_purchase_timestamp)::date					as month
	, count(distinct o.order_id)												as order_count
	, sum(oi.price)																as revenue
	, round(
			sum(oi.price)::numeric 
			/ nullif(count(distinct o.order_id), 0), 
			2
		)																		as monthly_aov
from order_items oi 
  join orders o on o.order_id = oi.order_id 
where o.order_status = 'delivered'
group by month
order by month;

/*
 4) Month-over-Month зміна виручки
 	Month-over-Month revenue change

 	Key techniques:
		- CTE
		- Window function (LAG)
		- Ratio calculation
		- NULLIF
		- Numeric & date casting
		- GROUP BY
 */
with monthly_revenue as (  -- Рахуємо revenuе by month в cte для подальшого використання
	select date_trunc('month' ,o.order_purchase_timestamp)	as month
		, sum(oi.price)										as revenue
	from order_items oi 
	  join orders o on o.order_id = oi.order_id 
	where o.order_status = 'delivered'
	group by month
)
select month::date
	, revenue
	, lag(revenue, 1, null) over (order by month)								as previous_month_revenue
	, round(
			(revenue - lag(revenue, 1, 0) over (order by month))::numeric	-- віднімаємо від revenue поточного місяця revenue минулого
			/ nullif(lag(revenue, 1, 0) over (order by month), 0), 			-- рахуємо MoM по формулі (revenue - previous_month_revenue) / previous_month_revenue
			4
		)																		as mom
from monthly_revenue
order by month;

/*
 5) Кумулятивна виручка
	Running revenue

 	Key techniques:
		- CTE
		- Window function (SUM(...) OVER)
		- Window frame definition
		- DATE_TRUNC
		- GROUP BY
		- Aggregations (SUM)
		- Date casting
 */
with monthly_revenue as		-- дістаємо revenue by month
	(select DATE_TRUNC('month' ,o.order_purchase_timestamp)::date	as month
		, sum(oi.price)												as revenue
	from order_items oi 
	  join orders o on o.order_id = oi.order_id 
	where o.order_status = 'delivered'
	group by month)
select month
	, revenue
	, sum(revenue) over (order by month rows between unbounded preceding and current row)	as running_revenue  -- рахуємо кумулятивну сумму revenue по month
from monthly_revenue
order by month;

/*
 6) Топ категорій + накопичувальна частка (Pareto) 
	Top categories + cumulative share (Pareto) 

 	Key techniques:
		- CTE
		- Window function (SUM(...) OVER)
		- Window frame definition
		- Numeric casting & rounding
		- GROUP BY
		- NULLIF
 */
with category_info as ( 	-- дістаємо revenue та revenue_share груповане по product_category_name
	select p.product_category_name 
		, sum(oi.price)							as revenue
		, sum(oi.price)::numeric 
		/ nullif(sum(sum(oi.price)) over(), 0)	as revenue_share
	from order_items oi 
	  join products p on oi.product_id = p.product_id
	  join orders o on o.order_id = oi.order_id
	where o.order_status = 'delivered'
	group by p.product_category_name
)
select product_category_name
	, revenue 
	, revenue_share::numeric(10,4) 
	, sum(revenue_share) over(order by revenue desc rows between unbounded preceding and current row)::numeric(10,4)	as cumulative_share  -- рахуємо кумулятивну суму revenue_share по revenue
from category_info
order by revenue desc;	