# -------------------------------------------------------
# Read in SQL table with paper 0 study population 
# (1/4/2012 - 31/3/2017) to populate descriptive tables

# TABLE 1 - invitees and % attendees by financial year
# TABLE 2 - Number of invites (attendees)
# TABLE 3 - invitees compared to estimated ONS mid-2015 population
# Risk factors - data completeness and risk profile
#    A) Figure: Data completeness radar charts
#    B) Appendix - breakdowns by risk factor category (excluding missings)
#    C) Figure: Risk factors - binary high risk cut off volumes
# TEXT: Type of check (third party completed)
# Appendix: HCP type
# TABLE 4 - Interventions - advice, referrals, further tests

# Set up ------------------------------------------------------------------

# Load packages
library(tidyverse)
library(RODBC)
library(readxl)
library(phecharts)
library(scales)
library(ggradar)
library(tibble)

# Connect to the Data Lake via an ODBC
# 
dbhandle <- odbcDriverConnect(Sys.getenv("ODBC_DRIVER_CONNECT"))

# Extract SQL data and check structure
patients_table  <- sqlQuery(dbhandle,
                            "SELECT *
                             FROM [NHS_Health_Checks].[dbo].[EC_NHSHC_PAPER0_PATIENTS]")

# Check structure
str(patients_table)

# Close the connection
odbcClose(dbhandle)


# 1) Prepare data for descriptive tables -----------------------------------------

# Create variables for patients' socio-demographic groupings
patients_table_formatted <- patients_table %>% 
                        mutate(age_group = factor(ifelse(AGE >= 40 & AGE <= 44, '40-44',
                                                 ifelse(AGE >= 45 & AGE <= 49, '45-49',
                                                 ifelse(AGE >= 50 & AGE <= 54, '50-54',
                                                 ifelse(AGE >= 55 & AGE <= 59, '55-59',
                                                 ifelse(AGE >= 60 & AGE <= 64, '60-64',
                                                 ifelse(AGE >= 65 & AGE <= 69, '65-69',
                                                 ifelse(AGE >= 70, '70-74',       
                                                          'error')))))))),
                               gender = factor(ifelse(SEX == 1, '1.MALE',
                                               ifelse(SEX == 2, '2.FEMALE', '3.UNKNOWN'))),
                               #ETHNIC GROUP AS PER QRISK GROUPING
                               ethnic = factor(ifelse(is.na(ETHNIC), "92. UNKNOWN",
                                                  ifelse(ETHNIC %in% c("A", "B", "C", "T"), "1. WHITE",
                                                      ifelse(ETHNIC == "H", "2. INDIAN",
                                                             ifelse(ETHNIC == "J", "3. PAKISTANI",
                                                                    ifelse(ETHNIC == "K", "4. BANGLADESHI",
                                                                           ifelse(ETHNIC == "N", "5. BLACK AFRICAN",
                                                                                  ifelse(ETHNIC == "M", "6. BLACK CARIBBEAN",
                                                                                         ifelse(ETHNIC == "R", "7. CHINESE", 
                                                                                                ifelse(ETHNIC == "L", "8. OTHER ASIAN",
                                                                                                       ifelse(ETHNIC %in% c("D","E","F","G","P","S","W"), "90. OTHER ETHNIC GROUP", 
                                                                                                              ifelse(ETHNIC == "Z", "91. NOT STATED", "92. UNKNOWN")))))))))))),
                               # Use national IMD decile from GP's LSOA if patient is missing LSOA from postcode of residence
                               #IMD = ifelse(!is.na(coalesce(IMD_ENG_DECILE_PAT, IMD_ENG_DECILE_GP)), factor(coalesce(IMD_ENG_DECILE_PAT, IMD_ENG_DECILE_GP)), 'IMD UNKNOWN'))
                               IMD = ifelse(!is.na(IMD_ENG_DECILE_PAT), factor(IMD_ENG_DECILE_PAT), 'IMD UNKNOWN'))


# Create dummy variable to label outcome (attendee vs. non-attendee)
patients_table_formatted <- patients_table_formatted %>% 
                         mutate(outcome = ifelse(COHORT == 'ATTENDEE', 1, 0))

# Check variable types in data
str(patients_table_formatted)

# Create subsetted dataset of attendees
patients_table_attendees <- patients_table_formatted %>% 
  filter(outcome == 1)

# Remove intermediary data table
rm(patients_table)

#--------------------------------------------------------------------------
# TABLE 1 - invitees and % attendees by financial year
#--------------------------------------------------------------------------

# Sum invitees and attendees by financial year
gpes_year_all <- patients_table_formatted %>% 
                    group_by(FIN_YEAR) %>% 
                    summarise(invitees = n()) %>% 
                    mutate(invitee_col_pc = round(invitees*100/sum(invitees), 1))

gpes_year_attendees <- patients_table_attendees %>% 
                          group_by(FIN_YEAR) %>% 
                          summarise(attendees = n()) %>% 
                          mutate(attendee_col_pc = round(attendees*100/sum(attendees), 1))

# Sum total invitees and attendees
gpes_all_total <- patients_table_formatted %>%
                            group_by(FIN_YEAR = "TOTAL") %>% 
                            summarise(invitees = n()) %>% 
                            mutate(invitee_col_pc = round(invitees*100/sum(invitees), 1))

gpes_attendees_total <- patients_table_attendees %>% 
                                group_by(FIN_YEAR = "TOTAL") %>% 
                                summarise(attendees = n()) %>% 
                                mutate(attendee_col_pc = round(attendees*100/sum(attendees), 1))

# Join attendee and invitee counts, calculating 95% confidence interval for attendance rate
gpes_year <- gpes_year_all %>% 
  left_join(gpes_year_attendees, by = "FIN_YEAR") %>%
  group_by(FIN_YEAR) %>% 
  mutate(attendance_rate = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[1],
         CI_lower = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[2],
         CI_upper = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[3])

gpes_total <- gpes_all_total %>%  
                 left_join(gpes_attendees_total, by = "FIN_YEAR") %>% 
                  group_by(FIN_YEAR) %>% 
                  mutate(attendance_rate = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[1],
                         CI_lower = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[2],
                         CI_upper = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[3])

# Combine yearly breakdown and totals tables together
comb_table <- rbind(gpes_year, gpes_total)

# Copy to clipboard for pasting into Excel
write.table(comb_table, "clipboard", sep="\t", row.names = FALSE)


#--------------------------------------------------------------------------
# TABLE 2: Number of invites (attendees)
#--------------------------------------------------------------------------
# See SQL script: "SQL scripts/Analysis 2 - invite types.sql"

# FIGURES: Type and timing of invites

# Connect to the Data Lake via an ODBC
dbhandle <- odbcDriverConnect(Sys.getenv("ODBC_DRIVER_CONNECT"))

# Read in processed table with patient's first invite type
invites_by_year  <- sqlQuery(dbhandle,
                             "SELECT *
                            FROM [NHS_Health_Checks].[dbo].[EC_INVITES_BY_YEAR]")

# Check structure
str(invites_by_year)

# Close the connection
odbcClose(dbhandle)


# Format data for plotting ------------------------------------------------

# Extract PHE colour codes
phe_colours <- brewer_phe()
# Specify desired PHE colour codes
new_colours <- c("#C8C8C8", "#002776", "#8CB8C6", "#532D6D", "#C51A4A", "#EAAB00", "#00B092", "#822433")
atlas_colours <- c("#ffffff", "#B3B3B3", "#165863", "#0095A8", "#32B9D1", "#7EE1F2", "#CCF6FF", "#000000")
# https://personal.sron.nl/~pault/
paul_tol_colours <- c("#DDDDDD", "#332288", "#88CCEE", "#44AA99", "#999933", "#DDCC77", "#CC6677", "#882255")

# Sum invite types by year
invites_by_year <- invites_by_year %>% 
  group_by(COHORT, FIN_YEAR) %>% 
  mutate(pc_year = round(NO_PATIENTS*100/sum(NO_PATIENTS), 1)) %>% 
  ungroup()

# Relabel groupings for plotting
invites_by_year <- invites_by_year %>%   
  arrange(FIN_YEAR, COHORT, -pc_year) %>% 
  mutate(COHORT = ifelse(COHORT == "ATTENDEE", "ATTENDEES", "NON-ATTENDEES"),
         INVITE_TYPE = factor(INVITE_TYPE, 
                              levels = c("No invitation recorded",
                                         "Multiple invitation types",
                                         "NHSHC invitation - text",
                                         "NHSHC invitation - email",
                                         "NHSHC invitation - telephone",
                                         "NHSHC invitation - verbal",
                                         "NHSHC invitation (unspecified)",
                                         "NHSHC invitation - letter")))

# 1) Plot stacked bar chart by year ------------------------------------------
# Colour options - 1) subset of PHE colours 2) viridis palette (for colourblindness)
first_invites_plot <- ggplot(data = invites_by_year,
                             aes(x = FIN_YEAR, 
                                 y = pc_year,
                                 fill = INVITE_TYPE)) +
  geom_bar(stat = "identity") +
  labs(x = "\nYear",
       y = "% invitations",
       fill = "First invitation type") +
  facet_grid(. ~ COHORT) +
  ggtitle("First invitations of attendees and non-attendees\n(by invitation type and year of patient's index date)") +
  scale_fill_manual(values = paul_tol_colours) +
  scale_y_continuous(expand = c(0, 1)) +
  #scale_fill_viridis_d(option = "D") +
  theme(legend.title = element_text(face = "bold"),
        axis.title = element_text(face = "bold"),
        axis.text = element_text(face = "bold"),
        panel.background = element_rect(fill = "transparent",colour = NA))

# View plot
first_invites_plot

# Save plot
ggsave(first_invites_plot, 
       file = "Plots/first_invites_plot.png",
       width = 10, height = 6)

# 2) Plot distribution of time between invite and check ----------------------

# Connect to the Data Lake via an ODBC
dbhandle <- odbcDriverConnect(Sys.getenv("ODBC_DRIVER_CONNECT"))

# Extract data on time between attendee's first invite and check
invite_times  <- sqlQuery(dbhandle,
                          "SELECT *
                              FROM [NHS_Health_Checks].[dbo].[EC_ATTENDEE_INVITE_TIMES]")

# Check structure
str(invite_times)

# Close the connection
odbcClose(dbhandle)

# View frequency distribution of DATE_DIFF field
date_diffs <- invite_times %>% 
  group_by(DATE_DIFF) %>% 
  summarise(count = n()) %>% 
  mutate(pc = count*100.00/sum(count),
         same_day = ifelse(DATE_DIFF %% 7 == 0, 1, 0)) # add flag for multiples of 7 (peaks observed)

View(date_diffs)

# Remove patients with invite on same day as check
invite_times_without_same_day <- invite_times %>% 
  filter(DATE_DIFF != 0) %>% 
  arrange(DATE_DIFF)

# Calculate median time between invite and check
summary(invite_times_without_same_day$DATE_DIFF)

med_date_diff_without_same_day <- as.numeric(summary(invite_times_without_same_day$DATE_DIFF)[3])

# Plot histogram with distribution of DATE_DIFF
invites_date_diff_plot <- ggplot(data = invite_times_without_same_day,
                                 aes(x = DATE_DIFF)) +
  geom_histogram(binwidth = 1,
                 fill = "#00B092"
  ) +
  labs(x = "\nDays between first invitation and check",
       y = "Attendees") +
  scale_x_continuous(expand = c(0, 0)) +
  scale_y_continuous(labels = comma,
                     expand = c(0, 0)) +
  ggtitle("Distribution of days between attendees' first invitation and completed check\n(excluding opportunistic invitations recorded on the day of check)") +
  theme(axis.title = element_text(face = "bold"),
        panel.background = element_rect(fill = "transparent"),
        plot.background = element_rect(fill = "transparent", color = NA),
        axis.line = element_line()) +
  geom_vline(xintercept = med_date_diff_without_same_day,
             colour = "#EAAB00",
             size = 1,
             show.legend = TRUE) +
  annotate(geom = "text",
           label = paste0("Median = ", med_date_diff_without_same_day, " days"), 
           x = med_date_diff_without_same_day + 35, y = 60000)

# View histogram
invites_date_diff_plot

# Save plot
ggsave(invites_date_diff_plot, 
       file = "Plots/invites_date_diff_plot.png",
       width = 9, height = 6)


#--------------------------------------------------------------------------
# TABLE 3 - invitees compared to estimated ONS mid-2015 population
#--------------------------------------------------------------------------

# 3A) ONS mid 2015 population -----------------------------------------------

# Read in Excel files with ONS pops
ons_pops_15 <- read_excel("Reference Tables/ONS popsbyimddecileengland20012017.xls", 
                          sheet=2,
                          skip=11) 

ons_pops_15_ethnic <- read_excel("Reference Tables/denominatorsegregions20112017.xls", 
                                 sheet="2015",
                                 skip=2) 

# Filter on relevant year (2015) and ages (40-74)
ons_pops_15 <- ons_pops_15 %>% 
  filter(Year == 2015,
         `Age group` < "75-79",
         `Age group` > "35-39") %>% 
  mutate(gender = ifelse(Sex == 1, "1.MALE",
                         ifelse(Sex == 2, "2.FEMALE", "3.UNKNOWN")))

# Aggregate by AGE GROUP
ons_age <- ons_pops_15 %>%  
  group_by(`Age group`) %>% 
  summarise(count = sum(Count, na.rm = TRUE)) %>% 
  mutate(col_pc = count*100/sum(count))

# Aggregate by GENDER
ons_gender <- ons_pops_15 %>%  
  group_by(gender) %>% 
  summarise(count = sum(Count, na.rm = TRUE)) %>% 
  mutate(col_pc = count*100/sum(count))

# Aggregate by IMD decile
ons_imd <- ons_pops_15 %>%  
  group_by(`IMD decile`) %>% 
  summarise(count = sum(Count, na.rm = TRUE)) %>% 
  mutate(col_pc = count*100/sum(count))

# ETHNICITY
# Filter on England and relevant ages (40-74)
ons_pops_15_ethnic <- ons_pops_15_ethnic %>% 
  filter(area_name == "England",
         age >= 40,
         age <= 74) %>% 
  mutate(white = White_British + White_Irish + White_Gypsy_Irish_Traveller + White_Other_White,
         black_african = Black_African,
         black_caribbean = Black_Caribbean,
         indian = Asian_Indian,
         pakistani = Asian_Pakistani,
         bangladeshi = Asian_Bangladeshi,
         chinese = Asian_Chinese,
         other_asian = Asian_Other_Asian,
         other_ethnic = Mixed_White_and_Black_Caribbean + Mixed_White_and_Black_African + 
           Mixed_White_and_Asian + Mixed_Other_Mixed + Black_Other_Black + Other_Arab + Other_Any_other_ethnic_group)

# Aggregate
ons_ethnic <- ons_pops_15_ethnic %>% 
                  group_by(area_code, area_name) %>% 
                  summarise(`1. WHITE` = sum(white),
                            `5. BLACK AFRICAN` = sum(black_african),
                            `6. BLACK CARIBBEAN` = sum(black_caribbean),
                            `2. INDIAN` = sum(indian),
                            `3. PAKISTANI` = sum(pakistani), 
                            `4. BANGLADESHI` = sum(bangladeshi),
                            `7. CHINESE` = sum(chinese),
                            `8. OTHER ASIAN` = sum(other_asian),
                            `90. OTHER ETHNIC GROUP` = sum (other_ethnic)) %>% 
                  gather(group, count, `1. WHITE`:`90. OTHER ETHNIC GROUP`) %>% 
                  mutate(col_pc = count*100/sum(count)) %>% 
                  ungroup() %>% 
                  select(-area_code, -area_name)


# total
ons_total <- ons_pops_15 %>% 
  summarise(group = "Total",
            ons_count = sum(Count),
            ons_col_pc = 1)

# set rownames
colnames(ons_age) <- c("group", "ons_count", "ons_col_pc")
colnames(ons_ethnic) <-  c("group", "ons_count", "ons_col_pc")
colnames(ons_gender) <-  c("group", "ons_count", "ons_col_pc")
colnames(ons_imd) <-  c("group", "ons_count", "ons_col_pc")

# combine ONS results
ons_results <- rbind(ons_age, ons_ethnic, ons_gender, ons_imd, ons_total)


# 3B) Total invitees --------------------------------------------------------

# by age group
gpes_age <- patients_table_formatted %>% 
  group_by(age_group) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count))

# by ethnic group
gpes_ethnic <- patients_table_formatted %>% 
  group_by(ethnic) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count))

