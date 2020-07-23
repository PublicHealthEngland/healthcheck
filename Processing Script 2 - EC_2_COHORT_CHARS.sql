--------------------------------------------
--------------------------------------------

/* SCRIPT 2 - PATIENT CHARACTERISTICS FOR NHSHC ATTENDEES AND 
NON-ATTENDEES BY FINANCIAL YEAR 

This script appends patient characteristics to the table of 
attendees/non-attendees by financial year. The most recent characteristic 
status is taken for the patient, from the day of their NHSHC contact 
or anytime before.
- CARER STATUS
- DEAF DIAGNOSIS
- BLIND DIAGNOSIS
- SEVERE MENTAL ILLNESS
- LEARNING DISABILITY
- DEMENTIA

PRE-EXISTING CONDITIONS (to check eligibility for NHSHC)
o	Atrial Fibrillation not resolved 
o	CKD (chronic kidney disease) stage 3-5 not resolved
o	CHD (Coronary Heart Disease) 
o	Heart Failure 
o	Hypertension not resolved
o	PAD (Peripheral arterial disease)
o	Stroke
o	TIA (Transient ischaemic attack) 
o	Diabetes not resolved
o	Is being prescribed statin 
o	QRISK2 >= 20%
o	Hypercholesterolemia

*/

--Emma Clegg
--Last updated:
--25/4/19

--Script logic:

	-- STEP 1 - Extract and group relevant characteristic read codes
	-- STEP 2 - Extract characteristic records for the NHSHC attendees/non-attendees
	     -- a. Extract journals records 
		 -- b. Count how many patients affected by conflicting statuses on the same day
		 -- c. Calculate difference in days between characteristic recording and
	        -- the patient's NHSHC contact
    -- STEP 3 - Assign one characteristic record per patient before/on day/after NHSHC
	-- STEP 4 - Assign final patient characteristics to patients 
	-- STEP 5 - Output summary results
	-- STEP 6 - Checks

-------------------------------------------------------------------------------------
-- Script uses:
-- 1) Table of attendees/non-attendees by financial year
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]

-- Script produces:
-- 1) Table of attendees/non-attendees with patient characteristics joined on
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS]


/*****************************************************************************/
    --------------------------------------------------------------
	-- STEP 1 - Extract and group characteristic read codes
    --------------------------------------------------------------

/* Extract patient characteristic records using their cluster join key,
and allocate to a cluster type 

Create a field "status" to store additional information/categorisation on 
descriptive characteristics
*/

DROP TABLE IF EXISTS #COMB_CODES;

