/* =====================================================================
PSE_2023_PECS_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize West Bank and Gaza PECS 2023 to the
50by35 schema

Inputs : $REFUGEE_RAW_DATA/Palestine/PSE 2023 household variables.dta
         $REFUGEE_RAW_DATA/Palestine/PSE 2023 individual variables.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/PSE_2023_PECS_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, West Bank and Gaza 2023 block).
Sample: refugees only (refugee==1) — registered Palestine refugees per
UNRWA criteria, resident in the West Bank or Gaza.
Welfare is CONSUMPTION (cons_pc_d_day, already real per-capita per-day),
consistent with PECS's own poverty methodology. welfare_type = 1.
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
use `"`rawroot'/Palestine/PSE 2023 household variables.dta"', clear

* welfare: consumption per capita per day, already real/deflated
* (cons_pc_d_day), annualized to LCU (NIS). welfare_type = 1 (consumption).
gen double welfare = cons_pc_d_day*365

* welfare_self: the source provides HH nominal consumption both with
* (cons_hh_n) and without (cons_hh_n_noaid) aid. cons_pc_d_day's exact
* deflation chain is not reproducible from the documented variables, so
* welfare_self is obtained by applying the with/without-aid ratio
* observed in nominal terms to the deflated welfare measure — this
* preserves welfare_self <= welfare by construction. Floored at zero.
gen double ratio        = cons_hh_n_noaid/cons_hh_n
gen double welfare_self = max(welfare*ratio, 0)
drop ratio

* ---- merge individuals ---------------------------------------------------
merge 1:m hhid using `"`rawroot'/Palestine/PSE 2023 individual variables.dta"', ///
    keep(3) nogen keepusing(pid year weight region urban refugee camp d6 ///
    educ_attainment enrolled empl_status)

* refugees only
keep if refugee==1

* ---- schema variables ----------------------------------------------------
gen str3 code = "PSE"
* year already present from the individual file
gen      survname    = "PECS"

tostring hhid, replace
tostring pid, replace

gen byte   welfare_type = 1
* weight: HH weight already named `weight` from the individual file

* camp: source urban already folds camp in as category 2
gen byte camp2 = (urban==2)
drop camp
rename camp2 camp

* optional variables
gen int    hhsize2 = hhsize
drop hhsize
rename hhsize2 hhsize
gen double age    = d6
replace    age    = . if !inrange(age, 0, 120)
gen byte   educat4 = educ_attainment  // source already 1 No educ … 4 Tertiary
gen byte   empstat = empl_status      // source already 1 Employed 2 Unemployed 3 Inactive
replace    empstat = 4 if missing(empstat) & age < 15

* urban: fold camp into urban (camps are predominantly urban-classified
* localities); keep the binary 0/1 required by the schema
gen byte urban2 = (urban==1 | urban==2)
drop urban
rename urban2 urban

* ---- labels per the 50by35 schema ----------------------------------------
label drop _all
label define welfare_type 1 "Consumption" 2 "Income" 3 "Expenditure"
label define urban   0 "Rural" 1 "Urban"
label define camp    0 "Non-camp" 1 "Camp"
label define educat4 1 "No education" 2 "Primary" 3 "Secondary" 4 "Tertiary"
label define empstat 1 "Employed" 2 "Unemployed" 3 "Out of labor force" 4 "Not applicable"
foreach v in welfare_type urban camp educat4 empstat {
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
save "`outdir'/PSE_2023_PECS_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/PSE_2023_PECS_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
