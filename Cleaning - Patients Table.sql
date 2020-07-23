--------------------------------------------
--------------------------------------------

--QA of cleaned patients table - RW script
--4/12/18

--contains:

    --1. Restrict data to patients registered at a GP practice that was 
    -- extracted as part of our extract (note this will exclude more recent
	-- records for patients that have moved to a non-English practice
	--2. Extract list of patients with more than one DOB or GENDER
	--3. Extract each patient's most recent GP registration date
	--4. Copy patients table, excluding patients 
	     -- with multiple gender or DOB records
		 -- who have no registered date at their GP practice
       --Take one record for each patient based on most recent GP registered date
	--5. Update PRACTICE_ID, ETHNIC, LSOA and FIRST_LANGUAGE field to '-' where
	     -- there are conflicting entries on the same day
	--6. De-duplicate table, and ensure each patient has one record 
	--7. Checks
	--8. Save as permanent table

-- Script uses:
   -- 1) List of GP practice extracted in GPES data:
   --    (note 23 were extracted twice)
   -- SELECT * FROM [NHS_Health_Checks].[dbo].[GP_PRACTICE_LOOKUP]

   -- 2) Raw patients table
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]

-- Script produces:
   -- Cleaned patients table
   -- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]

/***** Data cleaning steps *****/

-- Check for blanks and NULLs in the LSOA field (all corrected to NULLs in step 4)
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]
WHERE LSOA = ''
ORDER BY 1
-- 0 rows

SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]
WHERE LSOA IS NULL
ORDER BY 1
-- 5663 rows

-- Count total raw records
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]
-- 12,157,457 rows

-- 1. Restrict data to patients registered at a GP practice that was 
-- extracted as part of our extract
DROP TABLE IF EXISTS #EXTRACTED_PRACTICES;

SELECT A.*
,B.SUPPLIER_NAME
INTO #EXTRACTED_PRACTICES
FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE] AS A 
INNER JOIN (SELECT PRACTICE_ID       -- Restrict to practices meant to be part of extract
                   ,SUPPLIER_NAME   
            FROM [NHS_Health_Checks].[dbo].[GP_PRACTICE_LOOKUP]
			GROUP BY PRACTICE_ID
			        ,SUPPLIER_NAME) AS B 
ON A.PRACTICE_ID = B.PRACTICE_ID ;
-- 12,152,031 rows

--2. Extract list of patients with more than one DOB or GENDER

/* Extract list of patients with more than one DOB 
SELECT * FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]
WHERE PATIENT_JOIN_KEY IN (SELECT PATIENT_JOIN_KEY FROM #DOB) */
DROP TABLE IF EXISTS #DOB;

SELECT PATIENT_JOIN_KEY
,COUNT(DISTINCT YEAR_OF_BIRTH) AS NO_DOB
INTO #DOB
FROM #EXTRACTED_PRACTICES
GROUP BY PATIENT_JOIN_KEY
HAVING COUNT(DISTINCT YEAR_OF_BIRTH) > 1;
-- 41 rows

/* Extract list of patients with more than one GENDER 
 (and not already picked up in #DOB)
*/
DROP TABLE IF EXISTS #GENDER;

SELECT A.PATIENT_JOIN_KEY
,COUNT(DISTINCT SEX) AS NO_SEX
INTO #GENDER
FROM #EXTRACTED_PRACTICES AS A 
LEFT JOIN #DOB AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE B.PATIENT_JOIN_KEY IS NULL
GROUP BY A.PATIENT_JOIN_KEY
HAVING COUNT(DISTINCT SEX) > 1;
-- 6 rows

-- Remove patients with multiple DOB or gender
DROP TABLE IF EXISTS #PATIENTS0;

SELECT *
INTO #PATIENTS0
FROM #EXTRACTED_PRACTICES AS A

WHERE A.PATIENT_JOIN_KEY NOT IN (SELECT PATIENT_JOIN_KEY 
                               FROM #DOB
							   GROUP BY PATIENT_JOIN_KEY) 
AND A.PATIENT_JOIN_KEY NOT IN (SELECT PATIENT_JOIN_KEY 
                               FROM #GENDER
							   GROUP BY PATIENT_JOIN_KEY) 
