# **Challenge 2 – Intermediate transformation, exploratory analysis (Silver) and Gold preparation 🔧📊**

## **Goal and step-by-step solution 🧭**

### **Goal 🎯**
Transform Bronze data, perform exploratory analysis in Silver, and finally build the Gold layer.

---

## **Step-by-step solution 🪜**

This approach uses three data products: **Credit Scores** (medallion + customer segmentation with ML KMeans), **Products** (medallion + product segmentation by commercial value with ML KMeans), and **Business Operations** which combines `transactions` and `products` tables to model operational analysis of customer purchases. The exercise is not intended to enforce a strict dimensional model; Fabric supports both dimensional modeling and denormalized approaches common in Big Data environments.

The structure used is shown below:

![Approach](/img/approach.png)


### **Credit score set 🧩**
(This is an example for the financial credit scenario; other approaches are possible.)

- Create a new Dataflow Gen2 or Notebook for the Silver layer
- Configure the source from Bronze tables
- Apply intermediate transformations
- Create derived credit score columns
- Segment customers by credit profile
- Save as a Silver table in the Lakehouse
- Create a new Notebook for the Gold layer of credit scoring
- Configure the source from Silver tables
- Identify the cluster with the highest average score
- Filter customers that belong to that cluster
- Store the results in the Gold layer
- Result: a subset of customers with a high credit profile

---

# **SILVER LAYER - CREDIT SCORE**

# **Example – Create Silver tables - Credit Score 🧮**


## **Load Bronze table with financial data 🧾**

```python

df_fin = spark.sql("SELECT * FROM Contoso_Lakehouse.bronze.credit_score") 
```

---

## **Derive `estimated_credit_score` column based on payment behavior and credit usage 💳**

```python

from pyspark.sql.functions import col, when, udf 
from pyspark.sql.types import StringType 

df_fin = df_fin.withColumn("estimated_credit_score", 
    when(col("Payment_Behaviour") == "High_spent_Small_value_payments", 650)
    .when(col("Payment_Behaviour") == "Low_spent_Large_value_payments", 750)
    .when(col("Payment_Behaviour") == "High_spent_Large_value_payments", 800)
    .when(col("Payment_Behaviour") == "Low_spent_Small_value_payments", 600)
    .otherwise(620)
)
```
---

## **Penalty for late payments ⏰**

```python
df_fin = df_fin.withColumn("estimated_credit_score", 
    col("estimated_credit_score") - (col("Num_of_Delayed_Payment") * 5)
)
```
---

## **Penalty for high credit utilization 📉**

```python
df_fin = df_fin.withColumn("estimated_credit_score", 
    when(col("Credit_Utilization_Ratio") > 0.8, col("estimated_credit_score") - 20)
    .otherwise(col("estimated_credit_score"))
)
```
---

## **Limit score between 300 and 850 ⚙️**

```python
df_fin = df_fin.withColumn("estimated_credit_score", 
    when(col("estimated_credit_score") < 300, 300)
    .when(col("estimated_credit_score") > 850, 850)
    .otherwise(col("estimated_credit_score"))
)
```
---

## **Filter valid records for clustering 🧹**

```python
df_fin_clean = df_fin.filter(col("estimated_credit_score").isNotNull()) 

```
 
---

## **Normalize column names to lower case**

```python
df_fin_clean = df_fin_clean .toDF(*[c.lower() for c in df_fin_clean.columns])
```
---
## **Filter out records with nulls/na and validate ages and loan counts**
```python
df_fin_clean = df_fin_clean.dropna().filter(
col("age").between(1, 120) & 
(col("num_of_loan") >= 0) &
(col("credit_history_age") != "NA"))
```
---

## **💾 Save prepared Silver table**

```python
df_fin_clean.write.option("overwriteSchema", "true").mode("overwrite").saveAsTable("Contoso_Lakehouse.silver.credit_score") 

```

---


# **GOLD LAYER - CREDIT SCORE**

# **Example – Customer segmentation by credit score 🧮**


## **📌 Import required functions**

```python
from pyspark.sql.functions import col, when, udf 
from pyspark.sql.types import StringType 
from pyspark.ml.feature import VectorAssembler 
from pyspark.ml.clustering import KMeans 
```


