/* =====================================================================
CRI_2024_ENAHO_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Costa Rica ENAHO 2024 to the
50by35 schema

Inputs : $REFUGEE_RAW_DATA/Costa Rica/2024 - households (with ppp21).dta
         $REFUGEE_RAW_DATA/Costa Rica/2024 - individuals (with ppp21).dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/CRI_2024_ENAHO_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Costa Rica 2024 block), with
welfare_self added: the source computed household income components
(inc_asst from timas_hh + ts_hh, assistance/subsidy transfers) but
never netted them out of welfare — this script does, applying the same
household-income-per-capita-PPP-per-day transformation used for welfare.
Sample: refugees only — Nicaraguan-born (lugnac==2), the 50by35
monitoring population for this survey.
Welfare is INCOME (ipcf_a_day_ppp21, already real per-capita per-day,
PPP-adjusted). welfare_type = 2.
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
use `"`rawroot'/Costa Rica/2024 - households (with ppp21).dta"', clear

* welfare: income per capita per day, already real/PPP-adjusted
* (ipcf_a_day_ppp21), annualized to LCU (CRC). welfare_type = 2 (income).
gen double welfare = ipcf_a_day_ppp21*365

* welfare_self: net out assistance/subsidy transfers (timas_hh + ts_hh,
* HH monthly totals) from total household income (itf) before applying
* the same per-capita/PPP/annualization transformation used for welfare.
gen double asst         = timas_hh + ts_hh
gen double ipcf_self    = max(itf - asst, 0)/tamhog
gen double welfare_self = (ipcf_self/ppp21*conversion)*365
replace     welfare_self = welfare if welfare_self > welfare & !missing(welfare)
drop asst ipcf_self

* ---- merge individuals ---------------------------------------------------
merge 1:m hhid using `"`rawroot'/Costa Rica/2024 - individuals (with ppp21).dta"', ///
    keep(3) nogen keepusing(pid lugnac a4 a5 nivinst condact)

* refugees only: Nicaraguan-born
keep if lugnac==2

* households without a positive income aggregate cannot conform to the schema
qui count if missing(welfare) | welfare<=0
di as txt "Dropping " r(N) " observations with missing or zero income"
drop if missing(welfare) | welfare<=0

* ---- schema variables ----------------------------------------------------
* code, year already present as `country`/`year` from the household file
rename country code
gen      survname    = "ENAHO"

gen byte   welfare_type = 2           // income
gen double weight       = factor      // HH weight applied to each member

gen byte camp = .                     // not applicable — no camp population in Costa Rica

* optional variables
gen int    hhsize = tamhog
gen double age    = a5
replace    age    = . if !inrange(age, 0, 120)
gen byte   male   = (a4==1)           // source: 1 Hombre / 2 Mujer

* nivinst: 0 None, 1-2 Primary, 3-6 Secondary, 7-8 Tertiary, 99 Unknown
recode nivinst (0=1) (1/2=2) (3/6=3) (7/8=4) (99=.), gen(educat4)

gen byte empstat = 1 if condact==1
replace  empstat = 2 if condact==2
replace  empstat = 3 if condact==3
replace  empstat = 4 if missing(empstat) & age < 15

gen byte urban2 = (zona==1)
drop zona
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
save "`outdir'/CRI_2024_ENAHO_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/CRI_2024_ENAHO_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