# by gender
gpes_gender <- patients_table_formatted %>% 
  group_by(gender) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count))

# by IMD
gpes_imd <- patients_table_formatted %>% 
  group_by(IMD) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count))

# patient characteristics

# 1) counts
gpes_chars_counts <- patients_table_formatted %>% 
  summarise(no_carers = sum(!is.na(CARER)),
            no_deaf = sum(!is.na(DEAF)),
            no_blind = sum(!is.na(BLIND)),
            no_smi = sum(!is.na(SMI)),
            no_learning = sum(!is.na(LEARNING)),
            no_dementia = sum(!is.na(DEMENTIA)),
            no_rheu_arthritis = sum(!is.na(R_ARTHRITIS)))

# Transpose and set row and column names
gpes_chars_counts <- data.frame((t(gpes_chars_counts))[-1, ])
colnames(gpes_chars_counts) <- "invitee_count"
gpes_chars_counts$group <- rownames(gpes_chars_counts)

# 2) percentages
gpes_chars_pc <- patients_table_formatted %>% 
  summarise(no_carers = sum(!is.na(CARER))*100.00/n(),
            no_deaf = sum(!is.na(DEAF))*100.00/n(),
            no_blind = sum(!is.na(BLIND))*100.00/n(),
            no_smi = sum(!is.na(SMI))*100.00/n(),
            no_learning = sum(!is.na(LEARNING))*100.00/n(),
            no_dementia = sum(!is.na(DEMENTIA))*100.00/n(),
            no_rheu_arthritis = sum(!is.na(R_ARTHRITIS))*100.00/n())