## **Load prepared Silver table with financial data 🧾**

```python
df_fin = spark.sql("SELECT * FROM Contoso_Lakehouse.silver.credit_score")

```

---

## **Vectorize `estimated_credit_score` column for ML 🤖**

```python
assembler = VectorAssembler(inputCols=["estimated_credit_score"], outputCol="features") 
df_fin_vec = assembler.transform(df_fin_clean) 
```

---

## **Apply KMeans clustering to segment customers 🧠**

```python
kmeans = KMeans(k=3, seed=42) 
model_fin = kmeans.fit(df_fin_vec) 
df_fin_clustered = model_fin.transform(df_fin_vec) 
```

---

## **Label credit profiles by average score per cluster 🏷️**

```python
cluster_scores = df_fin_clustered.groupBy("prediction") \
    .avg("estimated_credit_score") \
    .orderBy("avg(estimated_credit_score)", ascending=False) \
    .collect()
```

---

## **Create label map: High, Medium, Low 🗺️**

```python
cluster_map = {} 
for i, row in enumerate(cluster_scores): 
    cluster_map[row["prediction"]] = ["High", "Medium", "Low"][i] 
```

---

## **UDF to assign label ⚡**

```python
def map_cluster(pred): 
    return cluster_map.get(pred, "Unknown") 

map_udf = udf(map_cluster, StringType()) 
df_segmented = df_fin_clustered.withColumn("credit_profile", map_udf(col("prediction"))) 
```

---

## **Count customers by profile (optional for validation) 📊**

```python
df_segmented.groupBy("credit_profile").count().orderBy("count", ascending=False).show() 
```

---

## **Filter customers by profile 🥇**
**NOTE**: This step can be adjusted to analyze all tiers or only high-profile customers

```python
#df_gold_fin = df_segmented.filter(col("credit_profile") == "High") 
#display(df_gold_fin)
df_gold_fin = df_segmented
```

---

## **Drop ML helper columns**

```python
drop_columns = ["features", "prediction"]
df_gold_fin = df_gold_fin.drop(*drop_columns)
```

---

## **Save Gold table with top-tier customers 💾**

```python
df_gold_fin.write.option("mergeSchema", "true").mode("overwrite").saveAsTable("Contoso_Lakehouse.gold.credit_score") 

```

---

### **Retail set by Product 🧩**
(This is another example; apply similar steps to product scenarios)

- Create a new Dataflow Gen2 or Notebook for Silver
- Configure the source from Bronze tables
- Apply intermediate transformations
- Create derived columns
- Segment products/customers
- Save as a Silver table and prepare Gold
- Result: curated subsets ready for Gold


# **SILVER LAYER - RETAIL**

# **Example – Create Silver tables - Retail 🧮**

---

## **📌 Import required functions**

```python
from pyspark.sql.functions import col, when, udf 
from pyspark.sql.types import StringType 

```

---

## **Load Silver table with retail product catalog 🧾**

```python
df_retail = spark.read.table("silver_products") 
```

---

## **🧮 Derive `inventory_value` = Price × Stock**

```python
df_retail = df_retail.withColumn("inventory_value", col("Price") * col("Stock")) 
```

---

## **🧮 Derive binary availability column**

```python
df_retail = df_retail.withColumn("available", 
    when(col("Availability") == "in_stock", 1).otherwise(0)
)
```

---

## **🧹 Filter valid records for clustering**

```python
df_retail_clean = df_retail.filter( 
    col("inventory_value").isNotNull() & col("available").isNotNull()
)
```

---

## **Normalize column names to lower case**

```python
df_fin_clean = df_fin_clean .toDF(*[c.lower() for c in df_fin_clean.columns])
```
---

## **💾 Save prepared Silver table**

```python
df_retail_clean.write.option("overwriteSchema", "true").mode("overwrite").saveAsTable("Contoso_Lakehouse.silver.products") 

```

---



# **GOLD LAYER - RETAIL**

# **Example – Product segmentation 🧮**

---

## **📌 Import required functions**

```python
from pyspark.sql.functions import col, when, udf 
from pyspark.sql.types import StringType 
from pyspark.ml.feature import VectorAssembler 
from pyspark.ml.clustering import KMeans 
```
---