SELECT A.CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,ROW_NUMBER() OVER(PARTITION BY A.CLUSTER_JOIN_KEY ORDER BY A.CODE_DESCRIPTION) as 'NO_LABELS'
	       -- Label cluster type (for each patient characteristic)
	,CASE WHEN [CLUSTER_DESCRIPTION] = 'Codes identifying the patient as a carer' THEN 'CARER'
		  WHEN [CLUSTER_DESCRIPTION] = 'Severe deafness diagnosis codes' THEN 'DEAF'
		  WHEN [CLUSTER_DESCRIPTION] = 'Registered blind codes' THEN 'BLIND'
	      WHEN [CLUSTER_DESCRIPTION] = 'Psychosis, schizophrenia + bipolar affective disease codes' THEN 'SMI' 
          WHEN [CLUSTER_DESCRIPTION] = 'Learning Disability codes' THEN 'LEARNING' 
		  WHEN [CLUSTER_DESCRIPTION] = 'Codes for Dementia' THEN 'DEMENTIA' 

			-- Label pre-existing conditions (making patient ineligible for NHSHC)				
		  WHEN CLUSTER_DESCRIPTION LIKE '%Atrial Fibrillation%' THEN 'AF'
		  WHEN CLUSTER_DESCRIPTION LIKE '%chronic kidney disease%' THEN 'CKD'
		  WHEN CLUSTER_DESCRIPTION LIKE '%coronary heart disease%' THEN 'CHD'
		  WHEN CLUSTER_DESCRIPTION LIKE '%heart failure%' THEN 'HEART FAILURE'
		  WHEN CLUSTER_DESCRIPTION LIKE '%hypertension%' THEN 'HYPERTENSION'
		  WHEN CLUSTER_DESCRIPTION LIKE '%PAD diagnostic codes%' THEN 'PAD'
		  WHEN CLUSTER_DESCRIPTION LIKE '%Stroke diagnosis codes%' THEN 'STROKE'
		  WHEN CLUSTER_DESCRIPTION LIKE '%TIA codes%' THEN 'TIA'
		  WHEN (CLUSTER_DESCRIPTION LIKE '%Codes for diabetes%' 
				OR CLUSTER_DESCRIPTION LIKE '%Diabetes resolved codes%') THEN 'DIABETES'
		  WHEN CLUSTER_DESCRIPTION IN ('Statin Codes', 'Codes for exception from serum cholesterol target; persisting',
					'Codes for exception from serum cholesterol target; expiring', 'Statin contraindications; persistent') THEN 'STATINS'
		  WHEN (CODE_DESCRIPTION LIKE '%QRISK2%' 
		         AND CODE_DESCRIPTION NOT LIKE '%declined%' 
				 AND CODE_DESCRIPTION NOT LIKE '%unsuitable%') THEN 'QRISK2'
		  WHEN CLUSTER_DESCRIPTION LIKE '%Hypercholesterolemia%' THEN 'HYPERCHOLESTEROLEMIA'						 
		  ELSE NULL END AS 'CLUSTER_TYPE'

              -- Carer/non-carer status
     ,CASE WHEN ([CLUSTER_DESCRIPTION] = 'Codes identifying the patient as a carer' 
	             AND CODE_DESCRIPTION LIKE '%not a%' 
				 OR CODE_DESCRIPTION LIKE '%no longer%') THEN 'NON-CARER'
		   WHEN [CLUSTER_DESCRIPTION] = 'Codes identifying the patient as a carer' THEN 'CARER'
		      -- AF diagnosis vs. AF resolved
		   WHEN CLUSTER_DESCRIPTION = 'Atrial fibrillation codes' THEN 'AF DIAGNOSIS'
		   WHEN CLUSTER_DESCRIPTION = 'Atrial Fibrillation resolved codes' THEN 'AF RESOLVED'
		      -- CKD diagnosis vs. CKD resolved
		   WHEN CLUSTER_DESCRIPTION = 'Chronic kidney disease codes 1-2' THEN 'CHRONIC KIDNEY 1-2'
		   WHEN CLUSTER_DESCRIPTION = 'Chronic kidney disease codes 3-5' THEN 'CHRONIC KIDNEY 3-5'
           WHEN CLUSTER_DESCRIPTION = 'Chronic kidney disease resolved codes' THEN 'CHRONIC KIDNEY RESOLVED'
		      -- CHD diagnosis vs. CHD resolved		      
		   WHEN (CLUSTER_DESCRIPTION LIKE '%coronary heart disease%' 
		         AND CODE_DESCRIPTION LIKE '%resolved%') THEN 'CHD RESOLVED' 
		   WHEN (CLUSTER_DESCRIPTION LIKE '%coronary heart disease%'
		         AND CODE_DESCRIPTION NOT LIKE '%resolved%') THEN 'CHD DIAGNOSIS' 
			  -- Hypertension diagnosis vs. resolved
		   WHEN CLUSTER_DESCRIPTION = 'Codes for hypertension resolved' THEN 'HYPERTENSION RESOLVED'
           WHEN CLUSTER_DESCRIPTION = 'Hypertension diagnosis codes' THEN 'HYPERTENSION DIAGNOSIS'
		       -- Diabetes diagnosis vs. resolved
           WHEN CLUSTER_DESCRIPTION = 'Codes for diabetes' THEN 'DIABETES'
           WHEN CLUSTER_DESCRIPTION = 'Diabetes resolved codes' THEN 'DIABETES RESOLVED'
		   ELSE NULL 
		   END AS 'STATUS'   

