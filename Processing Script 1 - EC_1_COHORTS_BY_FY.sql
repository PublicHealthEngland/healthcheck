--------------------------------------------
--------------------------------------------

/* SCRIPT 1 - IDENTIFYING NHSHC ATTENDEES AND NON-ATTENDEES 
BY FINANCIAL YEAR 
1/4/2012 - 31/3/2018 (6 years)
*/

--Last updated:
--6/6/2019
--Emma Clegg

-- Script logic:
 
-- *** PART 1 ***
   -- STEP 1 - Extract patients' ethnicity from journals table
   -- STEP 2 - Extract NHSHC contacts for each patient
	   -- a) Search and create list of NHSHC read codes 
	   -- b) Extract all patients' NHSHC contact points
	   -- c) Add financial year labelling, and estimate patient's age at 
       -- time of NHSHC contact
    -- STEP 3 - Suppress conflicting HCP type entries
	-- STEP 4 - Identify patients inappropriate for NHSHC
	-- STEP 5 - Identify attendees by financial year
	-- STEP 6 - Identify NHSHC declined patients by financial year
	-- STEP 7 - Identify NHSHC DNA patients by financial year
	-- STEP 8 - Identify commenced only by financial year
	-- STEP 9 - Identify invite only patients by financial year
	-- STEP 10 - Combine in single table, add underage flag
	-- STEP 11 - Add flag for first/second valid checks
	-- STEP 12 - Save attendees/non-attendees as permanent table

-- *** PART 2 ***
	-- STEP 1 - Output attendee/non-attendee volumes
	-- STEP 2 - Sense checks

------------------------------------------------------------------------------
-- Script uses:
   -- 1) LSOA to higher geography lookup table:
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[vLKP_LSOA11]

   -- 2) LSOA IMD deprivation lookup
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[vSocioDemog_LSOA11]

   -- 3) Cleaned patients table
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]

   -- 4) Cleaned journals table
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]

   -- 5) GP Practice to CCG lookup
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[GP_PRACTICE_LOOKUP]

   -- 6) Read code lookup table
   -- SELECT * FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]

   -- 7) Lookup table for cluster key to ethnic group categories
   -- SELECT * FROM [NHS_Health_Checks].[dbo].[EC_ETHNICITY_LOOKUP] 

-- Script produces:
   -- Table of attendees/non-attendees by financial year
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]

/*****************************************************************************/
 

 ------------------------------------------------------------------------------------------------------
-- PART 1 - TABLE PRODUCTION
------------------------------------------------------------------------------------------------------
   
    --------------------------------------------------------------
	-- STEP 1 - Extract patients' journals table ethnicity
    --------------------------------------------------------------

-- 1) Extract journals table ethnic records
DROP TABLE IF EXISTS #ETHNICITY_RECORDS

SELECT 
	 A.[PATIENT_JOIN_KEY]
    ,COALESCE(A.[DATE], '1900-01-01') AS 'DATE'
	,B.[ETHNIC_CODE]
INTO  #ETHNICITY_RECORDS
FROM  [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]  AS A

INNER JOIN [NHS_Health_Checks].[dbo].[EC_ETHNICITY_LOOKUP]  AS B
ON A.[CLUSTER_JOIN_KEY] = B.[CLUSTER_JOIN_KEY]

WHERE 
	B.[ETHNIC_CODE] NOT IN ('-')   -- exclude cluster keys which can't be matched to an ethnic code
GROUP BY 
	 A.[PATIENT_JOIN_KEY]
    ,COALESCE(A.[DATE], '1900-01-01')
	,B.[ETHNIC_CODE]
-- 10,076,285 rows


-- 2) Identify the latest date that an ethnicity category for each patient was assigned
-- (results in one record per unique patient)
DROP TABLE IF EXISTS #ETHNICITY_RECORDS2

SELECT
	[PATIENT_JOIN_KEY]
	,MAX([DATE]) AS 'LATEST_DATE'
INTO #ETHNICITY_RECORDS2
FROM #ETHNICITY_RECORDS
GROUP BY [PATIENT_JOIN_KEY]
--10,051,788 rows


-- 3) Identify the latest ethnicity category at the latest date for each patient
DROP TABLE IF EXISTS #LATEST_ETHNICITY_CODE 

SELECT 
	 A.*
	,B.[ETHNIC_CODE]
INTO #LATEST_ETHNICITY_CODE
FROM #ETHNICITY_RECORDS2 AS A

LEFT JOIN #ETHNICITY_RECORDS AS B
ON A.[PATIENT_JOIN_KEY] = B.[PATIENT_JOIN_KEY]
AND A.LATEST_DATE = B.[DATE] 
--10,064,229 rows


-- 4) Identify patients with only one latest ethnic category
DROP TABLE IF EXISTS #ONE_LATEST_CODE

SELECT
	A.[PATIENT_JOIN_KEY]
	,COUNT(*) AS 'Number_of_codes'
INTO #ONE_LATEST_CODE
FROM #LATEST_ETHNICITY_CODE AS A

GROUP BY 
	A.[PATIENT_JOIN_KEY]
HAVING COUNT(*) = 1
-- 10,039,411 rows


SELECT TOP 10
	A.[PATIENT_JOIN_KEY]
	,COUNT(*) AS 'Number_of_codes'
FROM #LATEST_ETHNICITY_CODE AS A

GROUP BY 
	A.[PATIENT_JOIN_KEY]
