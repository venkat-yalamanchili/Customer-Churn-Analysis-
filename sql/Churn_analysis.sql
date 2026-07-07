/*
RetentionIQ: Telecom Churn Intelligence

Tables:
    dbo.Customer_Data       -- historical customer data used in Power BI analysis
    dbo.Predicted_Churn     -- customers scored by the Random Forest model

Important fields used:
    Customer_ID, Gender, Age, Married, State, Tenure_in_Months, Contract,
    Payment_Method, Internet_Type, Monthly_Charge, Total_Revenue,
    Customer_Status, Churn_Category, Churn_Reason, Customer_Status_Predicted

Definition used:
    Churned customer = Customer_Status = 'Churned'
    Predicted churner = Customer_Status_Predicted = 1
*/

/* ============================================================
   1. What is the overall customer base, churn count, and churn rate?
   Business use: Gives leadership the headline KPI for retention.
   SQL skill: Aggregate + conditional aggregation.
============================================================ */
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
    CAST(
        100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS churn_rate_pct,
    SUM(CASE WHEN Customer_Status = 'Joined' THEN 1 ELSE 0 END) AS new_joiners,
    SUM(CASE WHEN Customer_Status = 'Stayed' THEN 1 ELSE 0 END) AS stayed_customers
FROM dbo.Customer_Data;


/* ============================================================
   2. Which contract types have the highest churn rate?
   Business use: Identifies whether month-to-month customers are a retention risk.
   SQL skill: GROUP BY + HAVING + conditional aggregation.
============================================================ */
SELECT
    Contract,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
    CAST(
        100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS churn_rate_pct
FROM dbo.Customer_Data
GROUP BY Contract
HAVING COUNT(*) >= 50
ORDER BY churn_rate_pct DESC;


/* ============================================================
   3. Which payment methods are linked with higher churn?
   Business use: Shows if certain billing/payment experiences need improvement.
   SQL skill: CTE + ranking window function.
============================================================ */
WITH payment_churn AS (
    SELECT
        Payment_Method,
        COUNT(*) AS total_customers,
        SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
        CAST(
            100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5,2)
        ) AS churn_rate_pct
    FROM dbo.Customer_Data
    GROUP BY Payment_Method
)
SELECT
    Payment_Method,
    total_customers,
    churned_customers,
    churn_rate_pct,
    DENSE_RANK() OVER (ORDER BY churn_rate_pct DESC) AS churn_risk_rank
FROM payment_churn
ORDER BY churn_risk_rank;


/* ============================================================
   4. Which states contribute most to churn?
   Business use: Prioritizes retention campaigns by geography.
   SQL skill: CTE + window function for contribution percentage.
============================================================ */
WITH state_churn AS (
    SELECT
        State,
        COUNT(*) AS total_customers,
        SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers
    FROM dbo.Customer_Data
    GROUP BY State
)
SELECT TOP 10
    State,
    total_customers,
    churned_customers,
    CAST(100.0 * churned_customers / total_customers AS DECIMAL(5,2)) AS churn_rate_pct,
    CAST(
        100.0 * churned_customers / SUM(churned_customers) OVER ()
        AS DECIMAL(5,2)
    ) AS share_of_total_churn_pct
FROM state_churn
ORDER BY churned_customers DESC;


/* ============================================================
   5. Which age groups are most likely to churn?
   Business use: Helps define customer segments for targeted retention offers.
   SQL skill: CASE bucketing + GROUP BY.
============================================================ */
SELECT
    CASE
        WHEN Age < 20 THEN '< 20'
        WHEN Age BETWEEN 20 AND 35 THEN '20-35'
        WHEN Age BETWEEN 36 AND 50 THEN '36-50'
        ELSE '> 50'
    END AS age_group,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
    CAST(
        100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS churn_rate_pct
FROM dbo.Customer_Data
GROUP BY
    CASE
        WHEN Age < 20 THEN '< 20'
        WHEN Age BETWEEN 20 AND 35 THEN '20-35'
        WHEN Age BETWEEN 36 AND 50 THEN '36-50'
        ELSE '> 50'
    END
ORDER BY churn_rate_pct DESC;


/* ============================================================
   6. Does tenure affect churn behavior?
   Business use: Finds when customers are most vulnerable in their lifecycle.
   SQL skill: CTE + CASE bucketing + custom sort.
============================================================ */
WITH tenure_segments AS (
    SELECT
        Customer_ID,
        Customer_Status,
        CASE
            WHEN Tenure_in_Months < 6 THEN '< 6 Months'
            WHEN Tenure_in_Months BETWEEN 6 AND 12 THEN '6-12 Months'
            WHEN Tenure_in_Months BETWEEN 13 AND 18 THEN '12-18 Months'
            WHEN Tenure_in_Months BETWEEN 19 AND 24 THEN '18-24 Months'
            ELSE '>= 24 Months'
        END AS tenure_group
    FROM dbo.Customer_Data
)
SELECT
    tenure_group,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
    CAST(
        100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS churn_rate_pct
FROM tenure_segments
GROUP BY tenure_group
ORDER BY
    CASE tenure_group
        WHEN '< 6 Months' THEN 1
        WHEN '6-12 Months' THEN 2
        WHEN '12-18 Months' THEN 3
        WHEN '18-24 Months' THEN 4
        ELSE 5
    END;


/* ============================================================
   7. What are the top reasons customers churn?
   Business use: Converts churn analysis into operational action items.
   SQL skill: GROUP BY + window percent-of-total.
============================================================ */
WITH churn_reasons AS (
    SELECT
        Churn_Category,
        Churn_Reason,
        COUNT(*) AS churned_customers
    FROM dbo.Customer_Data
    WHERE Customer_Status = 'Churned'
    GROUP BY Churn_Category, Churn_Reason
)
SELECT TOP 10
    Churn_Category,
    Churn_Reason,
    churned_customers,
    CAST(
        100.0 * churned_customers / SUM(churned_customers) OVER ()
        AS DECIMAL(5,2)
    ) AS pct_of_top_10_result_set
FROM churn_reasons
ORDER BY churned_customers DESC;


/* ============================================================
   8. Which internet service types have the highest churn rate?
   Business use: Identifies product/service areas that may need quality improvement.
   SQL skill: Subquery + comparison against average churn rate.
============================================================ */
SELECT
    Internet_Type,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) AS churned_customers,
    CAST(
        100.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS churn_rate_pct,
    CASE
        WHEN 1.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*) >
             (SELECT 1.0 * SUM(CASE WHEN Customer_Status = 'Churned' THEN 1 ELSE 0 END) / COUNT(*)
              FROM dbo.Customer_Data)
        THEN 'Above Average Risk'
        ELSE 'Below Average Risk'
    END AS risk_label
FROM dbo.Customer_Data
GROUP BY Internet_Type
ORDER BY churn_rate_pct DESC;


/* ============================================================
   9. Which customers create the highest revenue risk if they churn?
   Business use: Builds a save-list for account managers.
   SQL skill: CTE + ROW_NUMBER window function.
============================================================ */
WITH churned_customers AS (
    SELECT
        Customer_ID,
        State,
        Contract,
        Payment_Method,
        Monthly_Charge,
        Total_Revenue,
        Churn_Category,
        ROW_NUMBER() OVER (ORDER BY Total_Revenue DESC) AS revenue_rank
    FROM dbo.Customer_Data
    WHERE Customer_Status = 'Churned'
)
SELECT TOP 25
    revenue_rank,
    Customer_ID,
    State,
    Contract,
    Payment_Method,
    Monthly_Charge,
    Total_Revenue,
    Churn_Category
FROM churned_customers
ORDER BY revenue_rank;


/* ============================================================
   10. For every state, who are the top 3 churned customers by revenue?
   Business use: Finds high-value churn cases within each region.
   SQL skill: Window function with PARTITION BY.
============================================================ */
WITH ranked_state_customers AS (
    SELECT
        State,
        Customer_ID,
        Contract,
        Total_Revenue,
        Churn_Category,
        ROW_NUMBER() OVER (
            PARTITION BY State
            ORDER BY Total_Revenue DESC
        ) AS state_revenue_rank
    FROM dbo.Customer_Data
    WHERE Customer_Status = 'Churned'
)
SELECT
    State,
    state_revenue_rank,
    Customer_ID,
    Contract,
    Total_Revenue,
    Churn_Category
FROM ranked_state_customers
WHERE state_revenue_rank <= 3
ORDER BY State, state_revenue_rank;


/* ============================================================
   11. Among predicted churners, which groups need immediate attention?
   Business use: Turns model output into a targeted retention campaign.
   SQL skill: CTE + aggregation on predicted data.
============================================================ */
WITH predicted_churners AS (
    SELECT
        Customer_ID,
        State,
        Contract,
        Payment_Method,
        Monthly_Charge,
        Total_Revenue
    FROM dbo.Predicted_Churn
    WHERE Customer_Status_Predicted = 1
)
SELECT TOP 10
    State,
    Contract,
    Payment_Method,
    COUNT(*) AS predicted_churners,
    CAST(AVG(Monthly_Charge) AS DECIMAL(10,2)) AS avg_monthly_charge,
    CAST(SUM(Total_Revenue) AS DECIMAL(12,2)) AS revenue_at_risk
FROM predicted_churners
GROUP BY State, Contract, Payment_Method
ORDER BY predicted_churners DESC, revenue_at_risk DESC;


/* ============================================================
   12. Which predicted churners should be contacted first?
   Business use: Prioritizes high-value customers from the ML prediction output.
   SQL skill: Subquery + ORDER BY business priority.
============================================================ */
SELECT TOP 25
    Customer_ID,
    State,
    Contract,
    Payment_Method,
    Monthly_Charge,
    Total_Revenue,
    Number_of_Referrals,
    Tenure_in_Months
FROM dbo.Predicted_Churn
WHERE Customer_Status_Predicted = 1
  AND Total_Revenue > (
        SELECT AVG(Total_Revenue)
        FROM dbo.Predicted_Churn
        WHERE Customer_Status_Predicted = 1
  )
ORDER BY Total_Revenue DESC;