INTO #COMB_CODES 
FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF] AS A

;

/* Restrict to relevant cluster keys and deduplicate rows */
DROP TABLE IF EXISTS #COMB_CODES_2;

SELECT A.CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,A.[CLUSTER_TYPE]
	,COALESCE(A.[STATUS],A.[CLUSTER_TYPE]) AS [STATUS]
INTO #COMB_CODES_2
FROM #COMB_CODES AS A
WHERE [CLUSTER_TYPE] IS NOT NULL AND NO_LABELS = 1 -- select one label per cluster join key
GROUP BY A.CLUSTER_JOIN_KEY 
    ,A.CLUSTER_DESCRIPTION
	,A.CODE_DESCRIPTION
	,A.[CLUSTER_TYPE]
	,A.[STATUS]


SELECT * FROM #COMB_CODES_2
ORDER BY [CLUSTER_TYPE], 1;

    --------------------------------------------------------------
	-- STEP 2 - Extract characteristic records for the NHSHC attendees/non-attendees
    --------------------------------------------------------------

	     -- a. Extract journals records 

/* Extract all relevant characteristic records for attendees/non-attendees 
where date of record is not NULL. 

Add a valid_flag to label numerical measurements as valid (i.e. non-null and
within plausible range) - only applies to QRISK2 score here 
*/
 DROP TABLE IF EXISTS #CHARS_EXTRACT;    

 SELECT 
    A.PATIENT_JOIN_KEY
	,A.[DATE]
	,A.CLUSTER_JOIN_KEY 
    ,B.[CLUSTER_TYPE]
    ,CASE WHEN ([CLUSTER_TYPE] = 'QRISK2' AND A.VALUE1_CONDITION >= 20) THEN 'HIGH QRISK2'
	      ELSE [STATUS] END AS 'STATUS' 
	,A.[VALUE1_CONDITION] 
	,CASE WHEN (B.[CLUSTER_TYPE] = 'QRISK2'    -- Assign flag to label non-valid numerical measurements
	            AND A.VALUE1_CONDITION IS NULL) THEN 0 ELSE 1 END AS VALID_FLAG                 
 INTO #CHARS_EXTRACT
 FROM  [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]  AS A

 INNER JOIN #COMB_CODES_2 AS B           -- Join on cluster key lookup
 ON A.CLUSTER_JOIN_KEY = B.CLUSTER_JOIN_KEY

 WHERE A.[PATIENT_JOIN_KEY] IN (SELECT PATIENT_JOIN_KEY                      -- Restrict to attendees/non-attendees
                                   FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]
								   GROUP BY PATIENT_JOIN_KEY)
 AND A.[DATE] IS NOT NULL ;
 -- 33,098,949 rows
 -- 23442368 rows

 		 -- b. Count how many patients affected by conflicting statuses on the same day

/**** e.g. some patients marked as carer/non-carer on same day *****/

 /* Count how many valid measurements/statuses of each characteristic each patient 
 has (per day and overall) */

 -- Checks on STATUS field (everything apart from QRISK score)
 DROP TABLE IF EXISTS #MULTIPLE_TESTS_STATUS;

 SELECT A.[PATIENT_JOIN_KEY]
  	,A.[DATE]
	,A.[CLUSTER_TYPE]
	,A.[STATUS]
	,ROW_NUMBER() OVER(PARTITION BY A.[PATIENT_JOIN_KEY], A.[CLUSTER_TYPE], A.[DATE] ORDER BY A.[STATUS]) as 'NO_RECORDED_DAY'
	,ROW_NUMBER() OVER(PARTITION BY A.[PATIENT_JOIN_KEY], A.[CLUSTER_TYPE] ORDER BY A.[DATE]) as 'NO_RECORDED_TOT'
 INTO #MULTIPLE_TESTS_STATUS
 FROM #CHARS_EXTRACT AS A
 WHERE A.[CLUSTER_TYPE] <> 'QRISK2'
 GROUP BY
  A.[PATIENT_JOIN_KEY]
  	,A.[DATE]
	,A.[CLUSTER_TYPE]
	,A.[STATUS];
