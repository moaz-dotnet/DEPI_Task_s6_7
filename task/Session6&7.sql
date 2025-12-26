use StoreDB;
------------------------------------------------------------

-- Create a stored procedure named sp_GetCustomerOrderHistory that accepts a customer ID and optional start/end dates. Return the customer's order history with order totals calculated.
create procedure sp_getcustomerorderhistory
	@customer_id int,
	@start_date date = null,
	@end_date date = null
as
begin
	select 
		o.order_id,
		o.order_date,
		sum(oi.quantity * oi.list_price * (1 - oi.discount)) as order_total
	from sales.orders o
	join sales.order_items oi
		on o.order_id = oi.order_id
	where o.customer_id = @customer_id
	  and (@start_date is null or o.order_date >= @start_date)
	  and (@end_date is null or o.order_date <= @end_date)
	group by o.order_id, o.order_date
	order by o.order_date;
end;


-- Write a stored procedure named sp_RestockProduct with input parameters for store ID, product ID, and restock quantity. Include output parameters for old quantity, new quantity, and success status.
create procedure sp_restockproduct
	@store_id int,
	@product_id int,
	@restock_quantity int,
	@old_quantity int output,
	@new_quantity int output,
	@success bit output
as
begin
	select @old_quantity = quantity
	from production.stocks
	where store_id = @store_id and product_id = @product_id;

	if @old_quantity is null
	begin
		set @success = 0;
		return;
	end

	update production.stocks
	set quantity = quantity + @restock_quantity
	where store_id = @store_id and product_id = @product_id;

	select @new_quantity = quantity
	from production.stocks
	where store_id = @store_id and product_id = @product_id;

	set @success = 1;
end;


-- Create a stored procedure named sp_ProcessNewOrder that handles complete order creation with proper transaction control and error handling. Include parameters for customer ID, product ID, quantity, and store ID.
create procedure sp_processneworder
	@customer_id int,
	@product_id int,
	@quantity int,
	@store_id int
as
begin
	begin try
		begin transaction;

		insert into sales.orders
		(customer_id, order_status, order_date, required_date, store_id, staff_id)
		values
		(@customer_id, 1, getdate(), dateadd(day, 7, getdate()), @store_id, 1);

		declare @order_id int = scope_identity();

		insert into sales.order_items
		(order_id, item_id, product_id, quantity, list_price, discount)
		select
			@order_id, 1, p.product_id, @quantity, p.list_price, 0
		from production.products p
		where p.product_id = @product_id;

		update production.stocks
		set quantity = quantity - @quantity
		where store_id = @store_id and product_id = @product_id;

		commit;
	end try
	begin catch
		rollback;
	end catch
end;


-- Write a stored procedure named sp_SearchProducts that builds dynamic SQL based on optional parameters: product name search term, category ID, minimum price, maximum price, and sort column.
create procedure sp_searchproducts
	@product_name varchar(255) = null,
	@category_id int = null,
	@min_price decimal(10,2) = null,
	@max_price decimal(10,2) = null,
	@sort_column varchar(50) = 'product_name'
as
begin
	declare @sql nvarchar(max) = '
	select *
	from production.products
	where 1=1';

	if @product_name is not null
		set @sql += ' and product_name like ''%' + @product_name + '%''';

	if @category_id is not null
		set @sql += ' and category_id = ' + cast(@category_id as varchar);

	if @min_price is not null
		set @sql += ' and list_price >= ' + cast(@min_price as varchar);

	if @max_price is not null
		set @sql += ' and list_price <= ' + cast(@max_price as varchar);

	set @sql += ' order by ' + @sort_column;

	exec sp_executesql @sql;
end;


-- Create a complete solution that calculates quarterly bonuses for all staff members. Use variables to store date ranges and bonus rates. Apply different bonus percentages based on sales performance tiers.
declare @start_date date = '2025-01-01';
declare @end_date date = '2025-03-31';
declare @low_bonus decimal(5,2) = 0.05;
declare @mid_bonus decimal(5,2) = 0.10;
declare @high_bonus decimal(5,2) = 0.15;

select
	s.staff_id,
	s.first_name,
	s.last_name,
	sum(oi.quantity * oi.list_price) as total_sales,
	case
		when sum(oi.quantity * oi.list_price) < 5000 then sum(oi.quantity * oi.list_price) * @low_bonus
		when sum(oi.quantity * oi.list_price) between 5000 and 15000 then sum(oi.quantity * oi.list_price) * @mid_bonus
		else sum(oi.quantity * oi.list_price) * @high_bonus
	end as bonus
from sales.staffs s
join sales.orders o on s.staff_id = o.staff_id
join sales.order_items oi on o.order_id = oi.order_id
where o.order_date between @start_date and @end_date
group by s.staff_id, s.first_name, s.last_name;