HAVING COUNT(*) > 1

-- 5) Create table of patients with only one latest code
DROP TABLE IF EXISTS #FINAL_ETHNICITY_CODE

SELECT A.*
INTO #FINAL_ETHNICITY_CODE
FROM #LATEST_ETHNICITY_CODE AS A
INNER JOIN #ONE_LATEST_CODE AS B
ON A.[PATIENT_JOIN_KEY] = B.[PATIENT_JOIN_KEY]
-- 10,039,411 rows


-- Example patient with ethnicty record but NULL date
SELECT * FROM #ETHNICITY_RECORDS
WHERE PATIENT_JOIN_KEY = 7006115

SELECT * FROM #FINAL_ETHNICITY_CODE
WHERE PATIENT_JOIN_KEY = 7006115

-- Look at patient with two codes recorded on the same day
SELECT * FROM #ETHNICITY_RECORDS
WHERE PATIENT_JOIN_KEY = 1372340

SELECT * FROM #FINAL_ETHNICITY_CODE
WHERE PATIENT_JOIN_KEY = 1372340


    --------------------------------------------------------------
	-- STEP 2 - Extract NHSHC contacts for each patient
    --------------------------------------------------------------

/* a) Extract and label list of NHSHC read codes from GP read code
lookup table */
DROP TABLE IF EXISTS #NHSHC_CONTACT_CLUSTERS;

SELECT CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,ROW_NUMBER() OVER(PARTITION BY A.CLUSTER_JOIN_KEY ORDER BY A.CLUSTER_DESCRIPTION) as 'NO_LABELS'
	,CASE WHEN A.CODE_DESCRIPTION = 'NHS Health Check declined' THEN 'NHSHC declined'
		  WHEN A.CODE_DESCRIPTION = 'Did not attend NHS Health Check' THEN 'NHSHC not attended'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check not appropriate' THEN 'NHSHC inappropriate'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check commenced' THEN 'NHSHC commenced'

		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check completed' THEN 'NHSHC completed'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check completed by third party' THEN 'NHSHC completed third party'

		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation' THEN 'NHSHC invitation'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation email' THEN 'NHSHC invitation - email'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation first letter' THEN 'NHSHC invitation - letter 1'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation second letter' THEN 'NHSHC invitation - letter 2'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation third letter' THEN 'NHSHC invitation - letter 3'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation short message service text message' THEN 'NHSHC invitation - text'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check telephone invitation' THEN 'NHSHC invitation - telephone'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check verbal invitation' THEN 'NHSHC invitation - verbal'

		  ELSE 'Other' END AS CONTACT_TYPE 
INTO #NHSHC_CONTACT_CLUSTERS 
FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF] AS A 
WHERE ((CLUSTER_DESCRIPTION LIKE '%NHS Health Check%'
	OR CLUSTER_DESCRIPTION LIKE '%NHS Health Check%')
	AND CODE_DESCRIPTION NOT LIKE '%dementia%')    -- exclude NHSHC dementia referral codes
GROUP BY CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,CASE WHEN A.CODE_DESCRIPTION = 'NHS Health Check declined' THEN 'NHSHC declined'
		  WHEN A.CODE_DESCRIPTION = 'Did not attend NHS Health Check' THEN 'NHSHC not attended'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check not appropriate' THEN 'NHSHC inappropriate'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check commenced' THEN 'NHSHC commenced'

		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check completed' THEN 'NHSHC completed'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check completed by third party' THEN 'NHSHC completed third party'

		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation' THEN 'NHSHC invitation'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation email' THEN 'NHSHC invitation - email'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation first letter' THEN 'NHSHC invitation - letter 1'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation second letter' THEN 'NHSHC invitation - letter 2'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation third letter' THEN 'NHSHC invitation - letter 3'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check invitation short message service text message' THEN 'NHSHC invitation - text'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check telephone invitation' THEN 'NHSHC invitation - telephone'
		  WHEN A.CODE_DESCRIPTION = 'NHS Health Check verbal invitation' THEN 'NHSHC invitation - verbal'

		  --WHEN A.CLUSTER_DESCRIPTION = 'NHS Health Check invitation codes' THEN 'NHSHC invitation'
		  ELSE 'Other' END;

-- View read codes and descriptions
SELECT * FROM #NHSHC_CONTACT_CLUSTERS
ORDER BY 2,3;


/* b) Extract records for patients' NHSHC contacts:
invitation, declined, did not attend, commenced, completed (period: 1/4/12 - 31/3/18)
inappropriate (whole extract)
 */
 
DROP TABLE IF EXISTS #HC_CONTACTS;