-- 8,463,097 rows

-- Checks on VALUE1_CONDITION field (QRISK score only)
 DROP TABLE IF EXISTS #MULTIPLE_TESTS_VALUE;

 SELECT A.[PATIENT_JOIN_KEY]
  	,A.[DATE]
	,A.[CLUSTER_TYPE]
	,A.[VALUE1_CONDITION]
	,ROW_NUMBER() OVER(PARTITION BY A.[PATIENT_JOIN_KEY], A.[CLUSTER_TYPE], A.[DATE] ORDER BY A.[VALUE1_CONDITION]) as 'NO_RECORDED_DAY'
	,ROW_NUMBER() OVER(PARTITION BY A.[PATIENT_JOIN_KEY], A.[CLUSTER_TYPE] ORDER BY A.[DATE]) as 'NO_RECORDED_TOT'
 INTO #MULTIPLE_TESTS_VALUE
 FROM #CHARS_EXTRACT AS A
 WHERE A.VALID_FLAG = 1
 AND A.[CLUSTER_TYPE] = 'QRISK2'
 GROUP BY
  A.[PATIENT_JOIN_KEY]
  	,A.[DATE]
	,A.[CLUSTER_TYPE]
	,A.[VALUE1_CONDITION];
-- 10,412,082 rows

/* Check what proportion of patients are affected for each
characteristic */
SELECT 
[CLUSTER_TYPE]
,COUNT(DISTINCT PATIENT_JOIN_KEY) AS NO_PATIENTS_MULT
,(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]) AS NO_PATIENTS_TOT
,COUNT(DISTINCT PATIENT_JOIN_KEY)*100.00/(SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY]) AS PC
FROM (SELECT PATIENT_JOIN_KEY,
                  [CLUSTER_TYPE] 
				  FROM #MULTIPLE_TESTS_STATUS
				  WHERE NO_RECORDED_DAY > 1
				  GROUP BY 
				  PATIENT_JOIN_KEY,
                  [CLUSTER_TYPE] 
	  UNION
	  SELECT PATIENT_JOIN_KEY,
                  [CLUSTER_TYPE] 
				  FROM #MULTIPLE_TESTS_VALUE 
				  WHERE NO_RECORDED_DAY > 1
				  GROUP BY 
				  PATIENT_JOIN_KEY,
                  [CLUSTER_TYPE]) AS A 
GROUP BY [CLUSTER_TYPE];


     -- c. Calculate difference in days between characteristic recording and
	 -- the patient's NHSHC contact
/* 
Look at the time period between the characteristic record and the patient's
most recent NHSHC contact in each financial year. Calculate "DATE_DIFF" to represent the 
date of the record minus the date of the NHSHC contact.

NOTE: This is intended to introduce duplicate rows as some patients have a NHSHC contact 
in multiple financial years!

Exclude records in case of a conflicting characteristic status on the same day

*/

DROP TABLE IF EXISTS #CHARS_EXTRACT2;

SELECT  B.PATIENT_JOIN_KEY
    ,B.FIN_YEAR 
	,B.INDEX_DATE
	,B.COHORT
  	,A.[DATE] AS 'TEST_DATE'
	,A.[CLUSTER_TYPE]
	,A.VALUE1_CONDITION
	,A.VALID_FLAG
	,A.[STATUS]  -- Assign all records a "status" 
	,DATEDIFF(day, CONVERT(VARCHAR, B.INDEX_DATE, 23), CONVERT(VARCHAR, A.[DATE], 23)) AS 'DATE_DIFF'
INTO #CHARS_EXTRACT2
FROM #CHARS_EXTRACT AS A

