--segmenting the customer details by RFM(recency,frequency,monetary) framework
--the final result set will be one row per customer.
-- creating cte(customer, orders, nation) for making all the necessary database name in short
 
with customer as
(
	select *
	from snowflake_sample_data.tpch_sf1.customer
),
orders as
(
	select *
	from snowflake_sample_data.tpch_sf1.orders
),
nation as
(
	select *
	from snowflake_sample_data.tpch_sf1.nation
),
 
--to find the analysis order date by dateadd function(because current date is 18.11.2026 so if we calculate recency with this date there will be huge difference in days so i am adding one day to the latest date in this dataset for reference date for calculating datediff)
 
analysis_order_date as
(
	select
    	dateadd(day, 1, max(to_date(o_orderdate))) AS analysis_date
	from orders
),
--customer_order_details cte - It will join the necessary tables(customer,orders and nation) for retriving the final display output
customer_order_details as
(
	select
    	c.c_custkey as customer_id,
    	c.c_name as customer_name,
    	c.c_address as address,
    	c.c_acctbal as account_balance,
    	c.c_phone as phone,
    	c.c_mktsegment as marketing_segment,
    	n.n_name as nation_name,
    	o.o_orderkey as order_id,
    	o.o_orderdate as order_date,
    	o.o_totalprice as total_price,
-- using left join by order table and nation table  for getting all customer - order details
	from customer as c
	left join orders as o
    	on c.c_custkey = o.o_custkey
-- using left join by nation table for getting the nation name per customer
	left join nation as n
    	on c.c_nationkey = n.n_nationkey 	
),
 
--finding customer frequency(no of order placed per customer) and monetary values(total values spent per customer for placing the order)
frequency_monetary_analysis as
(
	select
    	customer_id,
    	customer_name,
    	address,
    	phone,
    	marketing_segment,
    	account_balance,
    	nation_name,
    	count(order_id) as frequency,
-- To making null value as 0 to display in final dataset
    	coalesce(sum(total_price), 0) as monetary,
    	coalesce(avg(total_price), 0) as average_order_value,
--converting to date format if any text format in date available and finding latest order date for finding date difference with reference date for identifying recency(how long ago the customer placed their latest order).
    	max(to_date(order_date)) as latest_order_date
	from customer_order_details 
	group by customer_id,
    	customer_name,
    	address,
    	phone,
    	marketing_segment,
    	account_balance,
    	nation_name
),
--finding recency for each customer
customer_rfm_values as
(
	select
    	f.*,
    	a.*,
--finding day difference for customers latest purchase(analysis_date - latest_order_date)(using - for getting positive value in resultset)
    	-datediff(
    	day,
    	a.analysis_date,
    	f.latest_order_date) as recency
	from frequency_monetary_analysis as f
	cross join analysis_order_date as a
-- there is only one analysis date so that need to compare with each and every customer latest orderdate then only we can find the diffrence in their dates (recency) so used cross join
),
--calculating the rfm scores
active_customer_rfm_scores as
(
	select
    	*,
-- RFM scores are calculated only for customers who have placed orders.
-- Customers without orders are assigned a score of 0 in the next CTE.
--ntile window function will split the row into 5 approximately equal group based on recency, frequency and monetary for calculating the rfm scores
--if smaller the recency will be the better value, higher frequency and monetary will be the better value
 	ntile(5) over (
        	order by recency desc
    	) as recency_score,
 	ntile(5) over (
        	order by frequency asc
    	) as frequency_score,
 	ntile(5) over (
        	order by monetary asc
    	) as monetary_score
	from customer_rfm_values
	where frequency > 0
),
-- finding all customer rfm value even the customer who have not placed an order then left join the active customer rfm and all customer rfm value
all_customer_rfm_scores as
(
	select
    	c.*,
    	coalesce(s.recency_score, 0) as recency_score,
    	coalesce(s.frequency_score, 0) as frequency_score,
    	coalesce(s.monetary_score, 0) as monetary_score
	from customer_rfm_values as c
	left join active_customer_rfm_scores as s
    	on c.customer_id = s.customer_id
),
--combining three rfm score to show the rfm score by using concat and assigning the segment
customer_segmentation as
(
	select
    	*,
    	case
        	when frequency = 0 then 'N/A'
        	else
        	concat(
        	recency_score,
        	frequency_score,
        	monetary_score
        	)
        	end as rfm_score,
    	
--approximately assuming the range for rfm scores to segment the customer based on their rfm scores
    	case
        	when frequency = 0
            	then 'no_order'
        	when recency_score >= 4
        	and frequency_score >= 4
        	and monetary_score >= 4
            	then 'excellent_customer'
        	when recency_score >=  3
        	and frequency_score >= 4
            	then 'loyal_customer'
        	when monetary_score >= 4
            	then 'high_spend_customer'
        	when recency_score >=  4
        	and frequency_score <= 2
            	then 'new_customer'
        	when recency_score <= 2
        	and frequency_score >= 4
            	then 'at_risk_customer'
        	when recency_score <= 2
        	and frequency_score <= 2
            	then 'high_risk_customer'
        	else 'other'
    	end as customer_segment    	
	from all_customer_rfm_scores
)
--final select query to show the output by ordering rfm scores
select
	*
from customer_segmentation
order by recency_score desc,
     	frequency_score desc,
     	monetary_score desc
;

