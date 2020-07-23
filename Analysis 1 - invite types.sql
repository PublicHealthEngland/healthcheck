/* Analysis looking at patients invites 

1) Of everyone that received an invite in period 1/4/12 - 31/3/17, what was their first invite type recorded?

*/
    --------------------------------------------------------------
	-- STEP 1 - Extract NHSHC invites for all patients 
    --------------------------------------------------------------

/* a) Extract and label list of NHSHC invites from GP read code
lookup table */
DROP TABLE IF EXISTS #NHSHC_CONTACT_CLUSTERS;

SELECT CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,ROW_NUMBER() OVER(PARTITION BY A.CLUSTER_JOIN_KEY ORDER BY A.CLUSTER_DESCRIPTION) as 'NO_LABELS'
	,CASE WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation' THEN 'NHSHC invitation (unspecified)'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation email' THEN 'NHSHC invitation - email'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation first letter' THEN 'NHSHC invitation - letter 1'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation second letter' THEN 'NHSHC invitation - letter 2'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation third letter' THEN 'NHSHC invitation - letter 3'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation short message service text message' THEN 'NHSHC invitation - text'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check telephone invitation' THEN 'NHSHC invitation - telephone'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check verbal invitation' THEN 'NHSHC invitation - verbal'
		  ELSE 'Other' END AS INVITE_TYPE 
INTO #NHSHC_CONTACT_CLUSTERS 
FROM [NHS_Health_Checks].[dbo].EXPANDED_CLUSTERS_REF AS A 
WHERE CLUSTER_DESCRIPTION = 'NHS Health Check invitation codes'
GROUP BY CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,CASE WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation' THEN 'NHSHC invitation (unspecified)'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation email' THEN 'NHSHC invitation - email'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation first letter' THEN 'NHSHC invitation - letter 1'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation second letter' THEN 'NHSHC invitation - letter 2'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation third letter' THEN 'NHSHC invitation - letter 3'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation short message service text message' THEN 'NHSHC invitation - text'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check telephone invitation' THEN 'NHSHC invitation - telephone'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check verbal invitation' THEN 'NHSHC invitation - verbal'
		  ELSE 'Other' END;

-- View read codes and descriptions
SELECT * FROM #NHSHC_CONTACT_CLUSTERS
WHERE NO_LABELS = 1
ORDER BY 2,3;


/* b) Extract records for patients' NHSHC invites 
Restrict to max one of each type per patient per day
(period: 1/4/11 - 31/3/17) */
 
DROP TABLE IF EXISTS #HC_INVITES;

SELECT
    A.[PATIENT_JOIN_KEY]
	,B.INVITE_TYPE
	,A.[DATE] AS INVITE_DATE 

 INTO #HC_INVITES
 FROM  [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]  AS A

 INNER JOIN #NHSHC_CONTACT_CLUSTERS AS B           -- keep NHSHC contact records only
 ON A.CLUSTER_JOIN_KEY = B.CLUSTER_JOIN_KEY 
 AND B.NO_LABELS = 1  -- Restrict to one record description per cluster join key

 WHERE A.[DATE] IS NOT NULL 
 AND A.[DATE] >= '2011-04-01'    -- restrict NHSHC contact dates to 5 year time period of interest + 1 year prior
 AND A.[DATE] <= '2017-03-31'  
											 
GROUP BY 
    A.[PATIENT_JOIN_KEY]
	,B.INVITE_TYPE
	,A.[DATE] 
;
-- 14,178,597 rows
-- (14178597 rows affected)


/* Add financial year of invite */
DROP TABLE IF EXISTS #HC_INVITES_2;

SELECT *
       -- Add financial year of NHSHC contact date
	,CASE WHEN A.[INVITE_DATE] >= '2016-04-01' AND A.[INVITE_DATE] <= '2017-03-31' THEN '2016/17'
	 WHEN A.[INVITE_DATE] >= '2015-04-01' AND A.[INVITE_DATE] <= '2016-03-31' THEN '2015/16'
	 WHEN A.[INVITE_DATE] >= '2014-04-01' AND A.[INVITE_DATE] <= '2015-03-31' THEN '2014/15'
	 WHEN A.[INVITE_DATE] >= '2013-04-01' AND A.[INVITE_DATE] <= '2014-03-31' THEN '2013/14'
	 WHEN A.[INVITE_DATE] >= '2012-04-01' AND A.[INVITE_DATE] <= '2013-03-31' THEN '2012/13'
	 WHEN A.[INVITE_DATE] >= '2011-04-01' AND A.[INVITE_DATE] <= '2012-03-31' THEN '2011/12'
	 END AS 'FIN_YEAR_INVITE'