LEFT JOIN [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY  AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

-- Exclude statuses/measurements where patient has multiple
-- conflicting recordings on the same day
LEFT JOIN (SELECT PATIENT_JOIN_KEY,
                  [DATE],
                  [CLUSTER_TYPE] 
				  FROM #MULTIPLE_TESTS_STATUS
				  WHERE NO_RECORDED_DAY > 1
				  GROUP BY 
				  PATIENT_JOIN_KEY,
				  [DATE],
                  [CLUSTER_TYPE] 
		   UNION
		   SELECT PATIENT_JOIN_KEY,
                  [DATE],
                  [CLUSTER_TYPE] 
				  FROM #MULTIPLE_TESTS_VALUE 
				  WHERE NO_RECORDED_DAY > 1
				  GROUP BY 
				  PATIENT_JOIN_KEY,
				  [DATE],
                  [CLUSTER_TYPE]) AS C
ON A.PATIENT_JOIN_KEY = C.PATIENT_JOIN_KEY
AND A.[DATE] = C.[DATE]
AND A.[CLUSTER_TYPE] = C.[CLUSTER_TYPE]

WHERE C.PATIENT_JOIN_KEY IS NULL   -- exclude conflicting status cases

GROUP BY  B.PATIENT_JOIN_KEY
    ,B.FIN_YEAR 
	,B.INDEX_DATE
	,B.COHORT
  	,A.[DATE] 
	,A.[CLUSTER_TYPE]
	,A.VALUE1_CONDITION
	,A.VALID_FLAG
	,A.[STATUS]
-- 41,596,992 rows
-- 29155085 rows
    --------------------------------------------------------------
	-- STEP 3 - Assign one characteristic record per patient before/on day of NHSHC
    --------------------------------------------------------------

	     -- a. Identify characteristic record closest to NHSHC in each time period

/* Create a table of patients who had a characteristic record before their NHSHC.
Keep each patient's most recent status (for each characteristic) in this time 
(i.e. closest to the NHSHC date) */
DROP TABLE IF EXISTS #TESTS_BEFORE;

SELECT A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[CLUSTER_TYPE]
,[STATUS] AS 'STATUS_BEFORE'
,[TEST_DATE] AS 'TEST_DATE_BEFORE'
,[DATE_DIFF] AS 'DATE_DIFF_BEFORE' 
INTO #TESTS_BEFORE
FROM [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY  AS A

LEFT JOIN (SELECT * -- this orders by most to least recent date
			  ,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR], [CLUSTER_TYPE] ORDER BY [VALID_FLAG] DESC, [DATE_DIFF] DESC) AS rn
			  FROM #CHARS_EXTRACT2
			  WHERE DATE_DIFF < 0) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.FIN_YEAR = B.FIN_YEAR

WHERE rn = 1

GROUP BY A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[CLUSTER_TYPE]
,[STATUS] 
,[TEST_DATE]
,[DATE_DIFF];
-- 3,628,601 rows

/* Create a table of patients who had a characteristic record on the day of 
their NHSHC date */
DROP TABLE IF EXISTS #TESTS_ONDAY;

SELECT A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[CLUSTER_TYPE]
,[STATUS] AS 'STATUS_ONDAY'
,[TEST_DATE] AS 'TEST_DATE_ONDAY'
,[DATE_DIFF] AS 'DATE_DIFF_ONDAY' 
INTO #TESTS_ONDAY
FROM [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY  AS A

LEFT JOIN (SELECT * 
			  ,ROW_NUMBER() OVER (PARTITION BY [PATIENT_JOIN_KEY], [FIN_YEAR], [CLUSTER_TYPE] ORDER BY [PATIENT_JOIN_KEY]) AS rn
			  FROM #CHARS_EXTRACT2
			  WHERE DATE_DIFF = 0) AS B
ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
AND A.FIN_YEAR = B.FIN_YEAR

WHERE rn = 1

GROUP BY A.[PATIENT_JOIN_KEY]
,A.FIN_YEAR
,A.INDEX_DATE
,A.COHORT
,[CLUSTER_TYPE]
,[STATUS] 
,[TEST_DATE]
,[DATE_DIFF];
-- 4,071,483 rows

		 -- b. Separate characteristic records into separate fields

/* Left join each of the BEFORE/ON DAY tables to the table of patients with 
a completed NHSHC. Characteristic fields will be populated only in cases of patients 
having that particular characteristic recorded in the corresponding time period. 
*/

	-- 1) characteristics and pre-existing conditions BEFORE NHSHC