-- Write a complex query with nested IF statements that manages inventory restocking. Check current stock levels and apply different reorder quantities based on product categories and current stock levels.
select
	p.product_id,
	p.product_name,
	s.quantity,
	case
		when s.quantity < 10 then 'reorder 50 units'
		when s.quantity between 10 and 30 then 'reorder 20 units'
		else 'stock sufficient'
	end as action
from production.products p
join production.stocks s
	on p.product_id = s.product_id;


-- Create a comprehensive solution that assigns loyalty tiers to customers based on their total spending. Handle customers with no orders appropriately and use proper NULL checking.
select
	c.customer_id,
	c.first_name,
	c.last_name,
	sum(oi.quantity * oi.list_price) as total_spent,
	case
		when sum(oi.quantity * oi.list_price) is null then 'no orders'
		when sum(oi.quantity * oi.list_price) < 5000 then 'silver'
		when sum(oi.quantity * oi.list_price) between 5000 and 15000 then 'gold'
		else 'platinum'
	end as loyalty_tier
from sales.customers c
left join sales.orders o on c.customer_id = o.customer_id
left join sales.order_items oi on o.order_id = oi.order_id
group by c.customer_id, c.first_name, c.last_name;


-- Write a stored procedure that handles product discontinuation including checking for pending orders, optional product replacement in existing orders, clearing inventory, and providing detailed status messages.
create procedure sp_discontinueproduct
	@product_id int,
	@replacement_product_id int = null
as
begin
	if exists (
		select 1
		from sales.order_items oi
		join sales.orders o on oi.order_id = o.order_id
		where oi.product_id = @product_id
		  and o.order_status in (1,2)
	)
	begin
		if @replacement_product_id is not null
		begin
			update sales.order_items
			set product_id = @replacement_product_id
			where product_id = @product_id;
		end
		else
		begin
			return;
		end
	end

	delete from production.stocks
	where product_id = @product_id;

	delete from production.products
	where product_id = @product_id;
end;


------------------------------------------------------------
-- 1.create a non-clustered index on the email column in the sales.customers table to improve search performance when looking up customers by email
create nonclustered index idx_customers_email
on sales.customers(email);

-- 2.create a composite index on the production.products table that includes category_id and brand_id columns to optimize searches that filter by both category and brand
create nonclustered index idx_products_category_brand
on production.products(category_id, brand_id);

-- 3.create an index on sales.orders table for the order_date column and include customer_id, store_id, and order_status as included columns to improve reporting queries
create nonclustered index idx_orders_order_date
on sales.orders(order_date)
include (customer_id, store_id, order_status);

-- 4.create a trigger that automatically inserts a welcome record into a customer_log table whenever a new customer is added to sales.customers

create table sales.customer_log (
	log_id int identity(1,1) primary key,
	customer_id int,
	action varchar(50),
	log_date datetime default getdate()
);
go

create trigger trg_customer_welcome
on sales.customers
after insert
as
begin
	insert into sales.customer_log (customer_id, action)
	select customer_id, 'welcome customer'
	from inserted;
end;

-- 5.create a trigger on production.products that logs any changes to the list_price column into a price_history table

create table production.price_history (
	history_id int identity(1,1) primary key,
	product_id int,
	old_price decimal(10,2),
	new_price decimal(10,2),
	change_date datetime default getdate(),
	changed_by varchar(100)
);
go

create trigger trg_product_price_change
on production.products
after update
as
begin
	if update(list_price)
	begin
		insert into production.price_history (product_id, old_price, new_price, changed_by)
		select d.product_id, d.list_price, i.list_price, suser_name()
		from deleted d
		join inserted i
		on d.product_id = i.product_id;
	end
end;

-- 7.create a trigger on sales.order_items that automatically reduces the quantity in production.stocks when a new order item is inserted

create trigger trg_reduce_stock
on sales.order_items
after insert
as
begin
	update s
	set s.quantity = s.quantity - i.quantity
	from production.stocks s
	join inserted i
	on s.product_id = i.product_id
	join sales.orders o
	on o.order_id = i.order_id
	and s.store_id = o.store_id;
end;

-- 8.create a trigger that logs all new orders into an order_audit table, capturing order details and the date/time when the record was created

create table sales.order_audit (
	audit_id int identity(1,1) primary key,
	order_id int,
	customer_id int,
	store_id int,
	staff_id int,
	order_date date,
	audit_timestamp datetime default getdate()
);
go

create trigger trg_order_audit
on sales.orders
after insert
as
begin
	insert into sales.order_audit (order_id, customer_id, store_id, staff_id, order_date)
	select order_id, customer_id, store_id, staff_id, order_date
	from inserted;
end;