gpes_chars_pc <- data.frame((t(gpes_chars_pc))[-1, ])
colnames(gpes_chars_pc) <- "invitee_col_pc"
gpes_chars_pc$group <- rownames(gpes_chars_pc)

# 3) combine counts and percentages
gpes_chars <- gpes_chars_counts %>% 
  left_join(gpes_chars_pc, by = "group")

gpes_chars <- gpes_chars %>% 
  select(group, "invitee_count", "invitee_col_pc")

# total
gpes_total <- patients_table_formatted %>% 
  summarise(group = "Total",
            invitee_count = n(),
            invitee_col_pc = 1) 

# set rownames
colnames(gpes_age) <- c("group", "invitee_count", "invitee_col_pc")
colnames(gpes_ethnic) <-  c("group", "invitee_count", "invitee_col_pc")
colnames(gpes_gender) <-  c("group", "invitee_count", "invitee_col_pc")
colnames(gpes_imd) <-  c("group", "invitee_count", "invitee_col_pc")

# combine invitee results
invitee_results <- rbind(gpes_gender, gpes_age, gpes_ethnic, gpes_imd, gpes_chars, gpes_total)


# 3C) Attendees and non-attendees -------------------------------------------

# by age group
gpes_invitee_age <- patients_table_formatted %>% 
  group_by(COHORT, age_group) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count)) %>% 
  pivot_wider(names_from = COHORT, values_from = c(count, col_pc)) 