DROP TABLE IF EXISTS #TESTS_BEFORE2;

SELECT A.*
	,B1.STATUS_BEFORE AS 'CARER_BEFORE'
	,B1.DATE_DIFF_BEFORE AS 'CARER_DIFF_BEFORE'
	,B2.STATUS_BEFORE AS 'DEAF_BEFORE'
	,B2.DATE_DIFF_BEFORE AS 'DEAF_DIFF_BEFORE'
	,B3.STATUS_BEFORE AS 'BLIND_BEFORE'
	,B3.DATE_DIFF_BEFORE AS 'BLIND_DIFF_BEFORE'
	,B4.STATUS_BEFORE AS 'SMI_BEFORE'
	,B4.DATE_DIFF_BEFORE AS 'SMI_DIFF_BEFORE'
	,B5.STATUS_BEFORE AS 'LEARNING_BEFORE'
	,B5.DATE_DIFF_BEFORE AS 'LEARNING_DIFF_BEFORE'
	,B6.STATUS_BEFORE AS 'DEMENTIA_BEFORE'
	,B6.DATE_DIFF_BEFORE AS 'DEMENTIA_DIFF_BEFORE'

	,B7.STATUS_BEFORE AS 'AF_BEFORE'
	,B7.DATE_DIFF_BEFORE AS 'AF_DIFF_BEFORE'
	,B8.STATUS_BEFORE AS 'CKD_BEFORE'
	,B8.DATE_DIFF_BEFORE AS 'CKD_DIFF_BEFORE'
	,B9.STATUS_BEFORE AS 'CHD_BEFORE'
	,B9.DATE_DIFF_BEFORE AS 'CHD_DIFF_BEFORE'
	,B10.STATUS_BEFORE AS 'HF_BEFORE'
	,B10.DATE_DIFF_BEFORE AS 'HF_DIFF_BEFORE'
	,B11.STATUS_BEFORE AS 'HT_BEFORE'
	,B11.DATE_DIFF_BEFORE AS 'HT_DIFF_BEFORE'
	,B12.STATUS_BEFORE AS 'PAD_BEFORE'
	,B12.DATE_DIFF_BEFORE AS 'PAD_DIFF_BEFORE'
	,B13.STATUS_BEFORE AS 'STROKE_BEFORE'
	,B13.DATE_DIFF_BEFORE AS 'STROKE_DIFF_BEFORE'
	,B14.STATUS_BEFORE AS 'TIA_BEFORE'
	,B14.DATE_DIFF_BEFORE AS 'TIA_DIFF_BEFORE'
	,B15.STATUS_BEFORE AS 'DIABETES_BEFORE'
	,B15.DATE_DIFF_BEFORE AS 'DIABETES_DIFF_BEFORE'
	,B16.STATUS_BEFORE AS 'STATINS_BEFORE'
	,B16.DATE_DIFF_BEFORE AS 'STATINS_DIFF_BEFORE'
	,B17.STATUS_BEFORE AS 'QRISK2_BEFORE'
	,B17.DATE_DIFF_BEFORE AS 'QRISK2_DIFF_BEFORE'
	,B18.STATUS_BEFORE AS 'HYPCHOL_BEFORE'
	,B18.DATE_DIFF_BEFORE AS 'HYPCHOL_DIFF_BEFORE'

