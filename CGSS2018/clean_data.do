********************************************************************************
* Clean CGSS 2018: 
* keep happiness, wtp_air3, age, female, educ_years, health, rural_hukou, married
********************************************************************************

clear all
set more off

* Change this path if needed
use "CGSS2018_PUBLIC.dta", clear

********************************************************************************
* 1. Keep only variables needed for analysis
********************************************************************************

keep ///
    id provinces community_i type ///
    a36 e76b ///
    a2 a31 a32 a33 a4 a7a a7b a8a a8b a10 a15 a18 a21 a69 a62 ///
    weight weight_raking

********************************************************************************
* 2. Rename variables
********************************************************************************

rename provinces     province_name
rename community_i   community_code
rename type          community_type

rename a36           happiness
rename e76b          wtp_air3

rename a2            sex
rename a31           birth_year
rename a32           birth_month
rename a33           birth_day
rename a4            ethnicity
rename a7a           education
rename a7b           education_status
rename a8a           personal_income
rename a8b           labor_income
rename a10           political_status
rename a15           health
rename a18           hukou_status
rename a21           hukou_location
rename a69           marital_status
rename a62           household_income

********************************************************************************
* 3. Clean special missing-value codes
********************************************************************************

* Happiness: 1 to 5; 98 = don't know, 99 = refuse
replace happiness = . if inlist(happiness, 98, 99)

* WTP: remove non-substantive response codes
replace wtp_air3 = . if wtp_air3 >= 9998
replace wtp_air3 = . if wtp_air3 < 0

* Other categorical variables with 98/99 codes
foreach v in birth_month birth_day education_status political_status health {
    replace `v' = . if inlist(`v', 98, 99)
}

* Income variables: CGSS uses large values such as 9999997/9999998/9999999
* for non-substantive responses
foreach v in personal_income labor_income household_income {
    replace `v' = . if `v' >= 9999996
    replace `v' = . if `v' < 0
}

********************************************************************************
* 4. Generate clean demographic controls
********************************************************************************

* Age in 2018
gen age = 2018 - birth_year
replace age = . if age < 18 | age > 100

* Gender
gen female = .
replace female = 0 if sex == 1
replace female = 1 if sex == 2
label define female_lab 0 "Male" 1 "Female"
label values female female_lab

* Ethnicity
gen minority = .
replace minority = 0 if ethnicity == 1
replace minority = 1 if ethnicity != 1 & !missing(ethnicity)
label define minority_lab 0 "Han" 1 "Ethnic minority"
label values minority minority_lab

* Approximate years of schooling
gen educ_years = .
replace educ_years = 0  if education == 1
replace educ_years = 2  if education == 2
replace educ_years = 6  if education == 3
replace educ_years = 9  if education == 4
replace educ_years = 12 if inlist(education, 5, 6, 7, 8)
replace educ_years = 15 if inlist(education, 9, 10)
replace educ_years = 16 if inlist(education, 11, 12)
replace educ_years = 19 if education == 13

* Log income controls
gen ln_personal_income  = ln(personal_income + 1)
gen ln_labor_income     = ln(labor_income + 1)
gen ln_household_income = ln(household_income + 1)

* Hukou controls
gen rural_hukou = .
replace rural_hukou = 1 if hukou_status == 1
replace rural_hukou = 0 if inlist(hukou_status, 2, 3, 4)

* Marital status
gen married = .
replace married = 1 if inlist(marital_status, 3, 4)
replace married = 0 if inlist(marital_status, 1, 2, 5, 6, 7)

* Political status
gen ccp_member = .
replace ccp_member = 1 if political_status == 4
replace ccp_member = 0 if inlist(political_status, 1, 2, 3)

* Community type: 1 = neighborhood committee, 2 = village committee
gen urban_community = .
replace urban_community = 1 if community_type == 1
replace urban_community = 0 if community_type == 2

* Province fixed effect variable
encode province_name, gen(province_id)

* Log WTP outcome, useful because WTP has many zeros and is skewed
gen ln_wtp_air3 = ln(wtp_air3 + 1)

********************************************************************************
* 5. Label key variables
********************************************************************************

label variable happiness          "Self-reported happiness, 1-5"
label variable wtp_air3           "WTP for 3 more good-air days in 2018"
label variable ln_wtp_air3        "Log(WTP + 1)"
label variable age                "Age in 2018"
label variable female             "Female respondent"
label variable minority           "Ethnic minority"
label variable educ_years         "Approximate years of schooling"
label variable rural_hukou        "Agricultural/rural hukou"
label variable married            "Currently married"
label variable ccp_member         "CCP member"
label variable urban_community    "Urban neighborhood committee"
label variable province_id        "Province fixed effect ID"

********************************************************************************
* 6. Keep final regression-ready variables
********************************************************************************

keep ///
    id province_name province_id community_code community_type urban_community ///
    happiness wtp_air3 ln_wtp_air3 ///
    sex female birth_year age ethnicity minority ///
    education education_status educ_years ///
    personal_income labor_income household_income ///
    ln_personal_income ln_labor_income ln_household_income ///
    political_status ccp_member health hukou_status rural_hukou hukou_location ///
    marital_status married ///
    weight weight_raking

order ///
    id province_name province_id community_code community_type urban_community ///
    happiness wtp_air3 ln_wtp_air3 ///
    female age minority educ_years health rural_hukou married ccp_member ///
    personal_income labor_income household_income ///
    ln_personal_income ln_labor_income ln_household_income ///
    weight weight_raking

compress

keep if !missing(happiness, wtp_air3, age, female, educ_years, health, rural_hukou, married)
export delimited using "CGSS2018_clean_main.csv", replace nolabel