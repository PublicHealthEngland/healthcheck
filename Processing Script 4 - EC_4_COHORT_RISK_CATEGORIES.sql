--------------------------------------------
--------------------------------------------

/* RISK FACTOR CATEGORISATION FOR PATIENTS AT TIME OF NHSHC CONTACT
This script takes the risk factor metrics of patients at the time
of their NHSHC contact and categorises them by risk
*/

--Emma Clegg
--Last updated:
--25/3/19

--contains:

	-- STEP 1 - Add risk categorisation for each risk factor
	-- STEP 2 - Checks

-- Script uses:
-- 1) Table of attendees/non-attendees with risk factor metrics at time of 
--    NHSHC contact
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_3_COHORT_RISK_FACTORS]

-- Script produces:
-- 1) Table of attendees/non-attendees categorised by risk at time of
--    NHSHC contact
-- SELECT TOP 10 * FROM [NHS_Health_Checks].[dbo].[EC_4_COHORT_RISK_CATEGORIES]


/*****************************************************************************/
    --------------------------------------------------------------
	-- STEP 1 - Add risk categorisation for each risk factor
    --------------------------------------------------------------

DROP TABLE IF EXISTS #PATIENT_RISK_CATEGORIES;

SELECT *
	,CASE WHEN BMI IS NULL THEN '0. Missing'
		  WHEN BMI < 18.5 THEN '1. Underweight'
		  WHEN BMI >= 18.5 AND BMI < 25 THEN '2. Healthy weight'
		  WHEN BMI >= 25 AND BMI < 30 THEN '3. Overweight'
		  WHEN BMI >= 30 AND BMI < 40 THEN '4. Obese'
		  WHEN BMI >= 40 THEN '5. Severe obese'
		  ELSE '6. Other'
		  END AS BMI_CLASS
	,CASE WHEN WAIST IS NULL THEN '0. Missing'
	      WHEN SEX NOT IN (1,2) THEN '0. Unknown sex'
		  WHEN (SEX = 1 AND WAIST < 94) OR (SEX = 2 AND WAIST < 80) THEN '1. Low risk'
		  WHEN (SEX = 1 AND WAIST < 102) OR (SEX = 2 AND WAIST < 88)THEN '2. Moderate risk'
		  WHEN (SEX = 1 AND WAIST >= 102) OR (SEX = 2 AND WAIST >= 88)THEN '3. High risk'
		  ELSE '4. Other'
		  END AS WAIST_CLASS
	,CASE WHEN SYS_BP IS NULL THEN '0. Missing'
		  WHEN SYS_BP < 115 THEN '1. < 115'  
		  WHEN SYS_BP < 130 THEN '2. < 130'
		  WHEN SYS_BP < 140 THEN '3. < 140'
		  WHEN SYS_BP < 160 THEN '4. < 160'
		  WHEN SYS_BP >= 160 THEN '5. >= 160'
		  ELSE '6. Other'
		  END AS SYS_BP_CLASS
	,CASE WHEN (SYS_BP IS NULL OR DIA_BP IS NULL) THEN '0. Missing'
	      WHEN SYS_BP <= 90 OR DIA_BP <= 60 THEN '1. Low'
		  WHEN SYS_BP < 140 AND DIA_BP < 90 THEN '2. Normal'
		  WHEN SYS_BP >= 140 OR DIA_BP >= 90 THEN '3. High'   -- Hypertension definition
		  ELSE '4. Other'
		  END AS BP_CLASS
	,CASE WHEN CHOL_TOTAL IS NULL THEN '0. Missing'
		  WHEN CHOL_TOTAL <= 5 THEN '1. 5 or less'
		  WHEN CHOL_TOTAL <= 7.5 THEN '2. 5 - 7.5'
		  WHEN CHOL_TOTAL > 7.5 THEN '3. more than 7.5'
		  ELSE '4. Other'
		  END AS CHOL_TOTAL_CLASS
	,CASE WHEN CHOL_RATIO IS NULL THEN '0. Missing'
		  WHEN CHOL_RATIO <= 4 THEN '1. 4 or less'
		  WHEN CHOL_RATIO > 4 THEN '2. more than 4'
		  ELSE '3. Other'
		  END AS CHOL_RATIO_CLASS

		  -- CVD risk score
	,CASE WHEN COALESCE(QRISK, FRAMINGHAM) IS NULL THEN '0. Missing'
	      WHEN COALESCE(QRISK, FRAMINGHAM) < 10 THEN '1. less than 10'
		  WHEN COALESCE(QRISK, FRAMINGHAM) < 20 THEN '2. 10 - 19.99'
		  WHEN COALESCE(QRISK, FRAMINGHAM) >= 20 THEN '3. 20 or more'
		  ELSE '4. Other'
		  END AS CVD_RISK_SCORE_CLASS

	      -- Alcohol: FULL AUDIT
    ,CASE WHEN [AUDIT] IS NULL AND COALESCE([AUDITC], 0) <= 12 AND COALESCE([FAST], 0) <= 16 THEN '0. Missing'
	      WHEN [AUDIT] BETWEEN 0 AND 7 THEN '1. LOW_RISK'
		  WHEN [AUDIT] BETWEEN 8 AND 15 THEN '2. INC_RISK'
		  WHEN [AUDIT] BETWEEN 16 AND 19 THEN '3. HIGH_RISK'
		  WHEN [AUDIT] BETWEEN 20 AND 40 THEN '4. POS_DEP'

		  -- Assume higher FAST and AUDIT-C scores are full AUDIT score
		  WHEN [AUDITC] BETWEEN 13 AND 15 THEN '2. INC_RISK'
          WHEN COALESCE([AUDITC], [FAST]) BETWEEN 16 AND 19 THEN '3. HIGH_RISK'
		  WHEN COALESCE([AUDITC], [FAST]) BETWEEN 20 AND 40 THEN '4. POS_DEP'
	      ELSE '0. Missing' END AS ALCOHOL_AUDIT_CLASS    

			      -- Alcohol: AUDIT-C or FAST
    ,CASE WHEN COALESCE([AUDITC], [FAST]) IS NULL THEN '0. Missing'
	       -- Alcohol: AUDIT-C	  
		  WHEN [AUDITC] BETWEEN 0 AND 4 THEN '5. AUDIT-C_NEG'
		  WHEN [AUDITC] BETWEEN 5 AND 12 THEN '6. AUDIT-C_POS'
	       --Alcohol: FAST
		  WHEN [FAST] BETWEEN 0 AND 2 THEN '7. FAST_NEG'
		  WHEN [FAST] BETWEEN 3 AND 16 THEN '8. FAST_POS'
	      ELSE '0. Missing' END AS ALCOHOL_AUDITC_FAST_CLASS   

	,CASE WHEN GPPAQ IS NULL OR GPPAQ = 'GPPAQ - NO SCORE' THEN '0. Missing'
	      WHEN GPPAQ = 'DECLINED_UNSUITABLE' THEN '0. Declined/Unsuitable'
		  WHEN GPPAQ = 'ACTIVE' THEN '1. Active'
		  WHEN GPPAQ = 'MODERATELY ACTIVE' THEN '2. Moderately Active'
		  WHEN GPPAQ = 'MODERATELY INACTIVE' THEN '3. Moderately Inactive'
          WHEN GPPAQ = 'INACTIVE' THEN '4. Inactive'
		  ELSE '5. Other'
		  END AS PHYS_ACTIVITY_CLASS

	,CASE WHEN SMOKING IS NULL THEN '0. Missing'
	      WHEN SMOKING = 'NON-SMOKER' THEN '1. Non-smoker'
		  WHEN SMOKING = 'EX-SMOKER' THEN '2. Ex-smoker'
		  WHEN SMOKING = 'SMOKER' THEN '3. Smoker'
		  ELSE '4. Other'
		  END AS SMOKING_CLASS
		         
				 -- Glucose: HBA1C                           
	,CASE WHEN HBA1C IS NULL THEN '0. Missing'
	      WHEN HBA1C < 42 THEN '1. HBA1C < 42'
		  WHEN (HBA1C >= 42 AND HBA1C < 48) THEN '2. HBA1C < 48'
		  WHEN HBA1C >= 48 THEN '3. HBA1C >= 48'
		  ELSE '4. Other'
		  END AS GLUCOSE_HBA1C_CLASS

		         -- Glucose: FPG
    ,CASE WHEN FPG IS NULL THEN '0. Missing'
		  WHEN FPG < 5.5 THEN '1. FPG < 5.5'
		  WHEN (FPG >= 5.5 AND FPG < 7) THEN '2. FPG < 7'
		  WHEN FPG >= 7 THEN '3. FPG >= 7'
		  ELSE '4. Other'
		  END AS GLUCOSE_FPG_CLASS

