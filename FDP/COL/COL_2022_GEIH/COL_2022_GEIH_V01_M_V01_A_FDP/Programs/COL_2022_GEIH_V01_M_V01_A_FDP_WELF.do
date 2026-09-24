/* =====================================================================
COL_2022_GEIH_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Colombia GEIH 2022 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Colombia/GEIH/individual_data_2022.dta
         $REFUGEE_RAW_DATA/Colombia/GEIH/household_data_2022.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/COL_2022_GEIH_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Colombia 2022 block).
Sample: refugees only — Venezuelan migrants (refugee==1), excluding
persons born in Colombia (cbirth==170).
Welfare is INCOME (ingpcug, monthly per capita of the expenditure
unit); annualized here per the schema. welfare_type = 2.
===================================================================== */

version 18
clear
set more off

* ---- raw data source ------------------------------------------------------
* Reads from REFUGEE_RAW_DATA. The same files can also be fetched from
* datalibweb's FDPRAW collection instead (see chapters/04-access.qmd,
* requires the datalibweb Stata package + a registered token) — swap the
* `use`/`merge...using` lines below for a datalibweb call if needed.
local rawroot : env REFUGEE_RAW_DATA
if `"`rawroot'"' == "" {
    di as error "Set REFUGEE_RAW_DATA to the raw-data root folder"
    exit 601
}
local outdir : env FIFTYBY35_PROCESSED
if `"`outdir'"' == "" local outdir "~/Github/50by35-data/data/processed"

* ---- merge individual and household data ---------------------------------
use `"`rawroot'/Colombia/GEIH/individual_data_2022.dta"', clear
merge m:1 hhid using `"`rawroot'/Colombia/GEIH/household_data_2022.dta"', keep(3) nogen

* refugees only: Venezuelan migrants, excluding the Colombia-born
replace refugee = 0 if cbirth==170
keep if refugee==1

* ---- schema variables ----------------------------------------------------
gen str3 code = "COL"
gen int  year        = survey_year
gen      survname    = "GEIH"

* welfare: official GEIH income aggregate ingpcug (monthly per capita of
* the expenditure unit, denominator npersug), annualized to LCU (COP).
gen double welfare = ingpcug*12

* welfare_self: net out institutional/government assistance
* (inc_transf_inst, monthly HH total), per capita on the same
* denominator as ingpcug, floored at zero.
gen double welfare_self = max(ingpcug - inc_transf_inst/npersug, 0)*12

* households without an income aggregate cannot conform to the schema
qui count if missing(welfare)
di as txt "Dropping " r(N) " observations with missing income aggregate"
drop if missing(welfare)

* schema requires welfare > 0: zero-income households cannot conform
qui count if welfare<=0
di as txt "Dropping " r(N) " observations with zero income (schema requires welfare > 0)"
drop if welfare<=0

* identifiers already strings (hhid str8, personid str10)
rename personid pid

gen byte   welfare_type = 2           // income
gen double weight2      = weight      // individual sampling weight
drop weight
rename weight2 weight

gen byte camp = .                     // not applicable in GEIH (missing allowed)

* optional variables
gen int  hhsize  = nper
gen double age2  = age
drop age
rename age2 age
replace age = . if !inrange(age, 0, 120)   // guard against sentinel codes
gen byte male    = gender             // source: 0 Female / 1 Male
gen byte educat4 = edulev             // 1 None … 4 Some tertiary (15+)
gen byte empstat = empl_status        // 1 Employed 2 Unemployed 3 Inactive (15+)
replace  empstat = 4 if missing(empstat) & age < 15   // not applicable

gen byte urban2 = urban               // source: 0 Rural / 1 Urban
drop urban
rename urban2 urban

* ---- labels per the 50by35 schema ----------------------------------------
label drop _all
label define welfare_type 1 "Consumption" 2 "Income" 3 "Expenditure"
label define male    0 "Female" 1 "Male"
label define urban   0 "Rural" 1 "Urban"
label define camp    0 "Non-camp" 1 "Camp"
label define educat4 1 "No education" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label define empstat 1 "Employed" 2 "Unemployed" 3 "Out of labor force" 4 "Not applicable"
foreach v in welfare_type male urban camp educat4 empstat {
    label values `v' `v'
}

label variable code  "Country code"
label variable year         "Survey year"
label variable survname     "Survey name"
label variable hhid         "Household identifier"
label variable pid          "Person identifier"
label variable welfare      "Welfare aggregate (LCU, annual per capita)"
label variable welfare_type "Welfare measure type"
label variable welfare_self "Self-reliance-adjusted welfare (LCU, annual per capita)"
label variable weight       "Sampling weight"
label variable camp         "Camp/non-camp"
label variable urban        "Urban/rural"
label variable hhsize       "Household size"
label variable age          "Age"
label variable male         "Sex"
label variable educat4      "Highest education (4 cat.)"
label variable empstat      "Employment status"

keep  code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat
order code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat

isid hhid pid
compress
save "`outdir'/COL_2022_GEIH_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/COL_2022_GEIH_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