INTO #HC_INVITES_2
FROM #HC_INVITES AS A ;
-- 14,178,597 rows
-- (14178597 rows affected)


    --------------------------------------------------------------
	-- STEP 2 - ATTENDEES
    --------------------------------------------------------------
---------------------------------------------------------------------
/* 1) How many attendees received an invite in the year before their check? */

-- How many attendees?
SELECT FIN_YEAR, 
COUNT(*)
FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
WHERE COHORT = 'ATTENDEE'
GROUP BY FIN_YEAR

-- Extract attendees' invitations and calculate difference in days between invites and
-- their completed check.
-- Note: If an attendee had more than one invite recorded they will have more than one
-- record in this table

DROP TABLE IF EXISTS #ATTENDEE_INVITES;

SELECT A.INVITE_DATE
,A.INVITE_TYPE
,A.FIN_YEAR_INVITE
,DATEDIFF(day, CONVERT(VARCHAR, A.INVITE_DATE, 23), CONVERT(VARCHAR, B.INDEX_DATE, 23)) AS 'DATE_DIFF'
,B.*
INTO #ATTENDEE_INVITES
FROM #HC_INVITES_2 AS A

INNER JOIN [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND B.COHORT = 'ATTENDEE'
-- 5,736,047 rows
-- (5736047 rows affected)


-- Restrict to invites in year before patient's completed check
-- Label patient's invites in order

DROP TABLE IF EXISTS #ATTENDEE_INVITES_2;

SELECT *
,RANK() OVER (PARTITION BY [PATIENT_JOIN_KEY] ORDER BY INVITE_DATE) AS INVITE_NO
INTO #ATTENDEE_INVITES_2
FROM #ATTENDEE_INVITES AS A

WHERE DATE_DIFF BETWEEN 0 AND 365   -- inclusive
-- 4,595,427 rows
-- (4595427 rows affected)

SELECT TOP 200 * FROM #ATTENDEE_INVITES_2
ORDER BY PATIENT_JOIN_KEY

-- Patient_Join_Key In(71,125,346, 470) (more than one invite)  -- 346 twice in financial year   --470 three times in financial year


---------------------------------------------------------------------
/* 2) What proportion of attendees have an invite 
-- a) in the year before or on the day of their check? 67.2%  -- 67.216%
-- b) on the day of their check and not in the year before? 11.6% -- 11.579%
*/

SELECT 
COUNT(A.PATIENT_JOIN_KEY) AS NO_ATTENDEES
,COUNT(B.PATIENT_JOIN_KEY) AS NO_PATIENTS_WITH_INVITE
,COUNT(C.PATIENT_JOIN_KEY) AS NO_PATIENTS_ON_DAY_INVITE
,COUNT(B.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_WITH_INVITE
,COUNT(C.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_ON_DAY_INVITE

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #ATTENDEE_INVITES_2
		   GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #ATTENDEE_INVITES_2
		   WHERE DATE_DIFF = 0
		   AND INVITE_NO = 1
		   GROUP BY PATIENT_JOIN_KEY) AS C
ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY

WHERE A.COHORT = 'ATTENDEE'

SELECT COUNT(A.PATIENT_JOIN_KEY) AS NO_ATTENDEES from
 (select distinct PATIENT_JOIN_KEY FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
   where COHORT = 'ATTENDEE') AS A
-- 5102758

-- Break down by financial year of NHSHC contact
SELECT 
A.FIN_YEAR
,COUNT(A.PATIENT_JOIN_KEY) AS NO_ATTENDEES
,COUNT(B.PATIENT_JOIN_KEY) AS NO_PATIENTS_WITH_INVITE
,COUNT(C.PATIENT_JOIN_KEY) AS NO_PATIENTS_ON_DAY_INVITE
,COUNT(B.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_WITH_INVITE
,COUNT(C.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_ON_DAY_INVITE

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #ATTENDEE_INVITES_2
		   GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #ATTENDEE_INVITES_2
		   WHERE DATE_DIFF = 0
		   AND INVITE_NO = 1
		   GROUP BY PATIENT_JOIN_KEY) AS C
ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY

WHERE A.COHORT = 'ATTENDEE'
GROUP BY A.FIN_YEAR
WITH ROLLUP
ORDER BY 1


---------------------------------------------------------------------
/* 3) What was the average time between first invite and completed check? */

DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_ATTENDEE_INVITE_TIMES]

SELECT *
INTO #EC_ATTENDEE_INVITE_TIMES
FROM
(SELECT PATIENT_JOIN_KEY 
            ,INVITE_DATE
			,INVITE_TYPE
            ,DATE_DIFF
			,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], INVITE_DATE ORDER BY INVITE_TYPE) AS INVITE_NO_DAY
			FROM #ATTENDEE_INVITES_2
	 WHERE INVITE_NO = 1
	 GROUP BY PATIENT_JOIN_KEY
	          ,INVITE_DATE
			  ,INVITE_TYPE
	          ,DATE_DIFF) AS A
