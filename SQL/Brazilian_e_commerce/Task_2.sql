-- Задача: Чи впливає відстань на час доставки?


with coordinates as -- СТЕ для приблизних координат по зіп коду
(

	select
		geolocation_zip_code_prefix		as geo_zip_code_prefix
		,avg(geolocation_lat)			as geo_lat
		,avg(geolocation_lng)			as geo_lng
	from geolocation
	group by 1

), single_seller_orders as -- СТЕ із замовленнями, де є лише 1 продавець, для подальшої фільтрації
(

	select order_id
	from order_items
	group by order_id
	having count(distinct seller_id) = 1 -- фільтр після групування - всього один продавець

), delivered_orders as -- Формуємо набір завершених замовлень для аналізу доставки. Залишаємо лише замовлення з одним продавцем, щоб уникнути складних маршрутів
(

	select distinct
		oi.order_id
		,o.customer_id
		,oi.seller_id
		,o.order_delivered_customer_date - o.order_delivered_carrier_date as delivery_time -- Розрахунок часу доставки. o.order_delivered_customer_date - час коли доставили замовлення. o.order_delivered_carrier_date - час передачі замовлення перевізнику
	from orders o
	  join order_items oi on o.order_id = oi.order_id
	  join single_seller_orders sso on sso.order_id = o.order_id -- за допомогою Join фільтруємо дані - залишаємо лише замовлення з одним продавцем
	where order_status = 'delivered'
	  and o.order_delivered_customer_date > o.order_delivered_carrier_date -- Прибираємо аномальні кейси, коли передача замовлення перевізнику відбулася вже після доставки
	  and o.order_delivered_carrier_date is not null -- видаляємо записи з NULL
	  and o.order_delivered_customer_date is not null -- видаляємо записи з NULL
	order by delivery_time

), routes as -- З'єднуємо дані з таблицями customers та sellers, щоб дістати їх зіп код для подальших розрахунків
(

	select
		d.order_id
		,d.customer_id
		,d.seller_id
		,c.customer_zip_code_prefix 
		,s.seller_zip_code_prefix
		,ROUND(EXTRACT(EPOCH FROM d.delivery_time) / 86400, 2) as delivery_days -- Додатково перерахував час у дні для подальшого імпорту в Рower BI
	from delivered_orders d
	  join customers c on c.customer_id = d.customer_id
	  join sellers s on s.seller_id = d.seller_id
	
), routes_with_coordinates as -- Дістаємо широту і довготу для продавців та клієнтів з раніше створеного СТЕ coordinates
(

	select
		r.order_id
		,r.delivery_days
		,cst.geo_lng		as cust_lng
		,cst.geo_lat		as cust_lat
		,sel.geo_lng		as sel_lng
		,sel.geo_lat		as sel_lat
	from routes r
	  join coordinates cst on cst.geo_zip_code_prefix = r.customer_zip_code_prefix -- окремо робимо з'єднання для клієнтів
	  join coordinates sel on sel.geo_zip_code_prefix = r.seller_zip_code_prefix -- окремо робимо з'єднання для продавців

)
select
	delivery_days
	,ROUND(                 -- Розрахунок відстані в кілометрах за допомогою довготи та широти. 
    6371 * 2 * ASIN(
			        SQRT(
				            POWER(SIN(RADIANS(cust_lat - sel_lat) / 2), 2) +
				            COS(RADIANS(sel_lat)) *
				            COS(RADIANS(cust_lat)) *
				            POWER(SIN(RADIANS(cust_lng - sel_lng) / 2), 2)
						)
					)::numeric, 2
			) as distance_km
from routes_with_coordinates
