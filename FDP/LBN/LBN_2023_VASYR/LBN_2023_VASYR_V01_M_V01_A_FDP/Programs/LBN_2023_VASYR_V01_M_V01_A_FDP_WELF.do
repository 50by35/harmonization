/* =====================================================================
LBN_2023_VASYR_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Lebanon VASyR (Vulnerability
Assessment of Syrian Refugees) 2023 round to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Lebanon/LBN_refugee_hhold.dta
         $REFUGEE_RAW_DATA/Lebanon/LBN_refugee_ind.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/LBN_2023_VASYR_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Lebanon 2023 block).
Sample: refugees only — Syrian household head (head_nationality==Syria).
Lebanese-headed and other-nationality households are dropped.
Welfare is CONSUMPTION (consagg, annualized), consistent with VASyR's
own poverty methodology. welfare_type = 1.
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

* ---- individual + household level -----------------------------------------
use `"`rawroot'/Lebanon/LBN_refugee_ind.dta"', clear
merge m:1 hhid using `"`rawroot'/Lebanon/LBN_refugee_hhold.dta"', ///
    keep(3) nogen keepusing(consagg CAwosocialasst head_nationality hhsize)

* refugees only: Syrian household head (head_nationality is numeric,
* value-labeled with country names)
keep if head_nationality==192

* survey rounds pooled to the 2023 file are relabeled 2023 in the source
* (some interviews carried out in late 2022 under the same VASyR round)
recode year (2022=2023)

* ---- schema variables ----------------------------------------------------
gen str3 code = "LBN"
gen      survname    = "VASYR"

* welfare: annualized per-capita consumption (consagg), '000 LBP.
* welfare_type = 1 (consumption).
gen double welfare = consagg*1000

* welfare_self: consumption net of social assistance, provided directly
* by the source (CAwosocialasst). Floored at zero for schema compliance.
gen double welfare_self = max(CAwosocialasst, 0)*1000

gen byte welfare_type = 1

* hhid already string; pid is numeric (per-household sequence number)
tostring pid, replace

gen double weight2 = weight
drop weight
rename weight2 weight

* camp: not applicable — VASyR samples Syrian refugees across Lebanon
* (no formal camps); leave missing (schema allows missing camp).
gen byte camp = .

* urban: source is 3-category (Urban/Semi Urban/Rural); semi-urban
* counted as urban, per the report replicability package's convention.
gen byte urban2 = (urban==1 | urban==2)
drop urban
rename urban2 urban

* optional variables
gen int    hhsize2 = hhsize
drop hhsize
rename hhsize2 hhsize
gen byte   male    = 2 - gender       // source: 1 Male / 2 Female
* edu_level: 1 None, 2-5 Pre-school..Complementary Technical, 6-7 Secondary,
* 8-15 University/technical tertiary, 16 Other (unclassifiable -> missing),
* -1 Don't know (-> missing)
recode edu_level (1=1) (2/5=2) (6/7=3) (8/15=4) (16=.) (-1=.), gen(educat4)
gen byte   empstat = LFstatus         // source already 1 Employed 2 Unemployed 3 Outside LF
replace    empstat = 4 if missing(empstat) & age < 15

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
save "`outdir'/LBN_2023_VASYR_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/LBN_2023_VASYR_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