WHERE A.INVITE_NO_DAY = 1
;
-- 3,429,914 rows
-- (3429914 rows affected)

SELECT TOP 1000 * FROM #EC_ATTENDEE_INVITE_TIMES

-- Descriptive stats
SELECT 
MIN(DATE_DIFF) AS MIN_DATE_DIFF
,AVG(DATE_DIFF) AS AVG_DATE_DIFF
-- , AS MEDIAN_DATE_DIFF
,MAX(DATE_DIFF) AS MAX_DATE_DIFF
FROM [NHS_Health_Checks].[dbo].[EC_ATTENDEE_INVITE_TIMES]
WHERE DATE_DIFF <> 0

SELECT 
MIN(DATE_DIFF) AS MIN_DATE_DIFF
,AVG(DATE_DIFF) AS AVG_DATE_DIFF
-- , AS MEDIAN_DATE_DIFF
,MAX(DATE_DIFF) AS MAX_DATE_DIFF
FROM #EC_ATTENDEE_INVITE_TIMES
WHERE DATE_DIFF <> 0

-- Distribution
SELECT 
CASE WHEN DATE_DIFF = 0 THEN '1. On day'
     WHEN DATE_DIFF > 0 AND DATE_DIFF <= 30 THEN '2. 1-30 days'
	 WHEN DATE_DIFF > 30 AND DATE_DIFF <= 60 THEN '3. 31-60 days'
     WHEN DATE_DIFF > 60 AND DATE_DIFF <= 90 THEN '4. 61-90 days'
	 WHEN DATE_DIFF > 90 AND DATE_DIFF <= 180 THEN '5. 91-180 days'
	 WHEN DATE_DIFF > 180 AND DATE_DIFF <= 365 THEN '6. 181-365 days'
	 ELSE 'error' END AS TIME_FRAME_INVITE
,COUNT(DISTINCT PATIENT_JOIN_KEY) AS NO_PATIENTS
,COUNT(DISTINCT PATIENT_JOIN_KEY) *100.00/(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM #EC_ATTENDEE_INVITE_TIMES) AS PC_PATIENTS
FROM #EC_ATTENDEE_INVITE_TIMES
GROUP BY 
CASE WHEN DATE_DIFF = 0 THEN '1. On day'
     WHEN DATE_DIFF > 0 AND DATE_DIFF <= 30 THEN '2. 1-30 days'
	 WHEN DATE_DIFF > 30 AND DATE_DIFF <= 60 THEN '3. 31-60 days'
     WHEN DATE_DIFF > 60 AND DATE_DIFF <= 90 THEN '4. 61-90 days'
	 WHEN DATE_DIFF > 90 AND DATE_DIFF <= 180 THEN '5. 91-180 days'
	 WHEN DATE_DIFF > 180 AND DATE_DIFF <= 365 THEN '6. 181-365 days'
	 ELSE 'error' END
ORDER BY 1


---------------------------------------------------------------------
/* 4) How many invites did attendees receive before their check? */

-- descriptive stats on invites per attendee in the year preceding 
-- their check

SELECT 
MIN(NO_INVITES) AS MIN_INVITES
,AVG(NO_INVITES) AS AVG_INVITES
,MAX(NO_INVITES) AS MAX_INVITES

FROM (SELECT 
	PATIENT_JOIN_KEY
	,MAX(INVITE_NO) AS NO_INVITES
	FROM #ATTENDEE_INVITES_2
	GROUP BY PATIENT_JOIN_KEY) AS A


-- Distribution of number of invites in the year preceding a
-- completed check
-- 32.8% with no invitation
-- 50.5% received only 1 invite  
-- 13.3% received 2 invites                            
-- 3.4% received more than 2 invites                   

SELECT 
COALESCE(NO_INVITES, 0) AS NO_INVITES 
,COUNT(A.PATIENT_JOIN_KEY) AS NO_PATIENTS 
,COUNT(A.PATIENT_JOIN_KEY)*100.00/(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] 
                                    WHERE COHORT = 'ATTENDEE') AS PC_PATIENTS

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A 

