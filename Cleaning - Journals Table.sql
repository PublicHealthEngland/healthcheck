--------------------------------------------
--------------------------------------------

--NHSHC, clean journals table

--contains:

	--1. Create temporary journals table to work from
	--2. Output min/maxes of each cluster join key, plus % non-null
	--3. Categories to apply value ranges to VALUE1_CONDITION field
			--a.) ACR Test
			--b.) BMI codes
			--c.) BP recording codes
			--d.) CVD risk assessment
			--e.) Height measured or declined
			--f.) Waist Circumference measured or declined
			--g.) Weight measured or declined
			--h.) IFCC HbA1c monitoring and diagnostic range codes
			--i.) Cholesterol total, HDL, ratio
			--j.) eGFR test
			--k.) alcohol
			--l.) FPG
	--4. Categories to apply value ranges to VALUE2_CONDITION field
			--a.) BP recording codes (diastolic part)
	--5. Categories where values are completely suppressed
		--i) VALUE1_CONDITION suppressed
		--ii) VALUE2_CONDITION suppressed
	--6. Height measured values in (m) updated to (cm) e.g 1 updated to 100 
	--7. De-duplicate records

	--8. Analysis of cleaned Journals table


--------------------------------------------
--------------------------------------------

----
----


--1. Create temporary journals table to work from

DROP TABLE IF EXISTS #JOURNALS_TABLE

SELECT *
INTO #JOURNALS_TABLE
FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE]
--615,630,491 rows

--

-- 2. Output min/maxes of each cluster join key, plus % non-null
/* Check min/max values for each cluster key */
SELECT
	A.[CLUSTER_JOIN_KEY]
	,B.CLUSTER_DESCRIPTION
	,B.CODE_DESCRIPTION
	,MIN([VALUE1_CONDITION]) AS MIN_VALUE1_CONDITION
	,MAX([VALUE1_CONDITION]) AS MAX_VALUE1_CONDITION
	,MIN([VALUE2_CONDITION]) AS MIN_VALUE2_CONDITION
	,MAX([VALUE2_CONDITION]) AS MAX_VALUE2_CONDITION
	,COUNT(*)  AS NO_RECORDS
	,COUNT(CASE WHEN [VALUE1_CONDITION] IS NOT NULL THEN 1 END)  AS VALUE1_NOT_NULL
	,COUNT(CASE WHEN [VALUE2_CONDITION] IS NOT NULL THEN 1 END)  AS VALUE2_NOT_NULL
	,COUNT(CASE WHEN [VALUE1_CONDITION] IS NOT NULL THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE1_NOT_NULL
	,COUNT(CASE WHEN [VALUE2_CONDITION] IS NOT NULL THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE2_NOT_NULL
	,COUNT(CASE WHEN [VALUE1_CONDITION] <> 0 THEN 1 END)  AS VALUE1_NOT_ZERO
	,COUNT(CASE WHEN [VALUE2_CONDITION] <> 0 THEN 1 END)  AS VALUE2_NOT_ZERO
	,COUNT(CASE WHEN [VALUE1_CONDITION] <> 0 THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE1_NOT_ZERO
	,COUNT(CASE WHEN [VALUE2_CONDITION] <> 0 THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE2_NOT_ZERO
FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE] AS A

LEFT JOIN (SELECT CLUSTER_JOIN_KEY
                 ,CLUSTER_DESCRIPTION
				 ,CODE_DESCRIPTION
				 ,ROW_NUMBER() OVER (PARTITION BY CLUSTER_JOIN_KEY ORDER BY CLUSTER_DESCRIPTION) AS RN
           FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
		   GROUP BY CLUSTER_JOIN_KEY
                   ,CLUSTER_DESCRIPTION
				   ,CODE_DESCRIPTION) AS B
ON A.[CLUSTER_JOIN_KEY] = B.[CLUSTER_JOIN_KEY]
AND B.RN = 1
GROUP BY
	A.[CLUSTER_JOIN_KEY]
	,B.CLUSTER_DESCRIPTION
	,B.CODE_DESCRIPTION
ORDER BY 1;


--3. Categories to apply value ranges to in VALUE1_CONDITION field

-- Suppress VALUE1_CONDITION field for these records

-- PART 1
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--a.) ACR Test
(
		
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'ACR test'
							   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 0
		OR  [VALUE1_CONDITION] > 1000000
			)
)
OR
--b.) BMI codes
	--i.) part 1 - Body mass index - observation (catch all)
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'BMI codes' 
							   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 12
		OR  [VALUE1_CONDITION] > 90
			)
)
OR 
	--part 2 - Body mass index less than 20