INTO #TESTS_BEFORE2
FROM [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY  AS A

	-- CARER, BLIND, DEAF, CARER, SMI, DEMENTIA 
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'CARER') AS B1
ON A.[PATIENT_JOIN_KEY] = B1.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B1.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'DEAF') AS B2
ON A.[PATIENT_JOIN_KEY] = B2.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B2.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'BLIND') AS B3
ON A.[PATIENT_JOIN_KEY] = B3.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B3.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'SMI') AS B4
ON A.[PATIENT_JOIN_KEY] = B4.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B4.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'LEARNING') AS B5
ON A.[PATIENT_JOIN_KEY] = B5.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B5.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'DEMENTIA') AS B6
ON A.[PATIENT_JOIN_KEY] = B6.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B6.FIN_YEAR

	-- Pre-existing conditions
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'AF') AS B7
ON A.[PATIENT_JOIN_KEY] = B7.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B7.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'CKD') AS B8
ON A.[PATIENT_JOIN_KEY] = B8.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B8.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'CHD') AS B9
ON A.[PATIENT_JOIN_KEY] = B9.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B9.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'HEART FAILURE') AS B10
ON A.[PATIENT_JOIN_KEY] = B10.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B10.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'HYPERTENSION') AS B11
ON A.[PATIENT_JOIN_KEY] = B11.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B11.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'PAD') AS B12
ON A.[PATIENT_JOIN_KEY] = B12.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B12.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'STROKE') AS B13
ON A.[PATIENT_JOIN_KEY] = B13.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B13.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'TIA') AS B14
ON A.[PATIENT_JOIN_KEY] = B14.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B14.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'DIABETES') AS B15
ON A.[PATIENT_JOIN_KEY] = B15.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B15.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'STATINS') AS B16
ON A.[PATIENT_JOIN_KEY] = B16.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B16.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'QRISK2') AS B17
ON A.[PATIENT_JOIN_KEY] = B17.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B17.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_BEFORE
		   WHERE [CLUSTER_TYPE] = 'HYPERCHOLESTEROLEMIA') AS B18
ON A.[PATIENT_JOIN_KEY] = B18.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B18.FIN_YEAR
;
--14,984,656 rows


	-- 2) characteristics ON DAY of NHSHC
DROP TABLE IF EXISTS #TESTS_ONDAY2;

SELECT A.*
	,C1.STATUS_ONDAY AS 'CARER_ONDAY'
	,C1.DATE_DIFF_ONDAY AS 'CARER_DIFF_ONDAY'
	,C2.STATUS_ONDAY AS 'DEAF_ONDAY'
	,C2.DATE_DIFF_ONDAY AS 'DEAF_DIFF_ONDAY'
	,C3.STATUS_ONDAY AS 'BLIND_ONDAY'
	,C3.DATE_DIFF_ONDAY AS 'BLIND_DIFF_ONDAY'
	,C4.STATUS_ONDAY AS 'SMI_ONDAY'
	,C4.DATE_DIFF_ONDAY AS 'SMI_DIFF_ONDAY'
	,C5.STATUS_ONDAY AS 'LEARNING_ONDAY'
	,C5.DATE_DIFF_ONDAY AS 'LEARNING_DIFF_ONDAY'
	,C6.STATUS_ONDAY AS 'DEMENTIA_ONDAY'
	,C6.DATE_DIFF_ONDAY AS 'DEMENTIA_DIFF_ONDAY'

INTO #TESTS_ONDAY2
FROM [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY AS A

	-- CARER, BLIND, DEAF, CARER, SMI, DEMENTIA
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'CARER') AS C1
ON A.[PATIENT_JOIN_KEY] = C1.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C1.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'DEAF') AS C2
ON A.[PATIENT_JOIN_KEY] = C2.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C2.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'BLIND') AS C3
ON A.[PATIENT_JOIN_KEY] = C3.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C3.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'SMI') AS C4
ON A.[PATIENT_JOIN_KEY] = C4.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C4.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'LEARNING') AS C5
ON A.[PATIENT_JOIN_KEY] = C5.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C5.FIN_YEAR
LEFT JOIN (SELECT * FROM #TESTS_ONDAY
		   WHERE [CLUSTER_TYPE] = 'DEMENTIA') AS C6
ON A.[PATIENT_JOIN_KEY] = C6.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C6.FIN_YEAR

