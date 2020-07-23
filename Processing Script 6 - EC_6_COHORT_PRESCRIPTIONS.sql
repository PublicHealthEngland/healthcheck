--------------------------------------------
--------------------------------------------

/* EXTRACTION OF STATIN PRESCRIPTION DATA FOR ATTENDEES AND
NON-ATTENDEES 

--Emma Clegg

--contains:

	-- STEP 1 - Label read codes for statin prescriptions
	-- STEP 2 - Extract prescriptions from journals table
	-- STEP 3 - Keep one prescription record per patient per day, separating into on day / after
	-- STEP 4 - Assign final prescription date to each patient

-- Script uses:
-- 1) Table of attendees/non-attendees with characteristics, risk factors and intervention info
-- at time of NHSHC contact
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_5_COHORT_INTERVENTIONS]

-- 2) CL lookup for statin codes (note: only using EMIS DM+D codes from this)
-- SELECT * FROM [NHS_Health_Checks].[dbo].[EC_STATIN_CLUSTER_FEB20]

-- 3) Cleaned journals table
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]

-- 4) Read code lookup table
-- SELECT * FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
   WHERE CLUSTER_DESCRIPTION LIKE '%STATIN%'

-- Script produces:
-- 1) Table of attendees/non-attendees with statin prescription information for
-- the window around their NHSHC contact
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS]

*/

/*****************************************************************************/

    --------------------------------------------------------------
	-- STEP 1 - Extract and label intervention codes
    --------------------------------------------------------------

DROP TABLE IF EXISTS #PRESCRIPTION_CLUSTERS;

SELECT *
INTO #PRESCRIPTION_CLUSTERS
FROM
(
			(SELECT * FROM
				(SELECT CLUSTER_JOIN_KEY 
					   ,CODING_ID
					   ,CLUSTER_DESCRIPTION
					   ,CODE_DESCRIPTION
					   ,ROW_NUMBER() OVER(PARTITION BY CLUSTER_JOIN_KEY ORDER BY CODE_DESCRIPTION) as 'NO_LABELS'
	              
				FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF] 
				WHERE CLUSTER_DESCRIPTION = 'STATIN CODES'
				GROUP BY CLUSTER_JOIN_KEY 
					   ,CODING_ID
					   ,CLUSTER_DESCRIPTION
					   ,CODE_DESCRIPTION) AS X	   
			WHERE NO_LABELS = 1)   

			UNION 

			(SELECT CLUSTER_JOIN_KEY 
				   ,CLUSTER_ID
				   ,CLUSTER_DESCRIPTION
				   ,CODE_DESCRIPTION
				   ,1 AS 'NO_LABELS'

			FROM [NHS_Health_Checks].[dbo].[EC_DMD_PRESCRIPTIONS_LOOKUP]   -- CL and RP provided full DMD lookup on 11/3/2020
			
			WHERE CLUSTER_DESCRIPTION = 'Statin Codes'
			GROUP BY  CLUSTER_JOIN_KEY 
				   ,CLUSTER_ID
				   ,CLUSTER_DESCRIPTION
				   ,CODE_DESCRIPTION

			)
) AS X;
-- 134 rows

    --------------------------------------------------------------
	-- STEP 2 - Extract prescriptions from journals table
    --------------------------------------------------------------

 --- Extract prescription records for all patients from journals table
DROP TABLE IF EXISTS #EC_EXTRACT; 

SELECT 
    A.PATIENT_JOIN_KEY
	,A.[DATE]
	,A.CLUSTER_JOIN_KEY 
		                               
 INTO #EC_EXTRACT
 FROM  [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]  AS A

 INNER JOIN #PRESCRIPTION_CLUSTERS AS B           -- Join on cluster key lookup
 ON A.CLUSTER_JOIN_KEY = B.CLUSTER_JOIN_KEY

 WHERE A.[PATIENT_JOIN_KEY] IN (SELECT PATIENT_JOIN_KEY                      -- Restrict to attendees/non-attendee population
                                   FROM [NHS_Health_Checks].[dbo].[EC_5_COHORT_INTERVENTIONS] 
								   GROUP BY PATIENT_JOIN_KEY)
 AND A.[DATE] IS NOT NULL ;
-- 6,335,812 rows rows


/* 
Keep one prescription record per patient per day.

Look at the time period between the intervention record and the patient's index date, calculating
DATE_DIFF to represent this.

NOTE: This is intended to introduce duplicate rows as some patients have an NHSHC contact 
in multiple financial years!

*/

DROP TABLE IF EXISTS #EC_EXTRACT2;

SELECT  A.[PATIENT_JOIN_KEY]
  	,B.[DATE] AS 'PRESCRIPTION_DATE'
	,A.FIN_YEAR
	,A.INDEX_DATE
	,DATEDIFF(day, CONVERT(VARCHAR, A.INDEX_DATE, 23), CONVERT(VARCHAR, B.[DATE], 23)) AS 'DATE_DIFF'
INTO #EC_EXTRACT2

FROM [NHS_Health_Checks].[dbo].EC_5_COHORT_INTERVENTIONS AS A

-- keeps one record per intervention per patient per day
LEFT JOIN (SELECT *
		  ,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], [DATE] ORDER BY [CLUSTER_JOIN_KEY] DESC) AS rn
		  FROM  #EC_EXTRACT) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE B.rn = 1                   -- keep 1 record per PRESCRIPTION per patient per day