(
		[CLUSTER_JOIN_KEY] IN (540, 2548)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 12
		OR  [VALUE1_CONDITION] >= 20	
			)
)
OR 
	--part 3 - Body mass index 20-24 - normal
(
		[CLUSTER_JOIN_KEY] IN (542, 3093)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 20
		OR  [VALUE1_CONDITION] >= 25
			)
)
OR 
	--part 4 - Body mass index index 25-29 - overweight
(
		[CLUSTER_JOIN_KEY] IN (538)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 25
		OR  [VALUE1_CONDITION] >= 30
			)
)
OR 
	--part 5 - Body mass index 30+ - obesity
(
		[CLUSTER_JOIN_KEY] IN (539)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 30
		OR  [VALUE1_CONDITION] > 90
			)
)
OR 
	--part 6 - body mass index 30.0 - 34.9
(
		[CLUSTER_JOIN_KEY] IN (544, 3633)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 30
		OR  [VALUE1_CONDITION] >= 35
			)
)
OR 
	--part 7 - body mass index 35.0 - 39.9
(
		[CLUSTER_JOIN_KEY] IN (545, 3634)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 35
		OR  [VALUE1_CONDITION] >= 40
			)
)
OR 
	--part 8 - Body mass index 40+ - severely obese
(
		[CLUSTER_JOIN_KEY] IN (541, 546, 2964, 3635) -- CHANGED 19/4
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 40
		OR  [VALUE1_CONDITION] > 90
			)
)
OR 
	--part 9 - Body Mass Index low K/M2
(
		[CLUSTER_JOIN_KEY] IN (537)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 12
		OR  [VALUE1_CONDITION] >= 18.5		
			)
OR 
	--part 10 - Body Mass Index normal K/M2
(
		[CLUSTER_JOIN_KEY] IN (535)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 18.5
		OR  [VALUE1_CONDITION] >= 25
			)
)
OR 
	--part 11 - Body mass index high K/M2
(
		[CLUSTER_JOIN_KEY] IN (536)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 25
		OR  [VALUE1_CONDITION] > 90	
			)
)
)
-- 65,391 rows



-- PART 2
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--c.) BP recording codes
	--i.) systolic part
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'BP recording codes'
							   AND CODE_DESCRIPTION NOT LIKE '%diastolic%'
							   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 70
		OR  [VALUE1_CONDITION] > 300
			)
)
OR
	--ii.) diastolic part
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'BP recording codes'
							   AND CODE_DESCRIPTION LIKE '%diastolic%'
							   GROUP BY CLUSTER_JOIN_KEY)

	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 20
	OR  [VALUE1_CONDITION] > 150
		)
)
-- 34,344 rows 



-- PART 3
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--d.) CVD risk assessment
	--i.) part 1 - (catch all)
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'CVD risk assessment'
							   AND CODE_DESCRIPTION LIKE '%QRISK%' 
							   OR CODE_DESCRIPTION LIKE '%framingham%'
							   OR CODE_DESCRIPTION LIKE '%joint british societies%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria (*** changed Apr19 to exclude 0 due to TPP duplicates ***)
	AND (
		[VALUE1_CONDITION] <= 0
	OR  [VALUE1_CONDITION] > 100
		)
)
OR
	--ii.) part 2 - score less than 10 percent
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'CVD risk assessment'
							   AND CODE_DESCRIPTION LIKE '%less than ten percent%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] <= 0
	OR  [VALUE1_CONDITION] >= 10
		)
)
OR
	--iii.) part 3
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'CVD risk assessment'
							   AND CODE_DESCRIPTION LIKE '%ten percent to twenty percent%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 10
	OR  [VALUE1_CONDITION] > 20
		)
)
OR
	--iv.) part 4
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'CVD risk assessment'
							   AND CODE_DESCRIPTION LIKE '%twenty percent up to thirty%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] <= 20
	OR  [VALUE1_CONDITION] > 30
		)
)
OR
	--v.) part 5
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'CVD risk assessment'
							   AND CODE_DESCRIPTION LIKE '%greater than thirty percent%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] <= 30
	OR  [VALUE1_CONDITION] > 100
		)
)
-- 45,987 rows