LEFT JOIN (SELECT PATIENT_JOIN_KEY
			,MAX(INVITE_NO) AS NO_INVITES
			FROM #ATTENDEE_INVITES_2
			GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.COHORT = 'ATTENDEE'
GROUP BY NO_INVITES
ORDER BY 1


---------------------------------------------------------------------
/* 5) What type of invite was most likely to be recorded on the day? */

SELECT (CASE WHEN B.PATIENT_JOIN_KEY IS NOT NULL THEN 'Multiple invite types'
        ELSE INVITE_TYPE END) AS INVITE_TYPE,
       COUNT(DISTINCT A.PATIENT_JOIN_KEY) AS NO_PATIENTS,
	   COUNT(DISTINCT A.PATIENT_JOIN_KEY)*100.00/(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM #ATTENDEE_INVITES_2
												WHERE DATE_DIFF = 0
												AND INVITE_NO = 1)	    
FROM #ATTENDEE_INVITES_2 AS A 

	-- Identify patients with more than one invite type on the day of their check
LEFT JOIN (SELECT PATIENT_JOIN_KEY, COUNT(*) AS NO_INVITES
           FROM #ATTENDEE_INVITES_2
		   WHERE DATE_DIFF = 0
		   AND INVITE_NO = 1
		   GROUP BY PATIENT_JOIN_KEY
		   HAVING COUNT(*) > 1) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.DATE_DIFF = 0
AND A.INVITE_NO = 1
GROUP BY (CASE WHEN B.PATIENT_JOIN_KEY IS NOT NULL THEN 'Multiple invite types'
        ELSE INVITE_TYPE END)
ORDER BY 2 DESC

-- 51.34% verbal
-- 23.91% unspecified
-- 13.55% letter 1
-- 6.41% telephone
-- less than 5% everything else
-- 22052 multiple invite types (3%)

-- Check on multiple invites
select count(distinct pata) from 
(SELECT A.PATIENT_JOIN_KEY pata, A.INVITE_TYPE, B.NO_INVITES
FROM #ATTENDEE_INVITES_2 AS A
LEFT JOIN (SELECT PATIENT_JOIN_KEY, COUNT(*) AS NO_INVITES
           FROM #ATTENDEE_INVITES_2
		   WHERE DATE_DIFF = 0
		   AND INVITE_NO = 1
		   GROUP BY PATIENT_JOIN_KEY
		   HAVING COUNT(*) > 1) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
WHERE A.DATE_DIFF = 0
AND A.INVITE_NO = 1
AND B.PATIENT_JOIN_KEY IS NOT NULL
AND A.INVITE_TYPE = 'NHSHC invitation (unspecified)'
--Order by A.PATIENT_JOIN_KEY
) a

-- 15688
-- likely most multiple invites on same day are errors, as approx 70% of these include unspecified invitations
	

    --------------------------------------------------------------
	-- STEP 3 - NON-ATTENDEES
    --------------------------------------------------------------
---------------------------------------------------------------------
/* 1) How many non-attendees received an invite? */

-- How many non-attendees?
SELECT FIN_YEAR, 
COUNT(*)
FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
WHERE COHORT = 'NON-ATTENDEE'
GROUP BY FIN_YEAR

-- Extract non-attendees' invitations and calculate difference in days between invites and
-- their index date

DROP TABLE IF EXISTS #NON_ATTENDEE_INVITES;

SELECT A.INVITE_DATE
,A.INVITE_TYPE
,A.FIN_YEAR_INVITE
,DATEDIFF(day, CONVERT(VARCHAR, A.INVITE_DATE, 23), CONVERT(VARCHAR, B.INDEX_DATE, 23)) AS 'DATE_DIFF'
,B.*
INTO #NON_ATTENDEE_INVITES
FROM #HC_INVITES_2 AS A

INNER JOIN [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND B.COHORT = 'NON-ATTENDEE'
-- 7,746,071 rows

SELECT TOP 20 * FROM #NON_ATTENDEE_INVITES
ORDER BY PATIENT_JOIN_KEY

-- Restrict to invites in year before patient's index date
-- Label patient's invites in order

DROP TABLE IF EXISTS #NON_ATTENDEE_INVITES_2;

SELECT *
,RANK() OVER (PARTITION BY [PATIENT_JOIN_KEY] ORDER BY INVITE_DATE) AS INVITE_NO
INTO #NON_ATTENDEE_INVITES_2
FROM #NON_ATTENDEE_INVITES AS A

WHERE 
(COHORT_DETAIL LIKE '%invitation%' AND DATE_DIFF BETWEEN -365 AND 0)   -- take invite-only patient's invite date and subsequent year
OR (COHORT_DETAIL NOT LIKE '%invitation%' AND DATE_DIFF BETWEEN 0 AND 365)   -- look 1 year before for other non-attendees
-- 4,731,407 rows

SELECT TOP 20 * FROM #NON_ATTENDEE_INVITES_2
ORDER BY PATIENT_JOIN_KEY


------------- SENSE CHECKS ------------------
-- Example - patient with 3 letter invites before a declined check
SELECT * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
WHERE PATIENT_JOIN_KEY = 118

SELECT * FROM #HC_INVITES_2
WHERE PATIENT_JOIN_KEY = 118
ORDER BY INVITE_DATE

SELECT * FROM #NON_ATTENDEE_INVITES_2
WHERE PATIENT_JOIN_KEY = 118
ORDER BY INVITE_DATE

-- Example - patient with many invites then declined
SELECT * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
WHERE PATIENT_JOIN_KEY = 4320981

SELECT * FROM #HC_INVITES_2
WHERE PATIENT_JOIN_KEY = 4320981
ORDER BY INVITE_DATE

SELECT * FROM #NON_ATTENDEE_INVITES_2
WHERE PATIENT_JOIN_KEY = 4320981
ORDER BY INVITE_DATE

-- Example - patient with invites only
SELECT * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
WHERE PATIENT_JOIN_KEY = 5330084

SELECT * FROM #HC_INVITES_2
WHERE PATIENT_JOIN_KEY = 5330084
ORDER BY INVITE_DATE

SELECT * FROM #NON_ATTENDEE_INVITES_2
WHERE PATIENT_JOIN_KEY = 5330084
ORDER BY INVITE_DATE


---------------------------------------------------------------------
/* 2) What proportion of non-attendees have an invite on the day 
or in the year before their NHSHC contact (not invite-onlys)
or in the year after their NHSHC contact (invites only)

98.9%

*/

SELECT 
COUNT(A.PATIENT_JOIN_KEY) AS NO_NON_ATTENDEES
,COUNT(B.PATIENT_JOIN_KEY) AS NO_PATIENTS_WITH_INVITE
,COUNT(B.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_WITH_INVITE

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #NON_ATTENDEE_INVITES_2
		   GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.COHORT = 'NON-ATTENDEE'

-- Breakdown by financial year
SELECT 
A.FIN_YEAR
,COUNT(A.PATIENT_JOIN_KEY) AS NO_NON_ATTENDEES
,COUNT(B.PATIENT_JOIN_KEY) AS NO_PATIENTS_WITH_INVITE
,COUNT(B.PATIENT_JOIN_KEY)*100.00/COUNT(A.PATIENT_JOIN_KEY) AS PC_WITH_INVITE

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #NON_ATTENDEE_INVITES_2
		   GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.COHORT = 'NON-ATTENDEE'
GROUP BY
A.FIN_YEAR
WITH ROLLUP
ORDER BY 1

---------------------------------------------------------------------
/* 3) How many invites did non-attendees receive? */

-- descriptive stats on invites per non-attendee in the year preceding 
-- their check

SELECT 
MIN(NO_INVITES) AS MIN_INVITES
,AVG(NO_INVITES) AS AVG_INVITES
,MAX(NO_INVITES) AS MAX_INVITES

FROM (SELECT 
	PATIENT_JOIN_KEY
	,MAX(INVITE_NO) AS NO_INVITES
	FROM #NON_ATTENDEE_INVITES_2
	GROUP BY PATIENT_JOIN_KEY) AS A


-- Distribution of number of invites 

SELECT 
COALESCE(B.NO_INVITES, 0) AS NO_INVITES 
,COUNT(A.PATIENT_JOIN_KEY) AS NO_NON_ATTENDEES 
,COUNT(A.PATIENT_JOIN_KEY)*100.00/(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) 
                                   FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
								   WHERE COHORT = 'NON-ATTENDEE') AS PC_PATIENTS

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT 
				PATIENT_JOIN_KEY
				,MAX(INVITE_NO) AS NO_INVITES
				FROM #NON_ATTENDEE_INVITES_2
				GROUP BY PATIENT_JOIN_KEY) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.COHORT = 'NON-ATTENDEE'
GROUP BY NO_INVITES
ORDER BY 1


    --------------------------------------------------------------
	-- STEP 4 - COMBINE ATTENDEES, NON-ATTENDEES
    --------------------------------------------------------------

SELECT TOP 5 * FROM #ATTENDEE_INVITES_2
SELECT TOP 5 * FROM #NON_ATTENDEE_INVITES_2

/* Combine attendee and non-attendee tables.
Add label to count cases of patients receiving more than one invite on the same day */
DROP TABLE IF EXISTS #COMB_INVITES;

SELECT *
,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], INVITE_DATE ORDER BY INVITE_TYPE) AS INVITE_NO_DAY
INTO #COMB_INVITES 
FROM (SELECT * FROM #ATTENDEE_INVITES_2
      UNION
	  SELECT * FROM #NON_ATTENDEE_INVITES_2) AS X
;
-- 9,326,834 rows

-- View example patient with more than one first invite on the same day
SELECT * FROM #COMB_INVITES
WHERE PATIENT_JOIN_KEY = 750
ORDER BY INVITE_DATE


-- Calculate number of invitees by first invite type
-- (identify cases of patients with multiple first invites on the same day)

-- Breakdown by cohort
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_INVITES_BY_YEAR];