# by ethnic group
gpes_invitee_ethnic <- patients_table_formatted %>% 
  group_by(COHORT, ethnic) %>% 
  summarise(count = n()) %>% 
  mutate(col_pc = count*100/sum(count)) %>% 
  pivot_wider(names_from = COHORT, values_from = c(count, col_pc))

# by gender
gpes_invitee_gender <- patients_table_formatted %>% 
  group_by(COHORT, gender) %>%
  summarise(count = n())  %>% 
  mutate(col_pc = count*100/sum(count)) %>% 
  pivot_wider(names_from = COHORT, values_from = c(count, col_pc))

# by IMD decile
gpes_invitee_imd <- patients_table_formatted %>% 
  group_by(COHORT, IMD) %>% 
  summarise(count = n())  %>% 
  mutate(col_pc = count*100/sum(count)) %>% 
  pivot_wider(names_from = COHORT, values_from = c(count, col_pc))

# patient characteristics

# 1) counts
gpes_invitee_chars_counts <- patients_table_formatted %>% 
  group_by(COHORT) %>% 
  summarise(no_carers = sum(!is.na(CARER)),
            no_deaf = sum(!is.na(DEAF)),
            no_blind = sum(!is.na(BLIND)),
            no_smi = sum(!is.na(SMI)),
            no_learning = sum(!is.na(LEARNING)),
            no_dementia = sum(!is.na(DEMENTIA)),
            no_rheu_arthritis = sum(!is.na(R_ARTHRITIS)))

gpes_invitee_chars_counts <- data.frame((t(gpes_invitee_chars_counts))[-1, ])
colnames(gpes_invitee_chars_counts) <- c("count_ATTENDEE", "count_NON-ATTENDEE")
gpes_invitee_chars_counts$group <- rownames(gpes_invitee_chars_counts)

# 2) percentages
gpes_invitee_chars_pc <- patients_table_formatted %>% 
  group_by(COHORT) %>% 
  summarise(no_carers = sum(!is.na(CARER))*100.00/n(),
            no_deaf = sum(!is.na(DEAF))*100.00/n(),
            no_blind = sum(!is.na(BLIND))*100.00/n(),
            no_smi = sum(!is.na(SMI))*100.00/n(),
            no_learning = sum(!is.na(LEARNING))*100.00/n(),
            no_dementia = sum(!is.na(DEMENTIA))*100.00/n(),
            no_rheu_arthritis = sum(!is.na(R_ARTHRITIS))*100.00/n())

gpes_invitee_chars_pc <- data.frame((t(gpes_invitee_chars_pc))[-1, ])
colnames(gpes_invitee_chars_pc) <- c("col_pc_ATTENDEE", "col_pc_NON-ATTENDEE")
gpes_invitee_chars_pc$group <- rownames(gpes_invitee_chars_pc)

# 3) combine counts and percentages
gpes_invitee_chars <- gpes_invitee_chars_counts %>% 
                        left_join(gpes_invitee_chars_pc, by = "group")

gpes_invitee_chars <- gpes_invitee_chars %>% 
                       select(group, `count_ATTENDEE`, "count_NON-ATTENDEE",
                              `col_pc_ATTENDEE`, "col_pc_NON-ATTENDEE")