-- PART 4
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--e.) height measured
(
	(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Height measured or declined'
							   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 100
		OR  [VALUE1_CONDITION] > 230
			)
	)
	AND
	(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Height measured or declined'
							   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION]*100 < 100
		OR  [VALUE1_CONDITION]*100 > 230
			)
	)
)
OR
--f.) Waist Circumference measured
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'waist circumference measured or declined'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 50
	OR  [VALUE1_CONDITION] > 200
		)
)
OR
--g.) Weight measured
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'weight measured or declined'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 20
	OR  [VALUE1_CONDITION] > 250
		)
)
OR
--h.) IFCC HbA1c monitoring and diagnostic range codes
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION LIKE '%hba1c%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 20
	OR  [VALUE1_CONDITION] > 195
		)
)
-- 180,723 rows



-- PART 5
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--i.) Cholesterol
	--i.) part 1 - total chol
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CLUSTER_DESCRIPTION = 'Cholesterol recorded'
								   AND CODE_DESCRIPTION NOT LIKE '%ratio%'
								   AND CODE_DESCRIPTION NOT LIKE '%HDL%'
								   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 1 
		OR  [VALUE1_CONDITION] >= 40 
			)
)
OR
	--ii.) part 2 HDL chol
(
			[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CLUSTER_DESCRIPTION = 'HDL cholesterol test' -- EC line changed 16/5/19
								   OR CODE_DESCRIPTION LIKE '%HDL cholesterol%'
								   GROUP BY CLUSTER_JOIN_KEY)
		--Min/Max criteria
		AND (
			[VALUE1_CONDITION] < 0.5
		OR  [VALUE1_CONDITION] > 5
			)
)
OR
	--iii.) part 3 - Chol ratio
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CODE_DESCRIPTION LIKE '%ratio%'
								   AND CLUSTER_DESCRIPTION LIKE '%cholesterol%'
								   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 0.2
	OR  [VALUE1_CONDITION] > 80 
		)
)
-- 74,445 rows


-- PART 6
UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--j.) eGFR test
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CLUSTER_DESCRIPTION = 'eGFR test'
								   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 0
	OR  [VALUE1_CONDITION] > 90
		)
)
OR
--k.) alcohol tests
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CLUSTER_DESCRIPTION LIKE '%alcohol%'
								   AND (CLUSTER_DESCRIPTION LIKE '%AUDIT%' 
											OR CLUSTER_DESCRIPTION LIKE '%FAST%')
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] < 0
	OR  [VALUE1_CONDITION] > 40
		)
)
OR
--l.) FPG *** ADDED MAR19 EC ***
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY 
								   FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
								   WHERE CLUSTER_DESCRIPTION = 'Fasting plasma glucose codes'
								   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE1_CONDITION] <= 0    -- Changed to exclude 0 12/7/2019
	OR  [VALUE1_CONDITION] > 100
		)
)
-- 343,679 rows


--4. Categories to apply value ranges to in VALUE2_CONDITION field

UPDATE #JOURNALS_TABLE
SET [VALUE2_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--a.) BP recording codes (diastolic part)
(
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'BP recording codes'
							   AND CODE_DESCRIPTION NOT LIKE '%diastolic%'
							   AND CODE_DESCRIPTION NOT LIKE '%systolic%'
							   GROUP BY CLUSTER_JOIN_KEY)
	--Min/Max criteria
	AND (
		[VALUE2_CONDITION] < 20
	OR  [VALUE2_CONDITION] > 150
		)
)
-- 38,557 rows


--
--5. Categories where values are suppressed completely

	--i.) VALUE1_CONDITION suppressed

UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
--suppress records with a value
	[VALUE1_CONDITION] IS NOT NULL
AND
(
--a.) Alcohol usage advice
		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Advice, information and any brief intervention given on alcohol usage'
							   GROUP BY CLUSTER_JOIN_KEY)

--b.) Smoking usage advice
OR		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Advice, signposting or information on smoking'
							   GROUP BY CLUSTER_JOIN_KEY)

