/* =====================================================================
UGA_2018_RHS_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Uganda Refugee & Host Communities
Household Survey 2018 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Uganda/UGA_hh.dta
         $REFUGEE_RAW_DATA/Uganda/UGA_ind.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/UGA_2018_RHS_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Uganda 2018 block).
Sample: refugees only (refugee_status==1).
Note the raw HH file codes urban 0=Urban/1=Rural (inverted); it is
recoded here, as in the report package.
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

* ---- household level ----------------------------------------------------
use `"`rawroot'/Uganda/UGA_hh.dta"', clear
drop region child   // clash with individual-level names downstream

* welfare: monthly nominal HH consumption (cons_agg), annualized,
* per capita, in LCU (UGX). welfare_type = 1 (consumption).
gen double welfare = cons_agg*12/hh_size

* welfare_self: the source provides consumption net of aid directly
* (cons_agg_less_aid). Floor at zero and cap at welfare.
gen double welfare_self = max(cons_agg_less_aid, 0)*12/hh_size
replace    welfare_self = welfare if welfare_self > welfare & !missing(welfare)

* fix inverted urban coding (0=Urban/1=Rural in the raw HH file)
recode urban (1=0) (0=1)

* ---- merge individuals ---------------------------------------------------
merge 1:m hh using `"`rawroot'/Uganda/UGA_ind.dta"', keep(3) nogen ///
    keepusing(pid age gender high_edu_lev_18p emp_stat country_3digit survey_year)

* refugees only
keep if refugee_status==1

* households without a consumption aggregate cannot conform to the schema
qui count if missing(welfare)
di as txt "Dropping " r(N) " observations with missing consumption aggregate"
drop if missing(welfare)

* ---- schema variables ----------------------------------------------------
gen str3 code = country_3digit
gen int  year        = survey_year
gen      survname    = "RHS"

rename hh hhid                        // str32
tostring pid, replace force

gen byte   welfare_type = 1
gen double weight2      = weight      // HH weight applied to each member
drop weight
rename weight2 weight

* camp: report convention for this survey — refugee settlements are the
* rural stratum (camp = 1 if rural). Confirm with the methodology team.
gen byte camp = cond(missing(urban), ., urban==0)

* optional variables
gen int    hhsize = hh_size
gen double age2   = age
drop age
rename age2 age
replace age = . if !inrange(age, 0, 120)   // guard against sentinel codes
gen byte male     = gender            // source: 0 Female / 1 Male
recode high_edu_lev_18p (0 1 = 1) (2 3 = 2) (4 = 3) (5 = 4), gen(educat4)
gen byte empstat  = emp_stat          // 1 Employed 2 Unemployed 3 Outside LF
replace  empstat  = 4 if missing(empstat) & age < 15   // not applicable

gen byte urban2 = urban
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
save "`outdir'/UGA_2018_RHS_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/UGA_2018_RHS_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
