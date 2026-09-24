/* =====================================================================
NER_2018_EHCVM_V01_M_V01_A_FDP_WELF.do
50by35 pipeline — Step 2: harmonize Niger EHCVM 2018 to the 50by35 schema

Inputs : $REFUGEE_RAW_DATA/Niger/household_NER_2018.dta
         $REFUGEE_RAW_DATA/Niger/individual_NER_2018.dta
         (or datalibweb's FDPRAW collection — see chapters/04-access.qmd)
Output : ${FIFTYBY35_PROCESSED:-data/processed}/NER_2018_EHCVM_V01_M_V01_A_FDP_WELF.dta

Variable construction follows the WB-UNHCR Refugee Welfare Report
replicability package (harmonized.do, Niger 2018 block).
Sample: refugees only — pop_group 2 (refugees from Mali), 3 (refugees
from Nigeria). IDPs (1, "Displaced from Niger"), hosts (4), and
Nigeriens (5) are dropped — the 50by35 monitoring population excludes
internally displaced persons.
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
use `"`rawroot'/Niger/household_NER_2018.dta"', clear

* welfare: HH nominal annual consumption (dtot), spatially deflated,
* per capita, in LCU (XOF). welfare_type = 1 (consumption).
gen double welfare = (dtot/def_spa)/hhsize

* welfare_self: welfare net of aid income (income_aid, annual, HH level),
* floored at zero before deflation so welfare_self >= 0 and <= welfare.
gen double welfare_self = (max(dtot - income_aid, 0)/def_spa)/hhsize

* ---- merge individuals ---------------------------------------------------
merge 1:m grappe menage using `"`rawroot'/Niger/individual_NER_2018.dta"'
keep if _merge==3
drop _merge

* refugees only — excludes IDPs (pop_group==1)
keep if inlist(pop_group, 2, 3)

* households without a consumption aggregate cannot conform to the schema
qui count if missing(welfare)
di as txt "Dropping " r(N) " observations with missing consumption aggregate"
drop if missing(welfare)

* ---- schema variables ----------------------------------------------------
gen str3 code = "NER"
gen int  year        = surveyyear
gen      survname    = "EHCVM"

* identifiers: rebuild hhid from grappe/menage (raw hhid is numeric float)
drop hhid
tostring grappe, gen(g_str) usedisplayformat force
tostring menage, gen(m_str) usedisplayformat force
gen hhid = g_str + "_" + m_str
tostring pid, replace force
drop g_str m_str

gen byte   welfare_type = 1
gen double weight       = hhweight   // HH weight applied to each member

* camp: report convention for this survey — refugee camps are the rural
* strata (camp = 1 if rural). Confirm with the methodology team.
recode urban (.=.), gen(urban2)      // keep source urban (0 rural / 1 urban)
gen byte camp = cond(missing(urban2), ., urban2==0)
drop urban
rename urban2 urban

* optional variables
gen int    hhsize2 = hhsize
drop hhsize
rename hhsize2 hhsize
gen double age     = ageyrs
replace    age     = . if !inrange(age, 0, 120)   // 9999 = unknown in source
gen byte   male    = gender          // source: 0 Female / 1 Male
gen byte   educat4 = education       // source already 1 None … 4 Tertiary
gen byte   empstat = empstatus7      // 1 Employed 2 Unemployed 3 Inactive
replace    empstat = 4 if missing(empstat) & age < 15   // not applicable
gen long   psu     = grappe

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
label variable psu          "Primary sampling unit"

keep  code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat psu
order code year survname hhid pid welfare welfare_type welfare_self weight ///
      camp urban hhsize age male educat4 empstat psu

isid hhid pid
compress
save "`outdir'/NER_2018_EHCVM_V01_M_V01_A_FDP_WELF.dta", replace
di as result "Saved `outdir'/NER_2018_EHCVM_V01_M_V01_A_FDP_WELF.dta (`=_N' refugees)"