;
--14,984,656 rows

    --------------------------------------------------------------
	-- STEP 4 - Assign final patient characteristics to patients
    --------------------------------------------------------------

DROP TABLE IF EXISTS #PATIENT_CHARS;

SELECT * INTO #PATIENT_CHARS 
FROM (

SELECT A.*
	,COALESCE(CARER_ONDAY, CARER_BEFORE) AS 'CARER'
	,COALESCE(DEAF_ONDAY, DEAF_BEFORE) AS 'DEAF'
	,COALESCE(BLIND_ONDAY, BLIND_BEFORE) AS 'BLIND'
	,COALESCE(SMI_ONDAY, SMI_BEFORE) AS 'SMI'
	,COALESCE(LEARNING_ONDAY, LEARNING_BEFORE) AS 'LEARNING'
	,COALESCE(DEMENTIA_ONDAY, DEMENTIA_BEFORE) AS 'DEMENTIA'
	  -- pre-existing conditions
    ,CASE WHEN AF_BEFORE = 'AF DIAGNOSIS' THEN 1 ELSE 0 END AS 'AF_INELIG' 
    ,CASE WHEN CKD_BEFORE = 'CHRONIC KIDNEY 3-5' THEN 1 ELSE 0 END AS 'CKD_INELIG'
	,CASE WHEN CHD_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'CHD_INELIG'
	,CASE WHEN HF_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'HF_INELIG'
	,CASE WHEN HT_BEFORE = 'HYPERTENSION DIAGNOSIS' THEN 1 ELSE 0 END AS 'HT_INELIG'
	,CASE WHEN PAD_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'PAD_INELIG'
    ,CASE WHEN STROKE_BEFORE IS NOT NULL  THEN 1 ELSE 0 END AS 'STROKE_INELIG'
	,CASE WHEN TIA_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'TIA_INELIG'
	,CASE WHEN DIABETES_BEFORE = 'DIABETES' THEN 1 ELSE 0 END AS 'DIABETES_INELIG'
	,CASE WHEN STATINS_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'STATINS_INELIG'
	,CASE WHEN QRISK2_BEFORE = 'HIGH QRISK2' THEN 1 ELSE 0 END AS 'QRISK2_INELIG'
	,CASE WHEN HYPCHOL_BEFORE IS NOT NULL THEN 1 ELSE 0 END AS 'HYPCHOL_INELIG'
	,CASE WHEN (AF_BEFORE = 'AF DIAGNOSIS' 
               OR CKD_BEFORE = 'CHRONIC KIDNEY 3-5' 
			   OR CHD_BEFORE IS NOT NULL
			   OR HF_BEFORE IS NOT NULL
			   OR HT_BEFORE = 'HYPERTENSION DIAGNOSIS'
			   OR PAD_BEFORE IS NOT NULL
               OR STROKE_BEFORE IS NOT NULL 
			   OR TIA_BEFORE IS NOT NULL
			   OR DIABETES_BEFORE = 'DIABETES'
			   OR STATINS_BEFORE IS NOT NULL
			   OR QRISK2_BEFORE = 'HIGH QRISK2'
			   OR HYPCHOL_BEFORE IS NOT NULL
			   ) THEN 1
	  ELSE 0 END AS 'INELIGIBLE_PRE_COND'

FROM [NHS_Health_Checks].[dbo].EC_1_COHORTS_BY_FY AS A 

LEFT JOIN #TESTS_ONDAY2 AS B
ON A.[PATIENT_JOIN_KEY] = B.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = B.FIN_YEAR

LEFT JOIN #TESTS_BEFORE2 AS C
ON A.[PATIENT_JOIN_KEY] = C.[PATIENT_JOIN_KEY]
AND A.FIN_YEAR = C.FIN_YEAR

) AS X;
--14,984,656 rows

    --------------------------------------------------------------
	-- STEP 5 - Save to permanent table
    --------------------------------------------------------------
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS];

SELECT * INTO [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS]
FROM #PATIENT_CHARS;
--14,984,656 rows

-- View sample results
SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS]

 