-- c.) Weight management
OR		[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Advice, signposting or information on weight management'
							   GROUP BY CLUSTER_JOIN_KEY)

--d.) BMI codes
OR		[CLUSTER_JOIN_KEY] IN (545, 546)

--e.) BP recording code
OR		[CLUSTER_JOIN_KEY] IN (560, 562, 564, 566, 568, -- suppressed as less than 5% populated, or less than 3000 records
                               570, 572, 574, 575, 576, 
							   581, 582, 593, 600)

--f.) Cholesterol recorded
OR		[CLUSTER_JOIN_KEY] IN (634, 635, 636, 637, 669)

--g.) Chronic kidney disease codes
OR		[CLUSTER_JOIN_KEY] IN (463)

--h.) Codes for diabetes
OR		[CLUSTER_JOIN_KEY] IN (1308, 1361)
)
-- 1,915,823 rows

UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
(
--i.) Alcohol usage describe
-- suppress all apart from alcohol consumption records (cluster keys 25, 60)
        [CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY FROM [NHS_Health_Checks].[dbo].[TE_ALCOHOL_LOOKUP]
							   WHERE CODE_DESCRIPTION NOT LIKE 'Alcohol consumption' 
							   AND CODE_DESCRIPTION NOT LIKE 'Alcohol units per week')

--j.) CVD risk assessement
OR		[CLUSTER_JOIN_KEY] IN (607, 616)
--k.) GPPAQ assessment
OR		[CLUSTER_JOIN_KEY] IN (613)
--l.) height
OR		[CLUSTER_JOIN_KEY] IN (515, 523)
--m.) hypertension
OR		[CLUSTER_JOIN_KEY] IN (1745, 1746)
--n.) Impaired glucose tolerance
OR		[CLUSTER_JOIN_KEY] IN (646, 647, 648,
							   649, 651, 652)
--o.) pulse rhythm assessment
OR		[CLUSTER_JOIN_KEY] IN (548, 550, 552, 554)
--p.) smoking habit codes
OR		[CLUSTER_JOIN_KEY] IN (92, 76, 96, 111,
								74, 78, 103, 109,
								105, 72, 94, 117,
								93, 89, 80, 104,
								100, 106, 107)
--q.) stroke diagnosis
OR		[CLUSTER_JOIN_KEY] IN (1901)
--r.) stop smoking service
OR		[CLUSTER_JOIN_KEY] IN (772)
--s.) waist circumference
OR		[CLUSTER_JOIN_KEY] IN (828)
--t.) weight measured or declined
OR		[CLUSTER_JOIN_KEY] IN (528, 529, 530, 531, 532, 533)
)
-- 19,787,105 rows

	--ii.) VALUE2_CONDITION suppressed

-- PART 1
UPDATE #JOURNALS_TABLE
SET [VALUE2_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
	[VALUE2_CONDITION] IS NOT NULL
AND
(
--a.) BP recording codes
		[CLUSTER_JOIN_KEY] IN ( 575, 574, 597, 596,
								585, 586, 590, 589,
								592, 591, 570, 566,
								595, 594, 600, 598,
								599, 568, 582, 584,
								576, 593, 601, 587,
								572, 588, 562, 564,
								581, 560)	
)
-- 17,486 rows

-- PART 2
UPDATE #JOURNALS_TABLE
SET [VALUE2_CONDITION] = NULL
FROM #JOURNALS_TABLE
WHERE
	[VALUE2_CONDITION] IS NOT NULL
AND 
(
--b.) chronic kidney disease codes
		[CLUSTER_JOIN_KEY] IN (463)
--c.) codes for diabetes
OR		[CLUSTER_JOIN_KEY] IN (1361, 1308)
--d.) hypertension diagnosis
OR		[CLUSTER_JOIN_KEY] IN (1746, 1745)
--e.) smoking habits
OR		[CLUSTER_JOIN_KEY] IN (99, 76)
--f.) stroke diagnosis
OR		[CLUSTER_JOIN_KEY] IN (1901)
)
-- 25 rows

--

--6. Height measured values in (m) updated to (cm) e.g 1 updated to 100

