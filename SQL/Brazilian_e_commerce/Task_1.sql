--Задача: Аналіз часу підтвердження замовлення по штатам. Пошук аномалій.

--Середній час підтвердження замовлення по штатам
select
	customer_state
	,DATE_TRUNC('second', AVG(order_approved_at - order_purchase_timestamp)) as avg_purchase_to_approve_time -- Розрахунок середньго часу підтвердження замовлення для кожного штату + відкидання секунд для кращої читабельності 
	,count(*) as orders_cnt -- Розрахунок кількості замовлень для кожного штату
from orders o
  join customers using (customer_id) -- Join до таблиці customers для групування дани по штатам
group by customer_state
order by avg_purchase_to_approve_time desc
-- Висновок: в штаті RR час прийняття замовлення набагато більший в середньому ніж в інших штатах. Можна пояснити малою кількістю замовлень

-- Середній час підтвердження замовлення по штатам (НЕ 'delivered')
select
	customer_state
	,DATE_TRUNC('second', AVG(order_approved_at - order_purchase_timestamp)) as avg_purchase_to_approve_time
	,count(*) as orders_cnt
from orders o
  join customers using (customer_id)
where order_status != 'delivered'
group by customer_state
order by avg_purchase_to_approve_time desc
-- Висновок: декілька незакінченних замовлень зі штату RR мають дуже великий час підтвердження

-- Середній час підтвердження замовлень штату 'RR'
select
	customer_state
	,DATE_TRUNC('second', order_approved_at - order_purchase_timestamp) as avg_purchase_to_approve_time
from orders
  join customers using (customer_id)
where customer_state = 'RR' 
  and order_status != 'delivered'
order by 2 desc

-- Висновок: є замовлення, яке більше місяця перебувало в процессі підтвердження. 
-- Можливі причини: тех. помилка системи, немає товару, немає підтвердження продавця. 
-- Мала кількість замовлень зі штату 'RR' сильно вплинула на середній час підтвердження.

-- (Запит для Power BI) Середній час підтвердження для всіх та для 10 надовших кейсів по штатам (1000+ замовлень).
with filtered_approve_time as 
(

	select
		customer_state
		,DATE_TRUNC('second', order_approved_at - order_purchase_timestamp) as purchase_to_approve_time
		,rank() over (partition by customer_state order by DATE_TRUNC('second', order_approved_at - order_purchase_timestamp) desc) as approve_rank -- Пошук rank для часу підтвердження задля виділення Топ-10 найгірших кейсів
	from orders
	  join customers using (customer_id)
	where order_approved_at is not null          -- Фільрування можливих null значень для точнішого аналізу
	  and order_purchase_timestamp is not null
	  and order_status = 'delivered'
		
), order_count as -- СТЕ для рахування кількості замовлень
(

	select customer_state
		  ,count(*) as order_cnt
	from orders
	  join customers using (customer_id)
	where order_approved_at is not null
	  and order_purchase_timestamp is not null
	  and order_status = 'delivered'
	group by customer_state
	
)
select
	customer_state
	,order_cnt
	,ROUND(EXTRACT(EPOCH FROM AVG(purchase_to_approve_time) filter (where approve_rank <=10)) / 3600, 2)  as avg_approve_hours_worst_10 -- Середній час підтвердження для 10 найдовших кейсів та конвертація часу в години для використання в Power BI
	,ROUND(EXTRACT(EPOCH FROM AVG(purchase_to_approve_time)) / 3600, 2) as avg_approve_hours -- Середній час підтвердження + конвертація в години
from filtered_approve_time
  join order_count using(customer_state)
where order_cnt > 1000 -- Залишаємо штати з 1000+ замовлень 
group by 1, 2
order by 3 desc