## **📊 Vectorize columns for ML**

```python
assembler = VectorAssembler(inputCols=["inventory_value", "available"], outputCol="features") 
df_retail_vec = assembler.transform(df_retail_clean) 
```

---

## **🤖 Apply KMeans clustering to segment products**

```python
kmeans = KMeans(k=3, seed=42) 
model_retail = kmeans.fit(df_retail_vec) 
df_retail_clustered = model_retail.transform(df_retail_vec) 
```

---

## **🏷️ Label products by average commercial value per cluster**

```python
cluster_scores = df_retail_clustered.groupBy("prediction") \
    .avg("inventory_value") \
    .orderBy("avg(inventory_value)", ascending=False) \
    .collect()
```

---

## **Create label map: Valuable, Medium, Low 🗺️**

```python
cluster_map = {} 
for i, row in enumerate(cluster_scores): 
    cluster_map[row["prediction"]] = ["Valuable", "Medium", "Low"][i] 
```

---

## **UDF to assign label ⚡**

```python
def map_cluster(pred): 
    return cluster_map.get(pred, "Unknown") 

map_udf = udf(map_cluster, StringType()) 
df_segmented = df_retail_clustered.withColumn("product_value_tier", map_udf(col("prediction"))) 
---

## **🥇 Filter available products**
**NOTE**: Adjust the filter to include all product value tiers or only the high-value tier.

```python
#df_gold_retail = df_segmented.filter(
#    (col("product_value_tier") == "Valioso") & (col("available") == 1)
#)
#display(df_gold_retail)
df_gold_retail = df_segmented.filter(
    (col("available") == 1))
```

---

## **Drop unnecessary ML helper columns**

```python
drop_columns = ["features", "prediction"]
df_gold_retail = df_gold_retail.drop(*drop_columns)

```

## **💾 Save the Gold table of available products**

```python
df_gold_retail.write.option("overwriteSchema", "true").mode("overwrite").saveAsTable("Contoso_Lakehouse.gold.products")
```

---


# **Preparation and promotion to the Gold layer (Business Operations — Transactions) 🛍️🤖**


## **Step-by-step solution 🪜**

### **Transaction dataset🧩**  
(This example demonstrates one approach to processing transaction data; other approaches are possible.)

- Create a new Dataflow Gen2 or notebook for the Silver layer
- Configure the Bronze tables as the data source
- Apply intermediate transformations 
- Extract basic date attributes
- Segment transactions by transaction amount
- Derive financing indicators
- Save the results as a Silver table in the lakehouse
- Create a new notebook for the Business Operations Gold layer
- Load the Silver transaction and product tables
- Left-join transactions to products using `product_id`
- Select the required transaction attributes, product attributes, and derived fields
- Save the result to the Gold layer
- Result: an enriched transaction table for operational analysis


---


# **SILVER LAYER - TRANSACTIONS**

# **Example — Create Silver tables for transactions 🧮**

---

## **📌 Import required functions**

```python
from pyspark.sql.functions import *
```
---

## **Load Bronze transaction data**

```python
df_transactions = spark.read.table("Contoso_Lakehouse.bronze.transactions")

print(f"💳 Transactions in Bronze: {df_transactions.count():,}")
print("\n📋 Schema:")
df_transactions.printSchema()
```
---

## **Silver layer transformations**

```python
df_transactions_enriched = (
    df_transactions
    
    # ============================================
    # DATE FEATURES (essential fields only)
    # ============================================
    .withColumn("year", year("transaction_date"))
    .withColumn("month", month("transaction_date"))
    .withColumn("quarter", quarter("transaction_date"))
    .withColumn("year_month", date_format("transaction_date", "yyyy-MM"))
    
    # ============================================
    # TRANSACTION AMOUNT SEGMENTATION
    # ============================================
    .withColumn("ticket_segment", 
        when(col("amount") < 500, "Low")
        .when(col("amount") < 1000, "Medium")
        .otherwise("High")
    )
    
    # ============================================
    # FINANCING INDICATORS
    # ============================================
    .withColumn("is_msi", col("installments") > 1)
    .withColumn("is_credit", col("payment_method") == "Credit")
    
    # Solo transacciones aprobadas
    .filter(col("approval_status") == "Approved")
    
    # ============================================
    # FINANCING INDICATORS
    # ============================================
    .select(
        # IDs
        "transaction_id",
        "customer_id",
        "product_id",
        
        # Transaction
        "transaction_date",
        "amount",
        "quantity",
        "payment_method",
        "installments",
        "channel",
        "store_location",
        
        # Time
        "year",
        "month",
        "quarter",
        "year_month",
        
        # Segments
        "ticket_segment",
        "is_msi",
        "is_credit"
    )
)
```
---

## **Data quality checks**

```python
total_transactions = df_transactions_enriched.count()
print(f"✅ Total transactions in Silver: {total_transactions:,}")