UPDATE #JOURNALS_TABLE
SET [VALUE1_CONDITION] = [VALUE1_CONDITION]*100
WHERE
[CLUSTER_JOIN_KEY] IN (SELECT CLUSTER_JOIN_KEY
		                       FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
							   WHERE CLUSTER_DESCRIPTION = 'Height measured or declined'
							   GROUP BY CLUSTER_JOIN_KEY)
--Min/Max criteria
AND (
	[VALUE1_CONDITION] >= 1
AND [VALUE1_CONDITION] <= 2.3
	)	
-- 8,795,580 rows

--

--7. De-duplicate records

-- Deduplicate table
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED];

SELECT
  ROW_NUMBER() OVER(ORDER BY [DATE]) as 'ID'		
 ,[PATIENT_JOIN_KEY]
 ,[DATE]
 ,[CLUSTER_JOIN_KEY]
 ,[HCP_TYPE]
 ,[VALUE1_CONDITION]
 ,[VALUE2_CONDITION]
 ,[VALUE1_PRESCRIPTION]
INTO [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED]
FROM #JOURNALS_TABLE
GROUP BY
  [PATIENT_JOIN_KEY]
 ,[DATE]
 ,[CLUSTER_JOIN_KEY]
 ,[HCP_TYPE]
 ,[VALUE1_CONDITION]
 ,[VALUE2_CONDITION]
 ,[VALUE1_PRESCRIPTION]
-- 557,278,626 rows


--8. Analysis of cleaned Journals table

/* Raw vs. cleaned table - volumes */

-- Count number of records in current and original table 
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE];
-- 615,630,491 rows
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED];
-- 557,278,626 rows


/* Check min/max values for each cluster key */
SELECT
	A.[CLUSTER_JOIN_KEY]
	,B.CLUSTER_DESCRIPTION
	,B.CODE_DESCRIPTION
	,MIN([VALUE1_CONDITION]) AS MIN_VALUE1_CONDITION
	,MAX([VALUE1_CONDITION]) AS MAX_VALUE1_CONDITION
	,MIN([VALUE2_CONDITION]) AS MIN_VALUE2_CONDITION
	,MAX([VALUE2_CONDITION]) AS MAX_VALUE2_CONDITION
	,COUNT(*)  AS NO_RECORDS
	,COUNT(CASE WHEN [VALUE1_CONDITION] IS NOT NULL THEN 1 END)  AS VALUE1_NOT_NULL
	,COUNT(CASE WHEN [VALUE2_CONDITION] IS NOT NULL THEN 1 END)  AS VALUE2_NOT_NULL
	,COUNT(CASE WHEN [VALUE1_CONDITION] IS NOT NULL THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE1_NOT_NULL
	,COUNT(CASE WHEN [VALUE2_CONDITION] IS NOT NULL THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE2_NOT_NULL
	,COUNT(CASE WHEN [VALUE1_CONDITION] <> 0 THEN 1 END)  AS VALUE1_NOT_ZERO
	,COUNT(CASE WHEN [VALUE2_CONDITION] <> 0 THEN 1 END)  AS VALUE2_NOT_ZERO
	,COUNT(CASE WHEN [VALUE1_CONDITION] <> 0 THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE1_NOT_ZERO
	,COUNT(CASE WHEN [VALUE2_CONDITION] <> 0 THEN 1 END)*100.00/COUNT(*)  AS PC_VALUE2_NOT_ZERO
FROM [NHS_Health_Checks].[dbo].[JOURNALS_TABLE_CLEANED] AS A

LEFT JOIN (SELECT CLUSTER_JOIN_KEY
                 ,CLUSTER_DESCRIPTION
				 ,CODE_DESCRIPTION
				 ,ROW_NUMBER() OVER (PARTITION BY CLUSTER_JOIN_KEY ORDER BY CLUSTER_DESCRIPTION) AS RN
           FROM [NHS_Health_Checks].[dbo].[EXPANDED_CLUSTERS_REF]
		   GROUP BY CLUSTER_JOIN_KEY
                   ,CLUSTER_DESCRIPTION
				   ,CODE_DESCRIPTION) AS B
ON A.[CLUSTER_JOIN_KEY] = B.[CLUSTER_JOIN_KEY]
AND B.RN = 1
GROUP BY
	A.[CLUSTER_JOIN_KEY]
	,B.CLUSTER_DESCRIPTION
	,B.CODE_DESCRIPTION
ORDER BY 1;