GROUP BY A.[PATIENT_JOIN_KEY]
  	,B.[DATE] 
	,A.FIN_YEAR
	,A.INDEX_DATE;
-- 7,745,484 rows rows


    --------------------------------------------------------------
	-- STEP 3 - Assign one prescription record per patient per day
    --------------------------------------------------------------

	     -- a. Identify intervention closest to NHSHC index date in each time period

/* Create a table of patients who had an prescription record before their index date
(relevant for non-attendees only) */

DROP TABLE IF EXISTS #EC_PRESCRIPTION_BEFORE;

SELECT A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE] AS 'PRESCRIPTION_DATE_BEFORE'
,[DATE_DIFF] AS 'DATE_DIFF_BEFORE' 
INTO #EC_PRESCRIPTION_BEFORE
FROM [NHS_Health_Checks].[dbo].EC_5_COHORT_INTERVENTIONS  AS A

LEFT JOIN (SELECT * -- this orders by most to least recent date
			  ,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR] ORDER BY [DATE_DIFF] DESC) AS rn
			  FROM #EC_EXTRACT2
			  WHERE DATE_DIFF < 0
			  ) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.FIN_YEAR = B.FIN_YEAR
AND A.COHORT = 'NON-ATTENDEE' 
AND B.rn = 1

GROUP BY A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE]
,[DATE_DIFF];
-- 14,984,656 rows


/* Create a table of patients who had an intervention record on their index date */
DROP TABLE IF EXISTS #EC_PRESCRIPTION_ONDAY;

SELECT A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE] AS 'PRESCRIPTION_DATE_ONDAY'
,[DATE_DIFF] AS 'DATE_DIFF_ONDAY' 
INTO #EC_PRESCRIPTION_ONDAY
FROM [NHS_Health_Checks].[dbo].EC_5_COHORT_INTERVENTIONS  AS A

LEFT JOIN (SELECT * 
           FROM #EC_EXTRACT2
		   WHERE DATE_DIFF = 0) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.FIN_YEAR = B.FIN_YEAR

GROUP BY A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE]
,[DATE_DIFF];
-- 14,984,656 rows


/* Create a table of patients who had an intervention record on the day of their NHSHC */
DROP TABLE IF EXISTS #EC_PRESCRIPTION_AFTER;

SELECT A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE] AS 'PRESCRIPTION_DATE_AFTER'
,[DATE_DIFF] AS 'DATE_DIFF_AFTER' 
INTO #EC_PRESCRIPTION_AFTER
FROM [NHS_Health_Checks].[dbo].EC_5_COHORT_INTERVENTIONS  AS A

LEFT JOIN (SELECT * -- this orders by closest date to index date
			  ,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR] ORDER BY [DATE_DIFF]) AS rn
			  FROM #EC_EXTRACT2
			  WHERE DATE_DIFF > 0
			  ) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.FIN_YEAR = B.FIN_YEAR
AND B.rn = 1
AND (A.COHORT = 'NON-ATTENDEE' OR
    (A.COHORT = 'ATTENDEE' AND DATE_DIFF <= 365))

GROUP BY A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[PRESCRIPTION_DATE]
,[DATE_DIFF];
-- 14,984,656 rows

-- Checks
select TOP 10 * from #EC_PRESCRIPTION_AFTER
where COHORT = 'ATTENDEE'
AND DATE_DIFF_AFTER IS NOT NULL


    --------------------------------------------------------------
	-- STEP 4 - Assign final prescription metrics to patients
    --------------------------------------------------------------

DROP TABLE IF EXISTS #PATIENT_PRESCRIPTIONS;

SELECT * INTO #PATIENT_PRESCRIPTIONS 
FROM (

SELECT 
A.*
,COALESCE(DATE_DIFF_ONDAY, DATE_DIFF_BEFORE, DATE_DIFF_AFTER) AS PRESCRIPTION_DATE_DIFF

FROM [NHS_Health_Checks].[dbo].[EC_5_COHORT_INTERVENTIONS] AS A

LEFT JOIN #EC_PRESCRIPTION_BEFORE AS B 
ON A.[PATIENT_JOIN_KEY] = B.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B.FIN_YEAR

LEFT JOIN #EC_PRESCRIPTION_ONDAY AS C
ON A.[PATIENT_JOIN_KEY] = C.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C.FIN_YEAR

LEFT JOIN #EC_PRESCRIPTION_AFTER AS D
ON A.[PATIENT_JOIN_KEY] = D.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = D.FIN_YEAR 
) AS X;
-- 14,984,656 rows


-- View data
SELECT TOP 10 * FROM #PATIENT_PRESCRIPTIONS;

-- Save to permanent table
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS];

SELECT *
INTO [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS]
FROM #PATIENT_PRESCRIPTIONS AS X;
-- 14,984,656 rows


-- View data
SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS]

-- Drop intermediary tables
DROP TABLE IF EXISTS #EC_EXTRACT;
DROP TABLE IF EXISTS #EC_EXTRACT2;
DROP TABLE IF EXISTS #EC_PRESCRIPTION_ONDAY;
DROP TABLE IF EXISTS #EC_PRESCRIPTION_ONDAY2;
DROP TABLE IF EXISTS #EC_PRESCRIPTION_AFTER;
DROP TABLE IF EXISTS #EC_PRESCRIPTION_AFTER2;