SELECT
    A.[PATIENT_JOIN_KEY]
    ,CASE WHEN A.HCP_TYPE IN (' ', '?') THEN NULL 
	      ELSE A.HCP_TYPE END AS HCP_TYPE
    ,C.[PRACTICE_ID]
    ,C.[SUPPLIER_NAME]
    ,C.[YEAR_OF_BIRTH]
    ,C.[SEX]
	,C.[LSOA] AS LSOA_PATIENT
    ,C.[YEAR_OF_DEATH]
    ,COALESCE(C.[ETHNIC], J.[ETHNIC_CODE]) AS ETHNIC   -- take patients table ethnicity in priority, otherwise latest journals one
    ,C.[REGISTERED_DATE]
    ,C.[FIRST_LANGUAGE]
	  -- patients' geography information
	,COALESCE(E.[UTLAApr19CD], 'Unknown') AS UTLA_CODE_PAT
	,COALESCE(E.[UTLAApr19NM], 'Unknown') AS UTLA_PAT
	,COALESCE(E.PHEC15CD, 'Unknown') AS PHE_CENTRE_CODE_PAT
	,COALESCE(E.PHEC15NM, 'Unknown') AS PHE_CENTRE_PAT
	,F.[IMD_EngDecile_2015] AS IMD_ENG_DECILE_PAT
	,F.[IMD_EngQuintile_2015] AS IMD_ENG_QUINTILE_PAT
	,F.[IMD_LTLAQuintile_2015] AS IMD_LTLA_QUINTILE_PAT
	  -- GP practices' geography information
	,COALESCE(D.LSOA, 'Unknown') AS LSOA_GP
	,COALESCE(G.[UTLAApr19CD], 'Unknown') AS UTLA_CODE_GP
	,COALESCE(G.[UTLAApr19NM], 'Unknown') AS UTLA_GP
	,H.[IMD_EngDecile_2015] AS IMD_ENG_DECILE_GP
	,COALESCE(D.CCG_ONS_CODE, 'Unknown') AS CCG_CODE_GP
	,COALESCE(D.CCG_NAME, 'Unknown') AS CCG_GP
	,B.CONTACT_TYPE
	,A.[DATE] AS INDEX_DATE 

 INTO #HC_CONTACTS
 FROM  [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]  AS A

 INNER JOIN #NHSHC_CONTACT_CLUSTERS AS B           -- keep NHSHC contact records only
 ON A.CLUSTER_JOIN_KEY = B.CLUSTER_JOIN_KEY 
 AND B.NO_LABELS = 1  -- Restrict to one record description per cluster join key

 INNER JOIN [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED] AS C -- keep ref population only
 ON A.[PATIENT_JOIN_KEY] = C.[PATIENT_JOIN_KEY]

 LEFT JOIN [NHS_Health_Checks].[dbo].[GP_PRACTICE_LOOKUP] AS D -- join on GP practices' LSOAs
 ON C.PRACTICE_ID = D.PRACTICE_ID

    -- Extract geographies based on patient's LSOA
 LEFT JOIN [NHS_Health_Checks].[dbo].[vLKP_LSOA11] AS E  -- find patient's UTLA and PHE Centre from their LSOA
 ON C.LSOA = E.LSOA11CD

 LEFT JOIN [NHS_Health_Checks].[dbo].[vSocioDemog_LSOA11] AS F  -- join on patient's IMD deprivation information
 ON C.LSOA = F.LSOA11CD

     -- Extract geographies based on GP's LSOA
 LEFT JOIN [NHS_Health_Checks].[dbo].[vLKP_LSOA11] AS G  -- find GP's UTLA from their LSOA
 ON D.LSOA = G.LSOA11CD

  LEFT JOIN [NHS_Health_Checks].[dbo].[vSocioDemog_LSOA11] AS H  -- join on GP's IMD deprivation information
 ON D.LSOA = H.LSOA11CD
  
	-- Join patient's journals table ethnicity
 LEFT JOIN #FINAL_ETHNICITY_CODE AS J
 ON A.PATIENT_JOIN_KEY = J.PATIENT_JOIN_KEY

 WHERE A.[DATE] IS NOT NULL 
 AND ((A.[DATE] >= '2012-04-01'    -- restrict NHSHC contact dates to 6 year time period of interest
	  AND A.[DATE] <= '2018-03-31')
	  OR B.CONTACT_TYPE = 'NHSHC inappropriate')  -- extract all "inappropriate" recordings however as we want to 
	                                              -- exclude these patients from entire analysis
									 
GROUP BY 
    A.[PATIENT_JOIN_KEY]
    ,CASE WHEN A.HCP_TYPE IN (' ', '?') THEN NULL 
	      ELSE A.HCP_TYPE END
    ,C.[PRACTICE_ID]
    ,C.[SUPPLIER_NAME]
    ,C.[YEAR_OF_BIRTH]
    ,C.[SEX]
    ,C.[LSOA]
    ,C.[YEAR_OF_DEATH]
    ,COALESCE(C.[ETHNIC], J.[ETHNIC_CODE])
    ,C.[REGISTERED_DATE]
    ,C.[FIRST_LANGUAGE]
	,COALESCE(E.[UTLAApr19CD], 'Unknown')
	,COALESCE(E.[UTLAApr19NM], 'Unknown') 
	,COALESCE(E.PHEC15CD, 'Unknown')
	,COALESCE(E.PHEC15NM, 'Unknown')
	,F.[IMD_EngDecile_2015]
	,F.[IMD_EngQuintile_2015]
	,F.[IMD_LTLAQuintile_2015] 
	,COALESCE(D.LSOA, 'Unknown') 
	,COALESCE(G.[UTLAApr19CD], 'Unknown') 
	,COALESCE(G.[UTLAApr19NM], 'Unknown')
	,H.[IMD_EngDecile_2015]
	,COALESCE(D.CCG_ONS_CODE, 'Unknown') 
	,COALESCE(D.CCG_NAME, 'Unknown') 
	,B.CONTACT_TYPE
	,A.[DATE] 
;
-- 24,000,219 rows
-- 1 min