unique_customers = df_transactions_enriched.select("customer_id").distinct().count()
print(f"👥 Unique customers: {unique_customers:,}")

print("\n💰 Transaction counts by amount segment:")
df_transactions_enriched.groupBy("ticket_segment").count().orderBy("ticket_segment").show()

```
---

## **💾 Save the prepared Silver table**

```python
df_transactions_enriched.write \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .saveAsTable("Contoso_Lakehouse.silver.transactions")

print(f"✅ Silver table created: silver.transactions")
print(f"   Records: {total_transactions:,}")
print(f"   Customers: {unique_customers:,}")
```

---

# **GOLD LAYER - BUSINESS OPERATIONS**
This notebook creates a Gold table by combining:
- Transactions (`silver.transactions`)
- Products (`silver.products`)

**Output**: `gold.business_operations` — a transaction-level fact table enriched with product attributes for operational analysis

# **Example — Business Operations: Join transactions and products 🧮**

```python
from pyspark.sql.functions import *
```

---

## **Load Silver layer data**

```python
# Enriched transactions
df_transactions = spark.read.table("Contoso_Lakehouse.silver.transactions")

# Enriched products
df_products = spark.read.table("Contoso_Lakehouse.silver.products")

print(f"Transactions: {df_transactions.count():,} registros")
print(f"Products: {df_products.count():,} registros")
```

---

## **Create the Gold table**

```python

df_business_operations = (
    df_transactions
    
    # JOIN with products
    .join(
        df_products.select(
            "product_id",
            "product_name",
            "brand", 
            "category",
            "price",
        ),
        "product_id",
        "left"
    )
    
    # Final column selection (required fields only)
    .select(
        # IDs
        "transaction_id",
        "customer_id",
        "product_id",
        
        # Product
        "product_name",
        "brand", 
        "category",
        "price",
        
        
        # Transaction
        "transaction_date",
        "amount",
        "quantity",
        "payment_method",
        "installments",
        "channel",
        "store_location",
        
        # Time
        "year",
        "month",
        "quarter",
        "year_month",
        
        # Segment
        "ticket_segment",
        "is_msi",
        "is_credit"
    )
)

```

---

## **Validation checks**

```python
total_records = df_business_operations.count()
print(f"✅ Total records en Gold: {total_records:,}")

# Check for nulls in critical fields
null_checks = df_business_operations.select([
    count(when(col(c).isNull(), c)).alias(c) 
    for c in ["customer_id", "product_id", "amount", "transaction_date"]
])
print("\n📊 Nulls in critical fields:")
null_checks.show()
```

---

## **Save the Gold table**

```python

df_business_operations.write \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .saveAsTable("Contoso_Lakehouse.gold.business_operations")

print(f"✅ Successfully created table gold.business_operations")
print(f"   Records: {total_records:,}")

```

---

## **Validation queries**

```python
# Top 10 products by revenue
print("🏆 Top 10 Products by Revenue:")
df_business_operations.groupBy("product_name", "category") \
    .agg(
        count("*").alias("units_sold"),
        sum("amount").alias("total_revenue")
    ) \
    .orderBy(col("total_revenue").desc()) \
    .limit(10) \
    .show(truncate=False)

# Revenue by channel
print("\n📺 Revenue by Channel:")
df_business_operations.groupBy("channel") \
    .agg(
        count("*").alias("transactions"),
        sum("amount").alias("revenue"),
        avg("amount").alias("avg_ticket")
    ) \
    .orderBy(col("revenue").desc()) \
    .show()
```

---