# total
gpes_invitee_total <- patients_table_formatted %>% 
  group_by(COHORT) %>%
  summarise(group = "Total",
            count = n()) %>% 
  mutate(col_pc = 1) %>% 
  pivot_wider(names_from = COHORT, values_from = c(count, col_pc))

# set rownames
colnames(gpes_invitee_age)[1] <- c("group")
colnames(gpes_invitee_ethnic)[1] <- c("group")
colnames(gpes_invitee_gender)[1] <- c("group")
colnames(gpes_invitee_imd)[1] <- c("group")  
colnames(gpes_invitee_total)[1] <- c("group")  

# combine attendee/non-attendee results
cohort_results <- rbind(gpes_invitee_gender, gpes_invitee_age, gpes_invitee_ethnic, gpes_invitee_imd, gpes_invitee_chars, gpes_invitee_total)

# Reorder columns
cohort_results <- cohort_results[c(1, 2, 4, 3, 5)]

# Combine ONS, invitee and attendee/non-attendee counts ------
results <- ons_results %>% 
  right_join(invitee_results, by = "group") %>% 
  left_join(cohort_results, by = "group")

# Copy to clipboard to paste to Excel
write.table(results, "clipboard", sep="\t", row.names = FALSE)


#--------------------------------------------------------------------------
# Risk factors - data completeness and risk profile
#--------------------------------------------------------------------------

# ---------------------------------------------------------------------
# A) Figure: Data completeness radar charts

# Install plotting package ggradar
# devtools::install_github("ricardo-bion/ggradar", 
#                          dependencies = TRUE)

# Define colour codes
plot_colours <- c("#A95AA1", "#0F2080")

# Count complete records by risk factor
risk_factor_completeness <- patients_table_formatted %>% 
  mutate(outcome = ifelse(outcome == 1, "Attendees", "Non-attendees")) %>% 
  group_by(outcome) %>% 
  summarise(`CVD risk\nscore` = sum(CVD_RISK_SCORE_CLASS != "0. Missing")/n(),
            Alcohol = sum(!(ALCOHOL_AUDIT_CLASS == "0. Missing" & ALCOHOL_AUDITC_FAST_CLASS %in% c("0. Missing", "6. AUDIT-C_POS", "8. FAST_POS")))/n(),
            `Blood\nglucose` = sum(!(GLUCOSE_HBA1C_CLASS == "0. Missing" & GLUCOSE_FPG_CLASS == "0. Missing"))/n(),
            `Blood\npressure` = sum(BP_CLASS != "0. Missing")/n(),
            BMI = sum(BMI_CLASS != "0. Missing")/n(),
            `Cholesterol\n(ratio)` = sum(CHOL_RATIO_CLASS != "0. Missing")/n(),
            `Cholesterol\n(total)` = sum(CHOL_TOTAL_CLASS != "0. Missing")/n(),
            `Physical\nactivity` = sum(PHYS_ACTIVITY_CLASS != "0. Missing")/n(),
            Smoking = sum(SMOKING_CLASS != "0. Missing")/n())

# Copy to clipboard for pasting
write.table(risk_factor_completeness, "clipboard", sep="\t", row.names = FALSE)

# Plot radar chart
radar_chart <- ggradar(risk_factor_completeness, 
                       group.colours = plot_colours,
                       gridline.label.offset = -0.05,
                       plot.title = "Completeness of risk factor measurements for\nattendees and non-attendees (2012/13 - 2016/17)",
                       legend.text.size = 16,
                       legend.position = "bottom") 

# View chart
radar_chart

# Save radar chart
ggsave("plots/radar chart risk factor completeness.png", 
       width = 9, height = 7.5, plot = radar_chart)

# ---------------------------------------------------------------------
# B) Appendix: Risk factors - binary high risk counts

# Create variables for binary risk factor cut offs
patients_table_risks <- patients_table_formatted %>% 
  mutate(`Alcohol` = ifelse(ALCOHOL_AUDIT_CLASS == "0. Missing" & ALCOHOL_AUDITC_FAST_CLASS %in% c("0. Missing", "6. AUDIT-C_POS", "8. FAST_POS"), "Missing",
                               ifelse(ALCOHOL_AUDIT_CLASS %in% c("2. INC_RISK", "3. HIGH_RISK", "4. POS_DEP"), "Yes", "No")),
         `Blood glucose` = ifelse(GLUCOSE_HBA1C_CLASS == "0. Missing" & GLUCOSE_FPG_CLASS == "0. Missing", "Missing",
                                  ifelse(GLUCOSE_HBA1C_CLASS == "3. HBA1C >= 48" | GLUCOSE_FPG_CLASS == "3. FPG >= 7", "Yes", "No")),
         `Blood pressure` = ifelse(BP_CLASS == "0. Missing", "Missing",
                                   ifelse(BP_CLASS == "3. High", "Yes", "No")),
         `BMI` = ifelse(BMI_CLASS == "0. Missing", "Missing",
                        ifelse(BMI_CLASS %in% c("4. Obese", "5. Severe obese"), "Yes", "No")),
         `Cholesterol (ratio)` = ifelse(CHOL_RATIO_CLASS == "0. Missing", "Missing",
                                      ifelse(CHOL_RATIO_CLASS == "2. more than 4", "Yes", "No")),
         `Cholesterol (total)` = ifelse(CHOL_TOTAL_CLASS == "0. Missing", "Missing",
                                      ifelse(CHOL_TOTAL_CLASS %in% c("2. 5 - 7.5", "3. more than 7.5"), "Yes", "No")),
         `Family history CVD` = ifelse(is.na(CVD_FAMILY), "No", 
                                       ifelse(CVD_FAMILY == "FIRST_DEGREE_U60_CVD", "Yes", "No")),
         `Physical activity` = ifelse(PHYS_ACTIVITY_CLASS == "0. Missing", "Missing",
                                       ifelse(PHYS_ACTIVITY_CLASS %in% c("4. Inactive", "3. Moderately Inactive"), "Yes", "No")),
         `CVD risk score` = ifelse(CVD_RISK_SCORE_CLASS == "0. Missing", "Missing",
                          ifelse(CVD_RISK_SCORE_CLASS %in% c("2. 10 - 19.99", "3. 20 or more"), "Yes", "No")),
         `Smoking` = ifelse(SMOKING_CLASS == "0. Missing", "Missing",
                         ifelse(SMOKING_CLASS %in% c("3. Smoker"), "Yes", "No")))