/* c) Add financial year labelling, and estimate patient's age at 
time of NHSHC contact */

DROP TABLE IF EXISTS #HC_CONTACTS_2;

SELECT *
       -- Add financial year of NHSHC contact date
	,CASE WHEN A.[INDEX_DATE] >= '2017-04-01' AND A.[INDEX_DATE] <= '2018-03-31' THEN '2017/18'
     WHEN A.[INDEX_DATE] >= '2016-04-01' AND A.[INDEX_DATE] <= '2017-03-31' THEN '2016/17'
	 WHEN A.[INDEX_DATE] >= '2015-04-01' AND A.[INDEX_DATE] <= '2016-03-31' THEN '2015/16'
	 WHEN A.[INDEX_DATE] >= '2014-04-01' AND A.[INDEX_DATE] <= '2015-03-31' THEN '2014/15'
	 WHEN A.[INDEX_DATE] >= '2013-04-01' AND A.[INDEX_DATE] <= '2014-03-31' THEN '2013/14'
	 WHEN A.[INDEX_DATE] >= '2012-04-01' AND A.[INDEX_DATE] <= '2013-03-31' THEN '2012/13'
	 END AS 'FIN_YEAR'
	   -- Estimate patient's age at time of NHSHC contact based on their year of birth *** UPDATED JUL19 ***
    ,CASE WHEN YEAR(A.[INDEX_DATE]) - A.[YEAR_OF_BIRTH] IS NULL THEN NULL
          ELSE YEAR(A.[INDEX_DATE]) - A.[YEAR_OF_BIRTH] END AS 'AGE'
INTO #HC_CONTACTS_2
FROM #HC_CONTACTS AS A ;
-- 24,000,219 rows



    --------------------------------------------------------------
	-- STEP 3 - Suppress conflicting HCP type entries
    --------------------------------------------------------------

-- Take one record only for patients with more than one HCP type 
-- recorded on the same day for the same contact type

-- Create new table with one record taken in each of these cases
DROP TABLE IF EXISTS #MULTIPLE_HCP_TYPE;

SELECT
    [PATIENT_JOIN_KEY]
	,CONTACT_TYPE
	,INDEX_DATE 
    ,COUNT(*) AS NO_HCP_TYPE
	INTO #MULTIPLE_HCP_TYPE
	FROM #HC_CONTACTS_2
	WHERE HCP_TYPE IS NOT NULL  -- enter valid HCP types here
	GROUP BY
	 [PATIENT_JOIN_KEY]
	,CONTACT_TYPE
	,INDEX_DATE 
	HAVING COUNT(*) > 1
	;
-- 29,405 rows

-- Update NHSHC contacts table, suppressing HCP entries for the
-- patients with multiple HCP types recorded
DROP TABLE IF EXISTS #HC_CONTACTS_3;

SELECT 	 A.[PATIENT_JOIN_KEY]
    ,A.[HCP_TYPE_EDITED] AS HCP_TYPE
    ,A.[PRACTICE_ID]
    ,A.[SUPPLIER_NAME]
    ,A.[YEAR_OF_BIRTH]
    ,A.[SEX]
	,A.[LSOA_PATIENT]
    ,A.[YEAR_OF_DEATH]
    ,A.[ETHNIC]
    ,A.[REGISTERED_DATE]
    ,A.[FIRST_LANGUAGE]
	,A.UTLA_CODE_PAT
	,A.UTLA_PAT
	,A.PHE_CENTRE_CODE_PAT
	,A.PHE_CENTRE_PAT
	,A.IMD_ENG_DECILE_PAT
	,A.IMD_ENG_QUINTILE_PAT
	,A.IMD_LTLA_QUINTILE_PAT
	,A.LSOA_GP
	,A.UTLA_CODE_GP
	,A.UTLA_GP
	,A.IMD_ENG_DECILE_GP
	,A.CCG_CODE_GP
	,A.CCG_GP
	,A.CONTACT_TYPE
	,A.INDEX_DATE 
	,A.FIN_YEAR 
	,A.AGE
INTO #HC_CONTACTS_3
FROM 
	(SELECT A.*
		,CASE WHEN B.PATIENT_JOIN_KEY IS NOT NULL THEN NULL 
		 ELSE A.HCP_TYPE END AS HCP_TYPE_EDITED
		,ROW_NUMBER() OVER(PARTITION BY A.[PATIENT_JOIN_KEY], A.[CONTACT_TYPE], A.[INDEX_DATE] ORDER BY (CASE WHEN B.PATIENT_JOIN_KEY IS NOT NULL THEN NULL 
																											ELSE A.HCP_TYPE END) DESC) as 'ORDER_HCP_TYPE'
		FROM #HC_CONTACTS_2 AS A 
		LEFT JOIN (SELECT PATIENT_JOIN_KEY,
						  CONTACT_TYPE,
						  INDEX_DATE
				   FROM #MULTIPLE_HCP_TYPE
				   GROUP BY PATIENT_JOIN_KEY,
							CONTACT_TYPE,
							INDEX_DATE) AS B
		ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
		AND A.CONTACT_TYPE = B.CONTACT_TYPE
		AND A.INDEX_DATE = B.INDEX_DATE) AS A

WHERE ORDER_HCP_TYPE = 1