;
-- 12,151,896 rows


--3. Extract each patient's most recent GP registration date

DROP TABLE IF EXISTS #REG_DATE;

SELECT [PATIENT_JOIN_KEY]
,MAX(REGISTERED_DATE) AS REG_DATE
INTO #REG_DATE
FROM  #EXTRACTED_PRACTICES
GROUP BY [PATIENT_JOIN_KEY];
-- 12,088,986 rows

--4. Copy patients table, excluding patients with multiple gender or DOB 
     -- records, and taking each patient's most recent GP registered practice
DROP TABLE IF EXISTS #PATIENTS1;

SELECT A.[PATIENT_JOIN_KEY]
      ,A.[PRACTICE_ID]
	  ,A.SUPPLIER_NAME
      ,[YEAR_OF_BIRTH]
      ,[SEX]
      ,CASE WHEN [LSOA] = '' THEN NULL 
	        ELSE [LSOA] END AS LSOA
      ,[YEAR_OF_DEATH]
      ,[ETHNIC]
	  ,A.REGISTERED_DATE
      ,[FIRST_LANGUAGE]
      ,[ACTIVE]
INTO #PATIENTS1
FROM #PATIENTS0 AS A

LEFT JOIN #REG_DATE AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.REGISTERED_DATE = B.REG_DATE

WHERE  B.REG_DATE IS NOT NULL  -- Apply latest registration date constraint

GROUP BY A.[PATIENT_JOIN_KEY]
      ,A.[PRACTICE_ID]
	  ,A.SUPPLIER_NAME
      ,[YEAR_OF_BIRTH]
      ,[SEX]
      ,CASE WHEN [LSOA] = '' THEN NULL 
	        ELSE [LSOA] END
      ,[YEAR_OF_DEATH]
      ,[ETHNIC]
	  ,REGISTERED_DATE
      ,[FIRST_LANGUAGE]
      ,[ACTIVE];
-- 12,127,108 rows


--5. Update PRACTICE_ID, ETHNIC, LSOA and FIRST_LANGUAGE field to '-' where
     -- there are conflicting entries on the same day

/* Suppress PRACTICE_ID where conflicting entries on registration date */

-- 1) Identify patients with conflicting practice IDs on the same day
DROP TABLE IF EXISTS #UNCLEAR_PRACTICE;

SELECT [PATIENT_JOIN_KEY]
,COUNT(DISTINCT PRACTICE_ID) AS NO_PRACTICE
INTO #UNCLEAR_PRACTICE
FROM #PATIENTS1
GROUP BY [PATIENT_JOIN_KEY]
HAVING COUNT(DISTINCT PRACTICE_ID) > 1;
-- 2,983 rows


-- 2) Update their practice ID to '-'
UPDATE #PATIENTS1
SET [PRACTICE_ID] = '-'
FROM #PATIENTS1
WHERE [PATIENT_JOIN_KEY] IN (SELECT [PATIENT_JOIN_KEY]
                             FROM #UNCLEAR_PRACTICE);
-- 5,967 rows


/* Remove multiple ETHNIC entries on registration date */

-- 1) Identify patients with multiple entries
DROP TABLE IF EXISTS #ETHNICITY;

SELECT PATIENT_JOIN_KEY
,COUNT(DISTINCT ETHNIC) AS NO_ETHNIC
INTO #ETHNICITY
FROM #PATIENTS1
GROUP BY PATIENT_JOIN_KEY
HAVING COUNT(DISTINCT ETHNIC) > 1;
-- 4 rows

-- 2) Update field to NULL
UPDATE #PATIENTS1
SET ETHNIC = NULL
FROM #PATIENTS1
WHERE [PATIENT_JOIN_KEY] IN (SELECT [PATIENT_JOIN_KEY]
                             FROM #ETHNICITY);
-- 8 rows

/* Remove multiple LSOA entries on registration date */

-- 1) Identify patients with multiple entries
DROP TABLE IF EXISTS #LSOA;

SELECT PATIENT_JOIN_KEY
,COUNT(DISTINCT LSOA) AS NO_LSOA
INTO #LSOA
FROM #PATIENTS1
GROUP BY PATIENT_JOIN_KEY
HAVING COUNT(DISTINCT LSOA) > 1;
-- 642 rows