# Output APPENDIX E table - attendee / non-attendee breakdowns

plot_data_risks_binary <- patients_table_risks %>% 
  select(COHORT, `Alcohol`, `Blood glucose`, `Blood pressure`, `BMI`, `Cholesterol (ratio)`,
         `Cholesterol (total)`, `Family history CVD`, `Physical activity`, `CVD risk score`,
         `Smoking`) %>% 
  pivot_longer(cols = `Alcohol`:`Smoking`,
               names_to = "risk_factor",
               values_to = "risk_group") %>% 
  group_by(COHORT, risk_factor, risk_group) %>% 
  summarise(count = n()) %>%
  mutate(col_pc = count*100.00/sum(count)) %>% 
  arrange(COHORT, risk_factor, risk_group, -col_pc) %>% 
  ungroup() %>% 
  mutate(risk_group = factor(risk_group, levels = c("Missing", "No", "Yes")),
         COHORT = ifelse(COHORT == "ATTENDEE", "ATTENDEES", "NON-ATTENDEES"))

# Copy to clipboard for pasting
write.table(plot_data_risks_binary, "clipboard", sep="\t", row.names = FALSE)

# ---------------------------------------------------------------------
# C) Figure: Risk factors - binary high risk cut off proportions

# Calculate order to display risk factors in (largest proportion high risk to smallest)
stacked_bar_order <- filter(plot_data_risks_binary, 
                            risk_group == "Yes",
                            COHORT == "ATTENDEES")

plot_data_risks_binary_2 <- plot_data_risks_binary %>% 
                                 mutate(risk_factor = factor(risk_factor, 
                                                             levels = stacked_bar_order$risk_factor[order(desc(stacked_bar_order$col_pc))]))

# OPTION 1 - Plot stacked bar chart ----------------------------------------------

# Define colour codes
plot_colours <- c("#DDDDDD", "#A95AA1", "#0F2080")

# Plot stacked bar chart for high/low risk factors
risks_stacked_barchart <- ggplot(data = plot_data_risks_binary_2,
                             aes(x = risk_factor, 
                                 y = col_pc,
                                 fill = risk_group)) +
  geom_bar(stat = "identity") +
  labs(x = "\nRisk factor",
       y = "% patients",
       fill = "High risk") +
  facet_grid(. ~ COHORT) +
  ggtitle("Risk factor profile of attendees and non-attendees") +
  scale_fill_manual(values = plot_colours) +
  scale_y_continuous(expand = c(0, 1)) +
  # geom_text(aes(label = paste0(round(col_pc, 0), "%")),
  #           colour = "white",
  #           fontface = "bold",
  #           position = position_stack(vjust = 0.5), 
  #           size = 3) +
  theme(legend.title = element_text(face = "bold"),
        axis.title = element_text(face = "bold"),
        axis.text.x = element_text(angle = 45, hjust = 1),
        axis.text = element_text(face = "bold"),
        panel.background = element_rect(fill = "transparent",colour = NA))

# View chart
risks_stacked_barchart

# Save chart
ggsave(risks_stacked_barchart, 
       file = "Plots/risks_stacked_barchart.png",
       width = 10, height = 6)



# OPTION 2 - Plot side by side bars comparing high risk attendees/non-attendees 
risks_dodged_barchart <- ggplot(data = filter(plot_data_risks_binary_2,
                                               risk_group == "Yes"),
                                 aes(x = risk_factor, 
                                     y = col_pc,
                                     fill = COHORT)) +
  geom_bar(stat = "identity", 
           position = "dodge") +
  labs(x = "\nRisk factor",
       y = "% patients",
       fill = "High risk") +
  ggtitle("Proportion of attendees and non-attendees that are high risk by risk factor") +
  scale_fill_manual(values = plot_colours) +
  geom_text(aes(label = paste0(round(col_pc, 0), "%")),
            colour = "white",
            fontface = "bold",
            position = position_dodge(width = 1),
            vjust = 1.3, 
            size = 3) +
  theme(legend.title = element_blank(),
        legend.position = "bottom",
        axis.title = element_text(face = "bold"),
        axis.text.x = element_text(angle = 45, hjust = 1))

# View chart
risks_dodged_barchart

# Save chart
ggsave(risks_dodged_barchart, 
       file = "Plots/risks_dodged_barchart.png",
       width = 10, height = 6)


#--------------------------------------------------------------------------
# TEXT: Type of check (completed by third party)
#--------------------------------------------------------------------------

# Count number of checks completed by third party each year
type_check_year <- patients_table_attendees %>% 
  group_by(FIN_YEAR) %>% 
  summarise(total = n(),
            third_party = sum(COHORT_DETAIL == 'NHSHC completed third party'),
            third_party_pc = sum(COHORT_DETAIL == 'NHSHC completed third party')*100.00/n())

# Count total number of checks completed by third party 
type_check <- patients_table_attendees %>% 
  summarise(FIN_YEAR = 'TOTAL',
            total = n(),
            third_party = sum(COHORT_DETAIL == 'NHSHC completed third party'),
            third_party_pc = sum(COHORT_DETAIL == 'NHSHC completed third party')*100.00/n())

# Combine yearly break down with total
type_check_comb = rbind(type_check_year, type_check)

