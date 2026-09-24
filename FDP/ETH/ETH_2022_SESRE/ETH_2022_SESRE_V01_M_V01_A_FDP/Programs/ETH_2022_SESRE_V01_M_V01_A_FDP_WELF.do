/* =====================================================================
ETH_2022_SESRE_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Ethiopia SESRE (Socioeconomic Survey
of Refugees and Host Communities) 2022 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Ethiopia/ETH_SESRE_consumption_hh_level.dta
         $REFUGEE_RAW_DATA/Ethiopia/ETH_SESRE_household_level.dta
         $REFUGEE_RAW_DATA/Ethiopia/ETH_SESRE_individual level.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/ETH_2022_SESRE_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Ethiopia 2022 block), with
welfare_self derived directly from the consumption file rather than
the household file's income-based aid variable (which the source
package found produced implausible negative values for some
households — see harmonized.do lines 910-911).
Sample: refugees only — sample_type 2 (out-of-camp) or 3 (in-camp).
Host communities (sample_type 1) are dropped.
Welfare is CONSUMPTION (total_exp, real Dec 2022 prices, annualized),
consistent with SESRE's own poverty methodology. welfare_type = 1.
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

* ---- consumption (household level) ----------------------------------------
use `"`rawroot'/Ethiopia/ETH_SESRE_consumption_hh_level.dta"', clear

* refugees only: out-of-camp (2) or in-camp (3)
keep if inlist(sample_type, 2, 3)

* welfare: total consumption expenditure, real Dec 2022 prices,
* per capita, annualized (LCU, ETB). welfare_type = 1 (consumption).
gen double welfare = total_exp/hhsize

* welfare_self: pre-assistance total consumption expenditure
* (total_exp_pre), same real-price basis as total_exp. A handful of
* households have small negative pre-assistance residuals (data noise
* near zero) — floored at zero. A separate handful have
* total_exp_pre > total_exp (deflation-component noise) — capped at
* welfare for schema compliance.
gen double welfare_self = max(total_exp_pre, 0)/hhsize
replace    welfare_self = welfare if welfare_self > welfare & !missing(welfare)

* ---- merge household roster + individuals ---------------------------------
merge 1:1 household_id using `"`rawroot'/Ethiopia/ETH_SESRE_household_level.dta"', ///
    keep(3) nogen keepusing(wq6901)
merge 1:m household_id using `"`rawroot'/Ethiopia/ETH_SESRE_individual level.dta"', ///
    keep(3) nogen

* ---- schema variables ----------------------------------------------------
gen str3 code = "ETH"
gen int  year        = svy_year
recode year (2023=2022)   // a handful of interviews spilled into early 2023
gen      survname    = "SESRE"

rename household_id hhid
rename member_id    pid

gen byte   welfare_type = 1
gen double weight       = wgt1        // HH weight applied to each member

* camp: in-camp refugees are camp==1; out-of-camp refugees (OCP) are
* camp==0 regardless of the wq6901 OCP-residence flag being sparsely filled
gen byte camp = (sample_type==3)

* urban: hosts use rur_urb; refugees don't have a comparable rural/urban
* split in this file, so urban is left missing for refugees (schema allows)
gen byte urban = .

* optional variables
gen int    hhsize2 = hhsize
drop hhsize
rename hhsize2 hhsize
gen double age = wq1105_year
replace    age = . if !inrange(age, 0, 120)
gen byte   male = (wq1104==1)          // source: "1. Male" / "2. Female"

* educat4: highest grade completed (wq2109), mapped to 4 broad categories.
* Codes: 1-8 Grade 1-8; 9-24 Grade 9-12/TVET/10+1/10+2; 25-33 college/
* university and postgraduate; 34-36 10+3 diploma (tertiary); 37-45
* pre-school/ABE/adult-education (primary-equivalent or below); 46
* diploma (tertiary, level unspecified); 96 informal (primary-equivalent);
* 97 don't know; 98 never attended school.
gen byte educat4 = 1
replace  educat4 = 2 if inrange(wq2109, 1, 8) | inrange(wq2109, 37, 45) | wq2109==96
replace  educat4 = 3 if inrange(wq2109, 9, 24)
replace  educat4 = 4 if inrange(wq2109, 25, 36) | wq2109==46
replace  educat4 = . if missing(wq2107) | wq2109==97   // not asked / don't know
replace  educat4 = 1 if wq2107==0 | wq2109==98         // never attended school

gen byte empstat = 1 if wq1205==1
replace  empstat = 1 if wq1205==0 & inlist(wq1206, 1, 2)
replace  empstat = 3 if wq1205==0 & wq1206==3 & wq1207a==3
replace  empstat = 2 if wq1205==0 & wq1206==3 & inlist(wq1207a, 1, 2)
replace  empstat = 4 if missing(empstat) & age < 15

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
save "`outdir'/ETH_2022_SESRE_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/ETH_2022_SESRE_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