GROUP BY
A.[PATIENT_JOIN_KEY]
    ,A.[HCP_TYPE_EDITED] 
    ,A.[PRACTICE_ID]
    ,A.[SUPPLIER_NAME]
    ,A.[YEAR_OF_BIRTH]
    ,A.[SEX]
	,A.[LSOA_PATIENT]
    ,A.[YEAR_OF_DEATH]
    ,A.[ETHNIC]
    ,A.[REGISTERED_DATE]
    ,A.[FIRST_LANGUAGE]
	,A.UTLA_CODE_PAT
	,A.UTLA_PAT
	,A.PHE_CENTRE_CODE_PAT
	,A.PHE_CENTRE_PAT
	,A.IMD_ENG_DECILE_PAT
	,A.IMD_ENG_QUINTILE_PAT
	,A.IMD_LTLA_QUINTILE_PAT
	,A.LSOA_GP
	,A.UTLA_CODE_GP
	,A.UTLA_GP
	,A.IMD_ENG_DECILE_GP
	,A.CCG_CODE_GP
	,A.CCG_GP
	,A.CONTACT_TYPE
	,A.INDEX_DATE 
	,A.FIN_YEAR 
	,A.AGE
;
-- 23,873,305 rows

-- Drop intermediary tables
DROP TABLE IF EXISTS #HC_CONTACTS
DROP TABLE IF EXISTS #HC_CONTACTS_2


    --------------------------------------------------------------
	-- STEP 4 - Identify patients inappropriate for NHSHC
    --------------------------------------------------------------

/* Identify patients marked as inappropriate for a NHSHC in our
data extract - we will exclude these patients from analysis */

 DROP TABLE IF EXISTS #HC_INAPPR;

 SELECT
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,MIN(A.[INDEX_DATE]) AS 'INDEX_DATE'
	,A.CONTACT_TYPE
 INTO #HC_INAPPR
 FROM #HC_CONTACTS_3 AS A

 WHERE CONTACT_TYPE = 'NHSHC inappropriate'
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.CONTACT_TYPE;
-- 18,720 rows


/* Check inappropriate counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_INAPPR
GROUP BY FIN_YEAR
ORDER BY 1;

-- Check patient count so far
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) AS NO_PATIENTS
FROM #HC_CONTACTS_3
WHERE FIN_YEAR IS NOT NULL AND FIN_YEAR <> '2017/18'
AND PATIENT_JOIN_KEY NOT IN (SELECT PATIENT_JOIN_KEY FROM #HC_INAPPR)

    --------------------------------------------------------------
	-- STEP 5 - Identify attendees by financial year
    --------------------------------------------------------------

/* Identify attendees by financial year - take date of each patient's
earliest completed check as the NHSHC event "index date"  */

 DROP TABLE IF EXISTS #HC_ATTENDEES_BY_YEAR;

 SELECT
 	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.INDEX_DATE
	,A.CONTACT_TYPE
 INTO #HC_ATTENDEES_BY_YEAR

 FROM 
     (SELECT * 
	      -- order by INDEX_DATE to take patient's earliest completed check in period,
		  -- then CONTACT_TYPE descending to prioritise a NHSHC completed third party record if present
	   ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY], FIN_YEAR ORDER BY INDEX_DATE, CONTACT_TYPE DESC) as 'ORDER_NHSHC'
	  FROM #HC_CONTACTS_3
	  WHERE CONTACT_TYPE IN ('NHSHC completed', 'NHSHC completed third party')
	  ) AS A

 -- join on inappropriate patients
FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
		 FROM #HC_INAPPR 
		 GROUP BY PATIENT_JOIN_KEY ) AS B
 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

 WHERE A.ORDER_NHSHC = 1          -- keep one completed NHSHC per patient per year
 AND B.PATIENT_JOIN_KEY IS NULL   -- exclude inappropriate patients
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.INDEX_DATE
	,A.CONTACT_TYPE;
-- 6,692,291 rows

/* Check attendee counts by financial year */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_ATTENDEES_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;


    --------------------------------------------------------------
	-- STEP 6 - Identify declined by financial year
    --------------------------------------------------------------

     -- Identify declines by financial year
	 -- take earliest contact date in the financial year as "index date"

 DROP TABLE IF EXISTS #HC_DECLINED_BY_YEAR;

 SELECT
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE
 INTO #HC_DECLINED_BY_YEAR

 FROM 
     (SELECT *  -- order by INDEX_DATE to take patient's earliest contact in period
	   ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR] ORDER BY INDEX_DATE) as 'ORDER_NHSHC'
	  FROM #HC_CONTACTS_3
	  WHERE CONTACT_TYPE IN ('NHSHC declined')
	  ) AS A 

   -- join on inappropriates
FULL JOIN
 (SELECT PATIENT_JOIN_KEY 
		 FROM #HC_INAPPR 
		 GROUP BY PATIENT_JOIN_KEY ) AS B
 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

  -- join on attendees
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_ATTENDEES_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS C
 ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = C.FIN_YEAR

 WHERE  
 A.ORDER_NHSHC = 1              -- keep first NHSHC non-attendee event per patient per year 
 AND B.PATIENT_JOIN_KEY IS NULL -- exclude NHSHC inappropriates
 AND C.PATIENT_JOIN_KEY IS NULL -- exclude NHSHC attendees
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE;
-- 294,775 rows