SELECT 
A.FIN_YEAR
,A.COHORT
,CASE WHEN B.INVITE_TYPE IS NULL THEN 'No invitation recorded'
      WHEN C.PATIENT_JOIN_KEY IS NOT NULL THEN 'Multiple invitation types'
      WHEN B.INVITE_TYPE LIKE '%letter%' THEN 'NHSHC invitation - letter'
      ELSE B.INVITE_TYPE END AS INVITE_TYPE
,COUNT(DISTINCT A.PATIENT_JOIN_KEY) AS NO_PATIENTS

INTO [NHS_Health_Checks].[dbo].[EC_INVITES_BY_YEAR]

FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] AS A

LEFT JOIN (SELECT * FROM #COMB_INVITES
           WHERE INVITE_NO = 1) AS B    -- restrict to first invite
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

LEFT JOIN (SELECT PATIENT_JOIN_KEY 
           FROM #COMB_INVITES
		   WHERE INVITE_NO_DAY > 1 
		   AND INVITE_NO = 1
		   GROUP BY PATIENT_JOIN_KEY) AS C  -- patients with more than one first invite on the same day
ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY

GROUP BY
A.FIN_YEAR
,A.COHORT
,CASE WHEN B.INVITE_TYPE IS NULL THEN 'No invitation recorded'
      WHEN C.PATIENT_JOIN_KEY IS NOT NULL THEN 'Multiple invitation types'
      WHEN B.INVITE_TYPE LIKE '%letter%' THEN 'NHSHC invitation - letter'
      ELSE B.INVITE_TYPE END 
ORDER BY 1,2,4 DESC
;

-- View data
SELECT * FROM [NHS_Health_Checks].[dbo].[EC_INVITES_BY_YEAR]
ORDER BY 1,2,4 DESC;

-- Check counts
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM #COMB_INVITES
