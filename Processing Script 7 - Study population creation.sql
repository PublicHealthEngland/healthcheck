/* Script to create study population for NHSHC academic paper 0

- Each patient has one NHSHC event during the 5-year period
1/4/2012 - 31/3/2017 (i.e. not broken down by financial year)
- Under 40 year olds are removed

--Author: Emma Clegg

--Script logic:

	-- STEP 1 - Define attendees/non-attendees over 1/4/12-31/3/2017
	-- STEP 2 - Output socio-demographic tables

-------------------------------------------------------------------------------------
-- Script uses:
-- Table of attendees/non-attendees by financial year, with risk factor and
-- interventions info around the time of the NHSHC contact appended on
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS]

-- Script creates:
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS_PRE_FEB20] (Data extract pre 5/2/2020)
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS] (New data extract)

/*****************************************************************************/

*/
    --------------------------------------------------------------
	-- STEP 1 - Define attendees/non-attendees over 1/4/12-31/3/2017
    --------------------------------------------------------------

/* Create new table where patients aren't double counted over the 6 year
period (i.e. to look at 6 year period as a whole rather than by financial
year). 

For this, take the patient's earliest NHSHC contact date (allocating in
order ATTENDEE >> DECLINED/NOT ATTENDED/COMMENCED >> INVITED AND NO FOLLOW-UP
(inappropriates have already been separated out in master table)

*/

-- 1) Identify attendees
DROP TABLE IF EXISTS #ATTENDEES_5YEARS;

SELECT 
[PATIENT_JOIN_KEY]
,'ATTENDEE' AS COHORT
,MIN([INDEX_DATE]) AS INDEX_DATE    -- take earliest completion date
INTO #ATTENDEES_5YEARS
FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS] AS A 

WHERE COHORT = 'ATTENDEE'
AND AGE >= 40 
AND FIN_YEAR <> '2017/18'
GROUP BY 
[PATIENT_JOIN_KEY]; 
-- 5,102,758 rows


-- 2) Identify non-attendees
DROP TABLE IF EXISTS #NON_ATTENDEE_5YEARS;

SELECT 
A.[PATIENT_JOIN_KEY]
,'NON-ATTENDEE' AS COHORT
,MIN(A.[INDEX_DATE]) AS INDEX_DATE 
INTO #NON_ATTENDEE_5YEARS
FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS] AS A 

	-- join on attendees
	FULL JOIN (SELECT PATIENT_JOIN_KEY 
				 FROM #ATTENDEES_5YEARS 
				 GROUP BY 
				 PATIENT_JOIN_KEY) AS B
	ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY

WHERE A.COHORT = 'NON-ATTENDEE'
AND B.PATIENT_JOIN_KEY IS NULL  -- exclude attendees
AND A.AGE >= 40 
AND A.FIN_YEAR <> '2017/18'
GROUP BY 
A.[PATIENT_JOIN_KEY]; 
-- 4,592,221 rows


-- 3) Combine tables
DROP TABLE IF EXISTS #COHORTS_5YEARS;

SELECT B.*

INTO #COHORTS_5YEARS
FROM
	(SELECT * FROM #ATTENDEES_5YEARS
	UNION
	SELECT * FROM #NON_ATTENDEE_5YEARS) AS A

	 -- Inner join analysis table 5 to retrieve information on patients' NHSHC contacts
	INNER JOIN [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS] AS B
	ON A.PATIENT_JOIN_KEY = B.PATIENT_JOIN_KEY
	AND A.INDEX_DATE = B.INDEX_DATE
;
-- 9,694,979 rows


/* Check same number of patients in original and new cohort table.
Check one contact per patient in new table 
OK - volumes all the same */
SELECT COUNT(*) FROM #COHORTS_5YEARS;

SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) 
FROM [NHS_Health_Checks].[dbo].[EC_6_COHORT_PRESCRIPTIONS]
WHERE COHORT <> 'INAPPROPRIATE'
AND FIN_YEAR IS NOT NULL
AND FIN_YEAR <> '2017/18'
AND AGE >= 40;


-- 4) Save as permanent table
-- Create second copy of table for analysis of updated data extract from NHSD
-- on 5/2/2020. Keep one table only when comparison checks have been completed

DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS];

SELECT * INTO [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]
FROM #COHORTS_5YEARS AS X
-- 9,694,979 rows

-- View data
SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]

-- Check no more than one record per patient
SELECT 
COUNT(*),
COUNT(DISTINCT PATIENT_JOIN_KEY)
FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]