/* Check declined counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_DECLINED_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;



    --------------------------------------------------------------
	-- STEP 7 - Identify did not attends by financial year
    --------------------------------------------------------------

     -- Identify did not attends by financial year
	 -- take earliest contact date in the financial year as "index date"

 DROP TABLE IF EXISTS #HC_DNA_BY_YEAR;

 SELECT
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE
 INTO #HC_DNA_BY_YEAR

 FROM 
     (SELECT *  -- order by INDEX_DATE to take patient's earliest contact in period
	   ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR] ORDER BY INDEX_DATE) as 'ORDER_NHSHC'
	  FROM #HC_CONTACTS_3
	  WHERE CONTACT_TYPE IN ('NHSHC not attended')
	  ) AS A 

   -- join on inappropriates
FULL JOIN
 (SELECT PATIENT_JOIN_KEY 
		 FROM #HC_INAPPR 
		 GROUP BY PATIENT_JOIN_KEY ) AS C
 ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY

   -- join on attendees
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_ATTENDEES_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS B
 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = B.FIN_YEAR

   -- join on declined
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_DECLINED_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS D
 ON A.PATIENT_JOIN_KEY = D.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = D.FIN_YEAR

 WHERE  
 A.ORDER_NHSHC = 1              -- keep first NHSHC non-attendee event per patient per year 
 AND B.PATIENT_JOIN_KEY IS NULL -- exclude NHSHC attendees
 AND C.PATIENT_JOIN_KEY IS NULL -- exclude NHSHC inappropriates
 AND D.PATIENT_JOIN_KEY IS NULL -- exclude NHSHC declined
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE;
-- 70,302 rows

/* Check DNA counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_DNA_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;


    --------------------------------------------------------------
	-- STEP 8 - Identify commenced only by financial year
    --------------------------------------------------------------

    -- Identify patients with commenced checks only
	-- take earliest invite date in the financial year as "index date" 

DROP TABLE IF EXISTS #HC_COMMENCED_BY_YEAR;

SELECT
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE
 INTO #HC_COMMENCED_BY_YEAR
 FROM       -- order by INDEX_DATE to take patient's earliest contact in period
     (SELECT * 
	   ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR] ORDER BY INDEX_DATE) as 'ORDER_NHSHC'
	  FROM #HC_CONTACTS_3
	  WHERE CONTACT_TYPE = 'NHSHC commenced'
	  AND [INDEX_DATE] >= '2015-01-01'    -- exclude commenced codes before 2015 (code not introduced then)
	  ) AS A 

 -- join on inappropriates
FULL JOIN(SELECT PATIENT_JOIN_KEY 
			 FROM #HC_INAPPR 
			 GROUP BY PATIENT_JOIN_KEY ) AS B
 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

 -- join on attendees
FULL JOIN(SELECT PATIENT_JOIN_KEY 
			 ,FIN_YEAR
			 FROM #HC_ATTENDEES_BY_YEAR 
			 GROUP BY 
			 PATIENT_JOIN_KEY 
			 ,FIN_YEAR) AS C
 ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = C.FIN_YEAR

   -- join on declined
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_DECLINED_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS D
 ON A.PATIENT_JOIN_KEY = D.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = D.FIN_YEAR

    -- join on DNAs
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_DNA_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS E
 ON A.PATIENT_JOIN_KEY = E.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = E.FIN_YEAR

 WHERE  
 A.ORDER_NHSHC = 1               -- keep first NHSHC invitation event per patient per year 
 AND B.PATIENT_JOIN_KEY IS NULL  -- exclude inappropriates
 AND C.PATIENT_JOIN_KEY IS NULL  -- exclude attendees
 AND D.PATIENT_JOIN_KEY IS NULL  -- exclude declined
 AND E.PATIENT_JOIN_KEY IS NULL  -- exclude DNAs
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR 
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE;
-- 3,106 records

/* Check commenced patient counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_COMMENCED_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;

/* Set TIME WINDOW in months for a patient to have acted on a check 
(8 weeks here) */
DECLARE @WEEKS_AFTER_COMMENCED INT
SET @WEEKS_AFTER_COMMENCED = 8

/* Create table of patients who just commenced in a FY, but
then had some follow up (non-invite) contact in the next 6 months.
i.e. this will ensure patients that were invited at the end of a 
financial year are not incorrectly labelled as non-attendees */
DROP TABLE IF EXISTS #COMMENCED_WITH_FOLLOW_UP;

  SELECT 
           A.PATIENT_JOIN_KEY
		   ,A.FIN_YEAR
		   ,A.INDEX_DATE AS INVITE_DATE
		   ,B.[INDEX_DATE] AS FOLLOW_UP_DATE
		   ,B.CONTACT_TYPE
		   INTO #COMMENCED_WITH_FOLLOW_UP
		   FROM #HC_COMMENCED_BY_YEAR AS A

		   LEFT JOIN #HC_CONTACTS_3 AS B  -- join on non-invite NHSHC events for each patient
		   ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
		   AND B.CONTACT_TYPE NOT LIKE '%NHSHC invitation%'
		   AND B.CONTACT_TYPE <> 'NHSHC commenced'

		   WHERE B.INDEX_DATE >= A.INDEX_DATE -- look for follow up events in 6 months following invite
		   AND B.INDEX_DATE <= DATEADD(WEEK, @WEEKS_AFTER_COMMENCED, A.INDEX_DATE) 
		   GROUP BY
           A.PATIENT_JOIN_KEY
		   ,A.FIN_YEAR
		   ,A.[INDEX_DATE]
		   ,B.INDEX_DATE
		   ,B.CONTACT_TYPE ;
	-- 81 records

     -- c) Compile final table of patients commenced with no
	 --  follow up within 8 weeks