# View data
View(type_check_comb)                             

# Copy to clipboard for pasting to Excel
write.table(type_check_comb, "clipboard", sep="\t", row.names = FALSE)     


#--------------------------------------------------------------------------
# Appendix: HCP type
#--------------------------------------------------------------------------

# Count patients by HCP type who completed their NHSHC activity record
hcp_total <- patients_table_formatted %>% 
  group_by(outcome, HCP_TYPE) %>% 
  summarise(total = n())

View(hcp_total)

write.table(hcp_total, "clipboard", sep="\t", row.names = FALSE)


#--------------------------------------------------------------------------
# Interventions - advice, referrals, further tests
#--------------------------------------------------------------------------

# Count attendees that were offered each intervention
intervention_volumes <- patients_table_risks %>% 
                      filter(COHORT == "ATTENDEE") %>% 
                      summarise(group = "No attendees",
                                support_alcohol_total = sum(!is.na(ADVICE_ALCOHOL) | !is.na(REFERRAL_ALCOHOL)),
                                support_diet_total = sum(!is.na(ADVICE_DIET) | !is.na(REFERRAL_DIET)),
                                support_exercise_total = sum(!is.na(ADVICE_EXERCISE) | !is.na(REFERRAL_EXERCISE)),
                                support_lifestyle_total = sum(!is.na(ADVICE_LIFESTYLE) | !is.na(REFERRAL_LIFESTYLE)),
                                support_smoking_total = sum(!is.na(ADVICE_SMOKING) | !is.na(REFERRAL_SMOKING)),
                                support_weight_total = sum(!is.na(ADVICE_WEIGHT) | !is.na(REFERRAL_WEIGHT)),
                                dpp_referral = sum(!is.na(DPP_REFERRAL)),
                                support_any = sum(!is.na(ADVICE_ALCOHOL) | !is.na(REFERRAL_ALCOHOL) | !is.na(ADVICE_DIET) 
                                                   | !is.na(REFERRAL_DIET) | !is.na(ADVICE_EXERCISE) | !is.na(REFERRAL_EXERCISE) 
                                                   | !is.na(ADVICE_LIFESTYLE) | !is.na(REFERRAL_LIFESTYLE) | !is.na(ADVICE_SMOKING)
                                                   | !is.na(REFERRAL_SMOKING) | !is.na(ADVICE_WEIGHT) | !is.na(REFERRAL_WEIGHT) 
                                                   | !is.na(DPP_REFERRAL)),
                                
                                further_test_acr = sum(!is.na(FURTHER_TEST_ACR)),
                                further_test_diabetes = sum(!is.na(FURTHER_TEST_DIABETES) | !is.na(REFERRAL_DIABETES)),
                                further_test_cvd_high_risk = sum(!is.na(FURTHER_TEST_CVD_HIGH_RISK) | !is.na(FURTHER_TEST_CVD_HIGH_RISK_DECLINED)),
                                further_test_cvd = sum(!is.na(FURTHER_TEST_CVD)),
                                further_test_egfr = sum(!is.na(FURTHER_TEST_EGFR)),
                                further_test_igt = sum(!is.na(FURTHER_TEST_IGT) | !is.na(REFERRAL_IGT_IFG)),
                                referral_ecg = sum(!is.na(REFERRAL_ECG)))


# Count attendees that were offered each intervention AND were high risk in the relevant risk factor                              
intervention_high_risk <- patients_table_risks %>% 
                              filter(COHORT == "ATTENDEE") %>% 
                              summarise(group = "No high risk with intervention",
                                        support_alcohol_total = sum((!is.na(ADVICE_ALCOHOL) | !is.na(REFERRAL_ALCOHOL))
                                                                    & Alcohol == "Yes"), # Full AUDIT 8+
                                        support_diet_total = sum((!is.na(ADVICE_DIET) | !is.na(REFERRAL_DIET))
                                                                 & BMI_CLASS %in% c("3. Overweight", "4. Obese", "5.Severe obese")),
                                        support_exercise_total = sum((!is.na(ADVICE_EXERCISE) | !is.na(REFERRAL_EXERCISE))
                                                                     & `Physical activity` == "Yes"),
                                        support_lifestyle_total = sum((!is.na(ADVICE_LIFESTYLE) | !is.na(REFERRAL_LIFESTYLE))
                                                                      & `CVD risk score` == "Yes"),
                                        support_smoking_total = sum((!is.na(ADVICE_SMOKING) | !is.na(REFERRAL_SMOKING))
                                                                    & Smoking == "Yes"),
                                        support_weight_total = sum((!is.na(ADVICE_WEIGHT) | !is.na(REFERRAL_WEIGHT))
                                                                   & BMI_CLASS %in% c("3. Overweight", "4. Obese", "5.Severe obese")),
                                        dpp_referral = sum(!is.na(DPP_REFERRAL)
                                                           & (GLUCOSE_HBA1C_CLASS %in% c("2. HBA1C < 48") | GLUCOSE_FPG_CLASS %in% c("2. FPG < 7"))),
                                        support_any = sum((!is.na(ADVICE_ALCOHOL) | !is.na(REFERRAL_ALCOHOL) | !is.na(ADVICE_DIET) 
                                                          | !is.na(REFERRAL_DIET) | !is.na(ADVICE_EXERCISE) | !is.na(REFERRAL_EXERCISE) 
                                                          | !is.na(ADVICE_LIFESTYLE) | !is.na(REFERRAL_LIFESTYLE) | !is.na(ADVICE_SMOKING)
                                                          | !is.na(REFERRAL_SMOKING) | !is.na(ADVICE_WEIGHT) | !is.na(REFERRAL_WEIGHT) 
                                                          | !is.na(DPP_REFERRAL)) & `CVD risk score` == "Yes"),
                                        
                                        further_test_acr = sum(!is.na(FURTHER_TEST_ACR) & `Blood pressure` == "Yes"),
                                        further_test_diabetes = sum((!is.na(FURTHER_TEST_DIABETES) | !is.na(REFERRAL_DIABETES))
                                                                    & `Blood glucose` == "Yes"),
                                        further_test_cvd_high_risk = sum((!is.na(FURTHER_TEST_CVD_HIGH_RISK) | !is.na(FURTHER_TEST_CVD_HIGH_RISK_DECLINED))
                                                                         & `CVD risk score` == "Yes"),
                                        further_test_cvd = sum(!is.na(FURTHER_TEST_CVD) & `CVD risk score` == "Yes"),
                                        further_test_egfr = sum(!is.na(FURTHER_TEST_EGFR) & `Blood pressure` == "Yes"),
                                        further_test_igt = sum((!is.na(FURTHER_TEST_IGT) | !is.na(REFERRAL_IGT_IFG)) & `Blood glucose` == "Yes"),
                                        referral_ecg = sum(!is.na(REFERRAL_ECG) & PULSE %in% c("IRREGULAR")))


