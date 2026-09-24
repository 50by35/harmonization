/* =====================================================================
JOR_2023_VAF_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Jordan VAF (Vulnerability Assessment
Framework) 2023 round to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Jordan/harmonize_household.dta
         $REFUGEE_RAW_DATA/Jordan/harmonize_individual.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/JOR_2023_VAF_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Jordan 2021/2023 block). The raw
household/individual files pool both VAF rounds (2021 and 2023) in one
file, distinguished by `year` — this script keeps only the 2023 round;
see JOR_2021_VAF_V01_M_V01_A_FDP_WELF.do for the 2021 round.
Sample: Syrian refugees, urban (Nationality==1) and camp (Nationality==2).
Non-Syrian refugees (Nationality==3) are dropped, consistent with the
50by35 monitoring population (Syrian refugee response only). The VAF
covers Syrian refugees only — no Jordanian host sample.
Welfare is CONSUMPTION (pce, monthly per capita including estimated camp
rent/utilities), annualized here per the schema. welfare_type = 1.
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
use `"`rawroot'/Jordan/harmonize_household.dta"', clear

* this round only: the raw file pools both 2021 and 2023
keep if year==2023

* refugees only: Syrian nationality (urban or camp)
keep if inlist(Nationality, 1, 2)

* welfare: consumption per capita per day (pce), annualized to LCU (JOD).
* welfare_type = 1 (consumption).
gen double welfare = pce*365

* welfare_self: the source provides consumption net of assistance
* directly (pce_without_assistance = pce - assistance_total). Floored
* at zero — small negative residuals occur for a handful of households.
gen double welfare_self = max(pce_without_assistance, 0)*365

* identifiers: rebuild hhid from Residence/Form/id (no single hhid var)
tostring id, gen(id_str)
gen hhid = string(Residence) + "_" + Form + "_" + id_str
drop id_str

* ---- merge individuals ---------------------------------------------------
* (drop the individual file's own case weight — HH weight above applies)
merge 1:m year Residence Form id using `"`rawroot'/Jordan/harmonize_individual.dta"', ///
    keep(3) nogen keepusing(ind_id IndAge AdultEducatio IndEnrolledSchool ///
    IndDoYouWork NoWorkReason)

* ---- schema variables ----------------------------------------------------
gen str3 code = "JOR"
* year already present from both files
gen      survname    = "VAF"

tostring ind_id, gen(pid)

gen byte   welfare_type = 1
* weight: HH weight already named `weight` in the household file

gen byte camp = (Nationality==2)          // Syrian camp vs. Syrian urban
gen byte urban = .                        // VAF has no separate urban/rural concept
                                           // (schema allows urban to be missing)

* optional variables
gen int    hhsize = householdsize
gen double age    = IndAge
replace    age    = . if !inrange(age, 0, 120)

gen byte educat4 = 1
replace  educat4 = 2 if inlist(AdultEducatio, "BasicSchool", "Kindergarten")
replace  educat4 = 3 if inlist(AdultEducatio, "SecondarySchool", "VocationalEducation")
replace  educat4 = 4 if inlist(AdultEducatio, "HigherEducation", "HigherEducationBachelor", ///
                                "HigherEducationDiploma", "HigherEducationPost-Bachelo")
replace  educat4 = . if AdultEducatio == ""

gen byte empstat = 1 if IndDoYouWork=="Yes"
replace  empstat = 2 if IndDoYouWork=="No" & NoWorkReason=="Unemployed"
replace  empstat = 3 if IndDoYouWork=="No" & NoWorkReason!="Unemployed" & NoWorkReason!=""
replace  empstat = 4 if missing(empstat) & age < 15

* ---- labels per the 50by35 schema ----------------------------------------
label drop _all
label define welfare_type 1 "Consumption" 2 "Income" 3 "Expenditure"
label define camp    0 "Non-camp" 1 "Camp"
label define urban   0 "Rural" 1 "Urban"
label define educat4 1 "No education" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label define empstat 1 "Employed" 2 "Unemployed" 3 "Out of labor force" 4 "Not applicable"
foreach v in welfare_type camp urban educat4 empstat {
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
label variable educat4      "Highest education (4 cat.)"
label variable empstat      "Employment status"

keep  code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age educat4 empstat
order code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age educat4 empstat

isid hhid pid
compress
save "`outdir'/JOR_2023_VAF_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/JOR_2023_VAF_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