DROP TABLE IF EXISTS #HC_COMMENCED_NOFOLLOWUP_BY_YEAR;

SELECT *
INTO #HC_COMMENCED_NOFOLLOWUP_BY_YEAR
FROM (
	SELECT A.*
	 FROM #HC_COMMENCED_BY_YEAR AS A
	 LEFT JOIN (SELECT PATIENT_JOIN_KEY 
					   ,FIN_YEAR 
				FROM #COMMENCED_WITH_FOLLOW_UP 
				GROUP BY PATIENT_JOIN_KEY 
					   ,FIN_YEAR ) AS B
	 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
	 AND A.FIN_YEAR = B.FIN_YEAR

	 WHERE B.PATIENT_JOIN_KEY IS NULL -- exclude patients with follow up within 8 weeks
	) AS X;
-- 3,025 records

/* Check commenced only counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_COMMENCED_NOFOLLOWUP_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;

;

    --------------------------------------------------------------
	-- STEP 9 - Identify invite only by financial year
    --------------------------------------------------------------

    -- Identify patients with invites only
	-- take earliest invite date in the financial year as "index date" 

-- Extract patients' earliest invite type
DROP TABLE IF EXISTS #FIRST_INVITE;

SELECT * 
INTO #FIRST_INVITE
FROM
(SELECT *  -- order by INDEX_DATE to take patient's earliest contact in period
	 		    -- then CONTACT_TYPE descending to prioritise a non-generic NHSHC invitation record if present
	   ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY], FIN_YEAR ORDER BY INDEX_DATE, CONTACT_TYPE DESC) as 'ORDER_NHSHC'
	  FROM #HC_CONTACTS_3
	  WHERE CONTACT_TYPE LIKE '%NHSHC invitation%'
	  ) AS A
WHERE ORDER_NHSHC = 1   -- keep first NHSHC invitation event per patient per year 
;
-- 12,563,717 rows


-- Identify patients whose only contact in a financial year was an 
-- NHSHC invite
DROP TABLE IF EXISTS #HC_INVITE_ONLY_BY_YEAR;

SELECT
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE
 INTO #HC_INVITE_ONLY_BY_YEAR
 FROM #FIRST_INVITE AS A 

 -- join on inappropriates
FULL JOIN(SELECT PATIENT_JOIN_KEY 
			 FROM #HC_INAPPR 
			 GROUP BY PATIENT_JOIN_KEY ) AS C
 ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY

  -- join on attendees
FULL JOIN(SELECT PATIENT_JOIN_KEY 
			 ,FIN_YEAR
			 FROM #HC_ATTENDEES_BY_YEAR 
			 GROUP BY 
			 PATIENT_JOIN_KEY 
			 ,FIN_YEAR) AS B
 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = B.FIN_YEAR

   -- join on declined
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_DECLINED_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS D
 ON A.PATIENT_JOIN_KEY = D.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = D.FIN_YEAR

    -- join on DNAs
 FULL JOIN 
 (SELECT PATIENT_JOIN_KEY 
         ,FIN_YEAR 
		 FROM #HC_DNA_BY_YEAR 
		 GROUP BY 
		 PATIENT_JOIN_KEY 
         ,FIN_YEAR) AS E
 ON A.PATIENT_JOIN_KEY = E.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = E.FIN_YEAR

   -- join on commenced no follow up
FULL JOIN (SELECT PATIENT_JOIN_KEY 
			 ,FIN_YEAR 
			 FROM #HC_COMMENCED_NOFOLLOWUP_BY_YEAR 
			 GROUP BY 
			 PATIENT_JOIN_KEY 
			 ,FIN_YEAR) AS F
 ON A.PATIENT_JOIN_KEY = F.PATIENT_JOIN_KEY
 AND A.FIN_YEAR = F.FIN_YEAR

 WHERE  
B.PATIENT_JOIN_KEY IS NULL  -- exclude attendees
 AND C.PATIENT_JOIN_KEY IS NULL  -- exclude inappropriates
 AND D.PATIENT_JOIN_KEY IS NULL  -- exclude declined
 AND E.PATIENT_JOIN_KEY IS NULL  -- exclude DNAs
 AND F.PATIENT_JOIN_KEY IS NULL  -- exclude commenced
 GROUP BY
	 A.[PATIENT_JOIN_KEY]
	,A.FIN_YEAR 
	,A.[INDEX_DATE]
	,A.CONTACT_TYPE;
-- 8,228,979 rows

/* Check invite only patient counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_INVITE_ONLY_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;

/* Set TIME WINDOW in months for a patient to have accepted a check 
(6 months here) */
DECLARE @MONTHS_AFTER_INVITE INT
SET @MONTHS_AFTER_INVITE = 6