# Count attendees that should have received each intervention (i.e. are high risk)                                
attendee_high_risk <- patients_table_risks %>% 
                            filter(COHORT == "ATTENDEE") %>% 
                            summarise(group = "No high risk",
                                      support_alcohol_total = sum(Alcohol == "Yes"), # Full AUDIT 8+
                                      support_diet_total = sum(BMI_CLASS %in% c("3. Overweight", "4. Obese", "5.Severe obese")),
                                      support_exercise_total = sum(`Physical activity` == "Yes"),
                                      support_lifestyle_total = sum(`CVD risk score` == "Yes"),
                                      support_smoking_total = sum(Smoking == "Yes"),
                                      support_weight_total = sum(BMI_CLASS %in% c("3. Overweight", "4. Obese", "5.Severe obese")),
                                      dpp_referral = sum((GLUCOSE_HBA1C_CLASS %in% c("2. HBA1C < 48") | GLUCOSE_FPG_CLASS %in% c("2. FPG < 7"))),
                                      support_any = sum(`CVD risk score` == "Yes"),
                                      
                                      further_test_acr = sum(`Blood pressure` == "Yes"),
                                      further_test_diabetes = sum(`Blood glucose` == "Yes"),
                                      further_test_cvd_high_risk = sum(`CVD risk score` == "Yes"),
                                      further_test_cvd = sum(`CVD risk score` == "Yes"),
                                      further_test_egfr = sum(`Blood pressure` == "Yes"),
                                      further_test_igt = sum(`Blood glucose` == "Yes"),
                                      referral_ecg = sum(PULSE %in% c("IRREGULAR")))


# Count attendees that declined each intervention                                
interventions_declined <- patients_table_risks %>% 
                                filter(COHORT == "ATTENDEE") %>% 
                                summarise(group = "No declined",
                                          support_alcohol_total = sum(!is.na(ADVICE_ALCOHOL_DECLINED) | !is.na(REFERRAL_ALCOHOL_DECLINED)), # Full AUDIT 8+
                                          support_diet_total = sum(!is.na(ADVICE_DIET_DECLINED) | !is.na(REFERRAL_DIET_DECLINED)),
                                          support_exercise_total = sum(!is.na(ADVICE_EXERCISE_DECLINED) | !is.na(REFERRAL_EXERCISE_DECLINED)),
                                          support_lifestyle_total = sum(!is.na(ADVICE_LIFESTYLE_DECLINED)),
                                          support_smoking_total = sum(!is.na(ADVICE_SMOKING_DECLINED) | !is.na(REFERRAL_SMOKING_DECLINED)),
                                          support_weight_total = sum(!is.na(ADVICE_WEIGHT_DECLINED) | !is.na(REFERRAL_WEIGHT_DECLINED)),
                                          dpp_referral = sum(!is.na(DPP_REFERRAL_DECLINED)),
                                          support_any = NA,
                                          
                                          further_test_acr = NA,
                                          further_test_diabetes = NA,
                                          further_test_cvd_high_risk = sum(!is.na(FURTHER_TEST_CVD_HIGH_RISK_DECLINED)),
                                          further_test_cvd = NA,
                                          further_test_egfr = NA,
                                          further_test_igt = NA,
                                          referral_ecg = NA)

# Combine counts together  
interventions <- rbind(intervention_volumes, intervention_high_risk, attendee_high_risk, interventions_declined)

# View data
View(interventions)

# Copy to clipboard for pasting to Excel
write.table(interventions, "clipboard", sep="\t", row.names = FALSE)



# Attendance rates by UTLA ------------------------------------------------

# Sum invitees and attendees by financial year
gpes_utla_all <- patients_table_formatted %>% 
  group_by(UTLA_CODE_PAT, UTLA_PAT) %>% 
  summarise(invitees = n()) 

gpes_utla_attendees <- patients_table_attendees %>% 
  group_by(UTLA_CODE_PAT, UTLA_PAT) %>% 
  summarise(attendees = n())

# Join attendee and invitee counts, calculating 95% confidence interval for attendance rate
gpes_utla <- gpes_utla_all %>% 
  left_join(gpes_utla_attendees, by = c("UTLA_CODE_PAT", "UTLA_PAT")) %>%
  group_by(UTLA_CODE_PAT, UTLA_PAT) %>%  
  mutate(attendance_rate = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[1],
         CI_lower = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[2],
         CI_upper = 100*(DescTools::BinomCI(attendees, invitees, conf.level = 0.95, method = "wilson"))[3]) %>% 
  arrange(-attendance_rate)

# Copy to clipboard for pasting into Excel
write.table(gpes_utla, "clipboard", sep="\t", row.names = FALSE)