INTO #PATIENT_RISK_CATEGORIES
FROM [NHS_Health_Checks].[dbo].[EC_3_COHORT_RISK_FACTORS]
;
-- 14,984,656 rows

SELECT TOP 10 * FROM #PATIENT_RISK_CATEGORIES;


/* Save to permanent table */ 
DROP TABLE IF EXISTS [NHS_Health_Checks].[dbo].[EC_4_COHORT_RISK_CATEGORIES];

SELECT * INTO [NHS_Health_Checks].[dbo].[EC_4_COHORT_RISK_CATEGORIES]
FROM #PATIENT_RISK_CATEGORIES;
-- 14,984,656 rows

    --------------------------------------------------------------
	-- STEP 2 - Sense checks
    --------------------------------------------------------------

/* Checks of permanent table volumes */

-- distinct patients
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY];
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS];
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_3_COHORT_RISK_FACTORS];
SELECT COUNT(DISTINCT PATIENT_JOIN_KEY) FROM [NHS_Health_Checks].[dbo].[EC_4_COHORT_RISK_CATEGORIES];
-- 11,553,866 patients

-- totals over all years
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[EC_1_COHORTS_BY_FY];
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[EC_2_COHORT_CHARS];
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[EC_3_COHORT_RISK_FACTORS];
SELECT COUNT(*) FROM [NHS_Health_Checks].[dbo].[EC_4_COHORT_RISK_CATEGORIES];
-- 14,984,656 records