-- 2) Update field to NULL
UPDATE #PATIENTS1
SET LSOA = NULL
FROM #PATIENTS1
WHERE [PATIENT_JOIN_KEY] IN (SELECT [PATIENT_JOIN_KEY]
                             FROM #LSOA);
-- 1284 rows


/* Remove multiple FIRST_LANGUAGE entries on registration date */

-- 1) Identify patients with multiple entries
DROP TABLE IF EXISTS #LANGUAGE;

SELECT PATIENT_JOIN_KEY
,COUNT(DISTINCT FIRST_LANGUAGE) AS NO_LANGUAGE
INTO #LANGUAGE
FROM #PATIENTS1
GROUP BY PATIENT_JOIN_KEY
HAVING COUNT(DISTINCT FIRST_LANGUAGE) > 1;
-- 1 row

-- 2) Update field to NULL
UPDATE #PATIENTS1
SET FIRST_LANGUAGE = NULL
FROM #PATIENTS1
WHERE [PATIENT_JOIN_KEY] IN (SELECT [PATIENT_JOIN_KEY]
                             FROM #LANGUAGE);
-- 2 rows

--6. De-duplicate table, and ensure each patient has one record 
DROP TABLE IF EXISTS #PATIENTS_FINAL;

SELECT * 
INTO #PATIENTS_FINAL
FROM
	(SELECT [PATIENT_JOIN_KEY]
		  ,[PRACTICE_ID]
		  ,[SUPPLIER_NAME]
		  ,[YEAR_OF_BIRTH]
		  ,[SEX]
		  ,[LSOA]
		  ,[YEAR_OF_DEATH]
		  ,[ETHNIC]
		  ,[REGISTERED_DATE]
		  ,[FIRST_LANGUAGE]
		  ,[ACTIVE] -- Sorting on LSOA, ETHNIC and FIRST_LANGUAGE fields descending will prioritise non-null values
		  ,ROW_NUMBER() OVER(PARTITION BY [PATIENT_JOIN_KEY] ORDER BY [LSOA] DESC, [ETHNIC] DESC, [FIRST_LANGUAGE] DESC) as rn
	FROM #PATIENTS1
	GROUP BY [PATIENT_JOIN_KEY]
		  ,[PRACTICE_ID]
		  ,[SUPPLIER_NAME]
		  ,[YEAR_OF_BIRTH]
		  ,[SEX]
		  ,[LSOA]
		  ,[YEAR_OF_DEATH]
		  ,[ETHNIC]
		  ,[REGISTERED_DATE]
		  ,[FIRST_LANGUAGE]
		  ,[ACTIVE]) AS X
WHERE rn = 1; -- Keep one record per patient (prioritising non-null)
-- 12,088,907 rows

   --7. Save as permanent table
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED];

SELECT * 
INTO [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]
FROM #PATIENTS_FINAL ;


	--8. Checks

/* View records */
SELECT TOP 10 * FROM  [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED];

/* Check one record per patient left */
SELECT COUNT(*) - COUNT(DISTINCT PATIENT_JOIN_KEY) 
FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED];

/* Final check against existing cleaned patients table */
-- 68,550 records removed
SELECT 
(SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]) AS NO_NEW
,(SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]) AS NO_OLD
,(SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]) - (SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]) AS DIFF;

-- 5,376 patients removed
SELECT 
(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]) AS NO_NEW
,(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]) AS NO_OLD
,(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]) - (SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]) AS DIFF;


/* Check treatment of patients that had multiple values in ETHNIC, LSOA and FIRST_LANGUAGE
fields - non NULL records should be retained */
SELECT * FROM  [NHS_Health_Checks].[dbo].[PATIENTS_TABLE]
WHERE PATIENT_JOIN_KEY IN (210, 1504, 1710, 2330, 5827)
ORDER BY 1;

SELECT * FROM [NHS_Health_Checks].[dbo].[PATIENTS_TABLE_CLEANED]
WHERE PATIENT_JOIN_KEY IN (210, 1504, 1710, 2330, 5827)
ORDER BY 1;