/* Create table of patients who had just an invite in a FY, but
then had some follow up (non-invite) contact in the next 6 months.
i.e. this will ensure patients that were invited at the end of a 
financial year are not incorrectly labelled as non-attendees */
DROP TABLE IF EXISTS #INVITE_WITH_FOLLOW_UP;

  SELECT 
           A.PATIENT_JOIN_KEY
		   ,A.FIN_YEAR
		   ,A.INDEX_DATE AS INVITE_DATE
		   ,B.[INDEX_DATE] AS FOLLOW_UP_DATE
		   ,B.CONTACT_TYPE
		   INTO #INVITE_WITH_FOLLOW_UP 
		   FROM #HC_INVITE_ONLY_BY_YEAR AS A

		   LEFT JOIN #HC_CONTACTS_3 AS B  -- join on non-invite NHSHC events for each patient
		   ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
		   AND B.CONTACT_TYPE NOT LIKE '%NHSHC invitation%'
		   AND (B.CONTACT_TYPE <> 'NHSHC commenced'
		        OR B.[INDEX_DATE] >= '2015-01-01')  -- exclude single patient (5653942) being picked up with a "commenced" code in 2012/13

		   WHERE B.INDEX_DATE >= A.INDEX_DATE -- look for follow up events in 6 months following invite
		   AND B.INDEX_DATE <= DATEADD(MONTH, @MONTHS_AFTER_INVITE, A.INDEX_DATE) 
		   GROUP BY
           A.PATIENT_JOIN_KEY
		   ,A.FIN_YEAR
		   ,A.[INDEX_DATE]
		   ,B.INDEX_DATE
		   ,B.CONTACT_TYPE ;
	-- 335,003 rows


     -- c) Compile final table of patients invited with no 
	 -- follow up in 6 months

DROP TABLE IF EXISTS #HC_INVITE_NOFOLLOWUP_BY_YEAR;

SELECT *
INTO #HC_INVITE_NOFOLLOWUP_BY_YEAR
FROM (
	SELECT A.*
	 FROM #HC_INVITE_ONLY_BY_YEAR AS A
	 LEFT JOIN (SELECT PATIENT_JOIN_KEY 
					   ,FIN_YEAR 
				FROM #INVITE_WITH_FOLLOW_UP 
				GROUP BY PATIENT_JOIN_KEY 
					   ,FIN_YEAR ) AS B
	 ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
	 AND A.FIN_YEAR = B.FIN_YEAR

	 WHERE B.PATIENT_JOIN_KEY IS NULL -- exclude patients with follow up within 6 months
	) AS X;
-- 7,905,555 rows

/* Check invite only counts */
SELECT FIN_YEAR
,COUNT(PATIENT_JOIN_KEY) 
FROM #HC_INVITE_NOFOLLOWUP_BY_YEAR
GROUP BY FIN_YEAR
ORDER BY 1;
;

  --------------------------------------------------------------------
	-- STEP 10 - Combine in single table
    --------------------------------------------------------------------

/* Combine into single table */

DROP TABLE IF EXISTS #COHORTS_BY_FY;

SELECT 
A.COHORT
,A.COHORT_DETAIL
,B.*
INTO #COHORTS_BY_FY
FROM (
   (SELECT *
			,'ATTENDEE' AS COHORT
			,CONTACT_TYPE AS COHORT_DETAIL
	FROM #HC_ATTENDEES_BY_YEAR)
	UNION
	(SELECT *
			,'INAPPROPRIATE' AS COHORT
			,'INAPPROPRIATE' AS COHORT_DETAIL
	FROM #HC_INAPPR)
	UNION
	(SELECT *
			,'NON-ATTENDEE' AS COHORT
			,'DECLINED' AS COHORT_DETAIL
	FROM #HC_DECLINED_BY_YEAR)
	UNION
	(SELECT *
			,'NON-ATTENDEE' AS COHORT
			,'DNA' AS COHORT_DETAIL
	FROM #HC_DNA_BY_YEAR)
	UNION
	(SELECT *
			,'NON-ATTENDEE' AS COHORT
			,'COMMENCED' AS COHORT_DETAIL
	FROM #HC_COMMENCED_NOFOLLOWUP_BY_YEAR)
	UNION
	(SELECT *
			,'NON-ATTENDEE' AS COHORT
			,CONTACT_TYPE AS COHORT_DETAIL
	FROM #HC_INVITE_NOFOLLOWUP_BY_YEAR)
) AS A 

INNER JOIN #HC_CONTACTS_3 AS B 
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.INDEX_DATE = B.INDEX_DATE
AND A.CONTACT_TYPE = B.CONTACT_TYPE
;
--14,984,668 rows 

-- View data
SELECT TOP 10 * FROM #COHORTS_BY_FY

-- Drop intermediary tables
DROP TABLE IF EXISTS #HC_CONTACTS_3
DROP TABLE IF EXISTS #HC_INAPPR
DROP TABLE IF EXISTS #HC_ATTENDEES_BY_YEAR
DROP TABLE IF EXISTS #HC_DECLINED_BY_YEAR
DROP TABLE IF EXISTS #HC_DNA_BY_YEAR
DROP TABLE IF EXISTS #HC_COMMENCED_BY_YEAR
DROP TABLE IF EXISTS #HC_COMMENCED_NOFOLLOWUP_BY_YEAR
DROP TABLE IF EXISTS #HC_INVITE_ONLY_BY_YEAR
DROP TABLE IF EXISTS #HC_INVITE_NOFOLLOWUP_BY_YEAR


    --------------------------------------------------------------
	-- STEP 12 - Save attendees/non-attendees as permanent table
    --------------------------------------------------------------

DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY];

SELECT * INTO [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]
FROM #COHORTS_BY_FY AS X
WHERE FIN_YEAR IS NOT NULL;  -- exclude inappropriate records before 1/4/2012
--14,984,656 rows

-- Sense check data
SELECT TOP 100 * FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]

